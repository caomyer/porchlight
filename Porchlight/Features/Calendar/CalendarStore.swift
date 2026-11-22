import Foundation
import Observation
import SwiftUI

/// Live calendar state for the wall: the calendars on this iPad, the
/// household's mapping for each, and the resolved events around today (plus
/// whatever range the Calendar screen is looking at).
@MainActor
@Observable
final class CalendarStore: StoredFirstObservable {
    let database: AppDatabase
    /// Whether this device lets Porchlight read its calendars. Stored before observers are
    /// told, like the snapshot: a screen redrawn as access is granted must already read it,
    /// or it keeps asking for access it has (see `AppModel.snapshot`).
    private(set) var access: CalendarAccess {
        get {
            access(keyPath: \.access)
            return storedAccess
        }
        set {
            storedAccess = newValue
            withMutation(keyPath: \.access) {}
        }
    }

    @ObservationIgnored private var storedAccess: CalendarAccess
    /// Calendars the provider currently knows, in display order, stored before observers
    /// are told.
    private(set) var calendars: [ExternalCalendar] {
        get {
            access(keyPath: \.calendars)
            return storedCalendars
        }
        set {
            storedCalendars = newValue
            withMutation(keyPath: \.calendars) {}
        }
    }

    @ObservationIgnored private var storedCalendars: [ExternalCalendar] = []
    /// What the database says now, stored before observers are told (see `AppModel.snapshot`).
    ///
    /// What the devices passed on (`shared`) is told apart: every pass writes its feed, and a
    /// view of this device's own calendars (the settings' menus) must not redraw for it, or an
    /// open menu loses the tap it is given (FirstRunTests, run 45013168902).
    private(set) var snapshot: CalendarSnapshot {
        get {
            access(keyPath: \.snapshot)
            return storedSnapshot
        }
        set {
            let old = storedSnapshot
            storedSnapshot = newValue
            var oldOwn = old, newOwn = newValue
            oldOwn.shared = .empty
            newOwn.shared = .empty
            if oldOwn != newOwn { withMutation(keyPath: \.snapshot) {} }
            if old.shared != newValue.shared { withMutation(keyPath: \.shared) {} }
        }
    }

    /// What every device passed on, observed on its own (see `snapshot`).
    var shared: SharedCalendarSnapshot {
        access(keyPath: \.shared)
        return storedSnapshot.shared
    }

    @ObservationIgnored private var storedSnapshot: CalendarSnapshot = .empty
    /// Resolved events in the loaded window, sorted by start, stored before observers are told.
    private(set) var events: [CalendarEvent] {
        get {
            access(keyPath: \.events)
            return storedEvents
        }
        set {
            storedEvents = newValue
            withMutation(keyPath: \.events) {}
        }
    }

    @ObservationIgnored private var storedEvents: [CalendarEvent] = []
    @ObservationIgnored @StoredFirst var lastError: String? = nil
    /// When this device last passed on, written or not: kept here and never synced, so Sync
    /// details can say "checked 10:02 AM, nothing new" without a write to iCloud.
    private(set) var lastChecked: Date?
    /// How many passes have run, for the test that no pass leads to another.
    @ObservationIgnored private(set) var passes = 0

    @ObservationIgnored private let provider: any CalendarProvider
    /// The screens' clock (`CompanionClock` unless a test hands in its own).
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private var rawEvents: [ExternalEvent] = []
    @ObservationIgnored private var eventsByDay: [DayKey: [CalendarEvent]] = [:]
    @ObservationIgnored private var fetchedCalendarIds: Set<String> = []
    @ObservationIgnored private var baseWindow: DateInterval?
    @ObservationIgnored private var focusWindow: DateInterval?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var dayObserver: (any NSObjectProtocol)?
    /// The pass waiting out its short delay, so a burst of changes is passed on once.
    @ObservationIgnored private var passTask: Task<Void, Never>?
    @ObservationIgnored private var hourly: Task<Void, Never>?
    @ObservationIgnored private var appObservers: [any NSObjectProtocol] = []
    /// The calendar this device shows its own events in: where its all-day events fall.
    @ObservationIgnored private let deviceCalendar: Calendar
    /// The store a background refresh passes on from (`CalendarPassOnRefresh`).
    @ObservationIgnored nonisolated(unsafe) static weak var shared: CalendarStore?

