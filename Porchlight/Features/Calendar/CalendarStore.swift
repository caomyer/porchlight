import Foundation
import Observation
import SwiftUI

/// Live calendar state for the wall: the calendars on this iPad, the
/// household's mapping for each, and the resolved events around today (plus
/// whatever range the Calendar screen is looking at).
@MainActor
@Observable
final class CalendarStore {
    let database: AppDatabase
    private(set) var access: CalendarAccess
    /// Calendars the provider currently knows, in display order.
    private(set) var calendars: [ExternalCalendar] = []
    private(set) var snapshot: CalendarSnapshot = .empty
    /// Resolved events in the loaded window, sorted by start.
    private(set) var events: [CalendarEvent] = []
    var lastError: String?

    @ObservationIgnored private let provider: any CalendarProvider
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var rawEvents: [ExternalEvent] = []
    @ObservationIgnored private var eventsByDay: [DayKey: [CalendarEvent]] = [:]
    @ObservationIgnored private var fetchedCalendarIds: Set<String> = []
    @ObservationIgnored private var baseWindow: DateInterval?
    @ObservationIgnored private var focusWindow: DateInterval?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var dayObserver: (any NSObjectProtocol)?

    /// Days loaded around today, before and after.
    static let pastDays = 42
    static let futureDays = 62

    convenience init(database: AppDatabase) {
        self.init(database: database, provider: Self.defaultProvider())
    }

    init(database: AppDatabase, provider: any CalendarProvider, now: @escaping () -> Date = { .now }) {
        self.database = database
        self.provider = provider
        self.now = now
        self.access = provider.access
        if let first = try? database.calendarSnapshot() { snapshot = first }
        provider.onChange = { [weak self] in self?.reload() }
        reload()
        observe()
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
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
        snapshot = newSnapshot
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

    /// Applies the mapping to the raw events and indexes them by day.
    private func resolve() {
        let sources = Dictionary(snapshot.sources.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
        let kinds = Dictionary(calendars.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let resolved = rawEvents
            .compactMap { event in sources[event.calendarId].flatMap { CalendarEvent.resolve(event, source: $0, kind: kinds[event.calendarId] ?? .regular) } }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
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
            var subtitle = EventText.timeRange(event, calendar: calendar)
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
                trailing: AnyView(OwnerAvatar(owner: event.owner, people: people))
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

    func color(for owner: Owner) -> Color {
        switch owner {
        case .everyone: Theme.everyone
        case let .person(id): people.first { $0.id == id }?.color.color ?? Theme.everyone
        }
    }

    // MARK: Mapping edits

    func setOwner(_ owner: Owner, for source: CalendarSource) {
        guard let id = source.id else { return }
        perform { try database.setCalendarSourceOwner(id: id, owner: owner) }
    }

    func setVisibility(_ visibility: CalendarVisibility, for source: CalendarSource) {
        guard let id = source.id else { return }
        perform { try database.setCalendarSourceVisibility(id: id, visibility: visibility) }
    }

    func setShown(_ isShown: Bool, for source: CalendarSource) {
        guard let id = source.id else { return }
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