    /// Days loaded around today, before and after.
    static let pastDays = 42
    static let futureDays = 62

    convenience init(database: AppDatabase) {
        self.init(database: database, provider: Self.defaultProvider())
    }

    init(
        database: AppDatabase, provider: any CalendarProvider, now: @escaping () -> Date = { CompanionClock.now() },
        deviceCalendar: Calendar = .autoupdatingCurrent, passesOn: Bool = true
    ) {
        self.database = database
        self.provider = provider
        self.now = now
        self.deviceCalendar = deviceCalendar
        self.storedAccess = provider.access
        if let first = try? database.calendarSnapshot() { snapshot = first }
        provider.onChange = { [weak self] in
            self?.reload()
            self?.passOnSoon(.change)
        }
        reload()
        observe()
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
                self?.passOnSoon(.day)
            }
        }
        guard passesOn else { return }
        Self.shared = self
        passOnSoon(.open)
        // Coming to the front catches up; going to the back asks iOS for the next refresh.
        appObservers = [
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.passOnSoon(.open, after: .milliseconds(500)) }
            },
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                CalendarPassOnRefresh.schedule()
            },
        ]
        // The wall is always on: it passes on every hour, which also rolls the window.
        hourly = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                self?.passOnSoon(.day, after: .zero)
            }
        }
    }

    private static func defaultProvider() -> any CalendarProvider {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleHousehold") {
            return SampleCalendarProvider()
        }
        #endif
        return EventKitProvider()
    }

    /// The household's calendar for all day math.
    var calendar: Calendar { snapshot.household?.calendar ?? .current }
    /// Whether there are any calendars to read: this device's, or another device's passed on.
    /// Without them nobody has anything planned, which says nothing about being free.
    var hasCalendars: Bool {
        access == .granted || shared.feeds.contains { $0.deviceId != shared.thisDeviceId }
    }
    var people: [Person] { snapshot.people }
    var today: DayKey { DayKey(now(), calendar: calendar) }

    /// Calendars to list in settings, each with its mapping row (once synced).
    var mappings: [(calendar: ExternalCalendar, source: CalendarSource)] {
        let byId = Dictionary(snapshot.sources.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
        return calendars.compactMap { calendar in byId[calendar.id].map { (calendar, $0) } }
    }

    // MARK: Loading

    private func observe() {
        observation = Task { [weak self, database] in
            do {
                for try await snapshot in database.calendarUpdates() {
                    self?.apply(snapshot)
                }
            } catch {
                self?.lastError = error.userMessage
            }
        }
    }

    private func apply(_ newSnapshot: CalendarSnapshot) {
        guard newSnapshot != snapshot else { return }
        let householdChanged = newSnapshot.household?.id != snapshot.household?.id
        let choicesFirstSeen = newSnapshot.choicesSeen && !snapshot.choicesSeen
        let choicesChanged = newSnapshot.sources.map { [$0.sharing.rawValue, $0.ownerId?.description ?? ""] }
            != snapshot.sources.map { [$0.sharing.rawValue, $0.ownerId?.description ?? ""] }
        snapshot = newSnapshot
        if householdChanged || choicesFirstSeen { passOnSoon(.open) } else if choicesChanged { passOnSoon(.choice, after: .milliseconds(300)) }
        if householdChanged || needsSync {
            syncSources()
        }
        if shownCalendarIds != fetchedCalendarIds {
            fetchEvents()
        } else {
            resolve()
        }
    }

    /// Re-reads everything from the provider. Called on launch, on calendar
    /// changes, after access is granted, and at midnight.
    func reload() {
        access = provider.access
        calendars = provider.calendars()
        syncSources()
        if let fresh = try? database.calendarSnapshot() { snapshot = fresh }
        let today = today.startDate(in: calendar)
        if let start = calendar.date(byAdding: .day, value: -Self.pastDays, to: today),
           let end = calendar.date(byAdding: .day, value: Self.futureDays, to: today) {
            baseWindow = DateInterval(start: start, end: end)
        }
        fetchEvents()
    }

    /// Makes sure events in `interval` are loaded (the Calendar screen calls
    /// this when it moves to another week or month).
    func show(_ interval: DateInterval) {
        if let base = baseWindow, base.start <= interval.start, interval.end <= base.end { return }
        if let focus = focusWindow, focus.start <= interval.start, interval.end <= focus.end { return }
        focusWindow = interval
        fetchEvents()
    }

    func requestAccess() async {
        access = await provider.requestAccess()
        reload()
    }

    private var needsSync: Bool {
        let known = Set(snapshot.sources.map(\.externalId))
        return calendars.contains { !known.contains($0.id) }
    }

    private func syncSources() {
        guard let householdId = snapshot.household?.id, !calendars.isEmpty else { return }
        do {
            try database.syncCalendarSources(householdId: householdId, calendars: calendars, now: now())
        } catch {
            lastError = error.userMessage
        }
    }

    private var shownCalendarIds: Set<String> {
        let available = Set(calendars.map(\.id))
        return Set(snapshot.sources.filter { $0.isShown && available.contains($0.externalId) }.map(\.externalId))
    }

    private func fetchEvents() {
        let ids = shownCalendarIds
        fetchedCalendarIds = ids
        var fetched: [String: ExternalEvent] = [:]
        for window in [baseWindow, focusWindow].compactMap({ $0 }) {
            for event in provider.events(in: window, calendarIds: ids) { fetched[event.id] = event }
        }
        rawEvents = Array(fetched.values)
        resolve()
    }

    /// Applies the mapping to the raw events, adds what the other devices passed on, each
    /// event once and quiet calendars as one block a day, and indexes them by day.
    private func resolve() {
        let sources = Dictionary(snapshot.sources.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
        let kinds = Dictionary(calendars.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let own = rawEvents
            .compactMap { event in sources[event.calendarId].flatMap { CalendarEvent.resolve(event, source: $0, kind: kinds[event.calendarId] ?? .regular) } }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        let others = SharedCalendarView.events(snapshot.shared, people: snapshot.people)
        var merged = SharedCalendarView.merge(own: own, others: others)
        // Who each event is for, where the household has said (docs/design/calendar-add-edit.md).
        if let householdId = snapshot.household?.id {
            merged = EventForLogic.apply(snapshot.shared.eventFors, to: merged, householdId: householdId)
        }
        let resolved = SharedCalendarView.quietBlocks(merged, people: snapshot.people, calendar: calendar)
        let calendar = calendar
        var byDay: [DayKey: [CalendarEvent]] = [:]
        for event in resolved {
            let range = event.dayRange(in: calendar)
            var day = range.first
            var guardCount = 0
            while day <= range.last && guardCount < 400 {
                byDay[day, default: []].append(event)
                day = day.adding(days: 1, calendar: calendar)
                guardCount += 1
            }
        }
        eventsByDay = byDay
        events = resolved
    }

    // MARK: Queries

    /// Every shown event touching `day`, sorted by start.
    func events(on day: DayKey) -> [CalendarEvent] {
        _ = events  // register observation of changes
        return eventsByDay[day] ?? []
    }

    /// Timed events for the Today agenda.
    func timelineItems(for day: DayKey) -> [TimelineItem] {
        let calendar = calendar
        let dayStart = day.startDate(in: calendar)
        return events(on: day).filter { !$0.isAllDayLike }.map { event in
            var subtitle = event.isQuiet ? QuietWords.detail(event, calendar: calendar) : EventText.timeRange(event, calendar: calendar)
            if let location = event.location { subtitle += " · \(location)" }
            return TimelineItem(
                id: "calendar-\(event.id)",
                kind: .event,
                time: max(event.start, dayStart),
                timeLabel: nil,
                title: event.title,
                subtitle: subtitle,
                owner: event.owner,
                leading: AnyView(EventMark(event: event, color: color(for: event.owner))),
                trailing: AnyView(OwnerFaces(owners: event.owners, people: people, size: 30)),
                target: .event(event.id)
            )
        }
    }

    /// All-day / multi-day chips for the Today agenda.
    func allDayItems(for day: DayKey) -> [AllDayItem] {
        events(on: day).filter(\.isAllDayLike).map { event in
            var title = [event.emoji, event.title].compactMap { $0 }.joined(separator: " ")
            if let span = EventText.daySpan(event, calendar: calendar) { title += " · \(span)" }
            return AllDayItem(id: "calendar-\(event.id)", title: title, owner: event.owner)
        }
    }

    /// Special days coming up in the next month, for the Today card.
    func countdowns(limit: Int = 3) -> [Countdown] {
        CountdownPicker.pick(from: events, today: today, calendar: calendar, limit: limit)
    }

    /// Whether another device has passed its calendars on, so there is a household calendar
    /// to show even on a device with none of its own.
    var hasOthersCalendars: Bool {
        let mine = shared.thisDeviceId.map { CalendarFeed.id(deviceId: $0) }
        return shared.calendars.contains { $0.feedId != mine }
    }

    /// Whether this device shows any of its own calendars.
    var showsOwnCalendars: Bool {
        access == .granted && mappings.contains { $0.source.isShown }
    }

    /// Other devices whose calendars are over a day old: "Sam's calendar, updated Tuesday".
    var staleSources: [StaleCalendarSource] {
        CalendarFreshness.stale(shared, people: people, now: now(), calendar: calendar)
    }

    /// The event with `id`, a quiet block's own events included, for its sheet.
    func event(id: String) -> CalendarEvent? {
        events.first { $0.id == id } ?? events.lazy.flatMap(\.quietEvents).first { $0.id == id }
    }

    // MARK: Adding and editing (docs/design/calendar-add-edit.md)

    /// The household's home calendar, as this device finds it among its own.
    var home: HomeCalendarLogic.Resolution {
        HomeCalendarLogic.resolve(home: snapshot.home, calendars: calendars, sources: snapshot.sources)
    }

    /// This device's calendars it may write to, to choose the home calendar from.
    var writableCalendars: [ExternalCalendar] { calendars.filter(\.allowsWrites) }

    func chooseHome(_ calendar: ExternalCalendar) {
        guard let householdId = snapshot.household?.id else { return }
        perform { try database.chooseHomeCalendar(calendar, householdId: householdId, now: now()) }
    }

    /// Makes a new calendar on this device and makes it the household's home calendar.
    func makeHomeCalendar(title: String) throws {
        let made = try provider.makeCalendar(title: title)
        reload()
        chooseHome(calendars.first { $0.id == made.id } ?? made)
    }

    func markHome(_ calendar: ExternalCalendar) {
        guard let householdId = snapshot.household?.id else { return }
        perform { try database.markHomeCalendar(externalId: calendar.id, householdId: householdId) }
    }

    /// Whether this device can change an event: one of its own, in a calendar it may write.
    func canChange(_ event: CalendarEvent) -> Bool {
        guard event.from == nil, !event.isQuiet || event.quietEvents.isEmpty else { return false }
        return calendars.first { $0.id == event.calendarId }?.allowsWrites ?? false
    }

    /// The event as the sheet edits it.
    func draft(for event: CalendarEvent) -> EventDraft? {
        guard canChange(event), let raw = rawEvents.first(where: { $0.id == event.id }) else { return nil }
        return EventDraft(
            occurrenceId: raw.id, calendarId: raw.calendarId, title: raw.title, start: raw.start, end: raw.end,
            isAllDay: raw.isAllDay, location: raw.location ?? "", notes: raw.notes ?? "", repeats: raw.repeats
        )
    }

    /// Who an event is for, as its "For" or its calendar's owner.
    func people(for event: CalendarEvent) -> [Person.ID] {
        event.owners.compactMap { if case let .person(id) = $0 { return id } else { return nil } }
    }

    /// Saves a new event or a change, and who it is for; then passes it on soon.
    @discardableResult
    func save(_ draft: EventDraft, span: EventSpan = .thisEvent, for people: [Person.ID]) throws -> String {
        let saved = try provider.save(draft, span: span)
        if let householdId = snapshot.household?.id, let key = CalendarPassOn.matchKey(saved.externalItemId) {
            let calendarOwner = snapshot.sources.first { $0.externalId == draft.calendarId }?.ownerId
            // "For" is the household's fact only where it differs from the calendar's owner.
            let forPeople: [Person.ID]? = people == (calendarOwner.map { [$0] } ?? []) ? nil : people
            try database.setEventFor(
                matchKey: key, title: draft.title, start: draft.start, itemId: EventForLogic.itemId(ofOccurrence: saved.occurrenceId),
                people: forPeople, householdId: householdId, now: now()
            )
        }
        reload()
        passOnSoon(.change)
        return saved.occurrenceId
    }

    /// Deletes an event, or it and those after it; returns it as it was, for Undo.
    func delete(_ event: CalendarEvent, span: EventSpan) throws -> (draft: EventDraft, people: [Person.ID])? {
        guard var draft = draft(for: event) else { return nil }
        let people = people(for: event)
        try provider.delete(occurrenceId: event.id, span: span)
        reload()
        passOnSoon(.change)
        draft.occurrenceId = nil
        if span == .thisEvent { draft.repeats = nil }
        return (draft, people)
    }

    // MARK: Passing on

    /// Passes on after a short wait, so a burst of changes is passed on once.
    func passOnSoon(_ trigger: CalendarPassTrigger, after delay: Duration = .seconds(2)) {
        passTask?.cancel()
        passTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            self?.passOn(trigger)
        }
    }

    /// Passes this device's calendars on to the household (docs/design/calendar-shared.md,
    /// "Passing on"): nothing before its choices have been seen here; without calendar
    /// access, what it passed on before is removed.
    @discardableResult
    func passOn(_ trigger: CalendarPassTrigger) -> CalendarPassResult? {
        passes += 1
        guard let household = snapshot.household else { return nil }
        access = provider.access
        guard access == .granted else {
            if access == .denied { perform { try database.withdrawCalendars(householdId: household.id) } }
            return nil
        }
        guard snapshot.choicesSeen else { return nil }
        let calendar = calendar
        let window = CalendarPassOn.window(today: DayKey(now(), calendar: calendar), calendar: calendar)
        let available = provider.calendars()
        let passing = Set(snapshot.sources.filter(\.sharing.passesOn).map(\.externalId)).intersection(available.map(\.id))
        let events = provider.events(in: window, calendarIds: passing)
        let plan = CalendarPassOn.plan(
            sources: snapshot.sources, calendars: available, events: events,
            deviceId: database.thisDeviceId(in: household.id), deviceCalendar: deviceCalendar, householdCalendar: calendar
        )
        do {
            // Each of this device's events by its local id, with the id it shares now.
            var currentKeys: [String: String] = [:]
            for event in events {
                if let key = CalendarPassOn.matchKey(event.externalItemId) { currentKeys[EventForLogic.itemId(ofOccurrence: event.id)] = key }
            }
            let result = try database.passOnCalendars(plan, householdId: household.id, trigger: trigger, window: window, now: now(), currentKeys: currentKeys)
            lastError = nil
            if result != nil { lastChecked = now() }
            return result
        } catch {
            lastError = error.userMessage
            return nil
        }
    }

    /// Remembers that the choices were shown here, which lets this device pass on.
    func choicesSeen() {
        guard !snapshot.choicesSeen else { return }
        perform { try database.markCalendarChoicesSeen() }
    }

    func color(for owner: Owner) -> Color {
        switch owner {
        case .everyone: Theme.everyone
        case let .person(id): people.first { $0.id == id }?.color.color ?? Theme.everyone
        }
    }

    // MARK: Mapping edits

    func setOwner(_ owner: Owner, for source: CalendarSource) {
        let id = source.id
        perform { try database.setCalendarSourceOwner(id: id, owner: owner) }
    }

    func setSharing(_ sharing: CalendarChoice, for source: CalendarSource) {
        let id = source.id
        perform { try database.setCalendarSourceSharing(id: id, sharing: sharing) }
    }

    func setShown(_ isShown: Bool, for source: CalendarSource) {
        let id = source.id
        perform { try database.setCalendarSourceShown(id: id, isShown: isShown) }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            lastError = nil
        } catch {
            lastError = error.userMessage
        }
    }
}
