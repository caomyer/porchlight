import CryptoKit
import Foundation
import GRDB

// Passing a device's calendars on to the household (docs/design/calendar-shared.md,
// "Passing on"): what is wanted, built where each choice is enforced, and the difference
// from what was passed on before, so only what changed is written and sent.

enum CalendarPassOn {
    /// Days passed on before today, and after it.
    static let daysBack = 14
    static let daysAhead = 90
    /// Notes are cut to this many characters: enough to read, little to send.
    static let notesLimit = 1_000

    /// From 14 days back to 90 days ahead of `today`, in the household's calendar.
    static func window(today: DayKey, calendar: Calendar) -> DateInterval {
        let start = today.adding(days: -daysBack, calendar: calendar).startDate(in: calendar)
        let end = today.adding(days: daysAhead + 1, calendar: calendar).startDate(in: calendar)
        return DateInterval(start: start, end: end)
    }

    /// The same for the same event on every device, without the raw id (which can name a
    /// domain) leaving any of them.
    static func matchKey(_ externalItemId: String?) -> String? {
        guard let id = externalItemId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        return SHA256.hash(data: Data(id.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Building, where each choice is enforced

    /// The calendar as passed on, or nil for Just me. Busy only passes on no name; the
    /// account, which can hold an address, is never passed on, only its kind.
    static func calendarRecord(_ source: CalendarSource, calendar: ExternalCalendar, deviceId: Device.ID) -> SharedCalendar? {
        guard source.sharing.passesOn else { return nil }
        return SharedCalendar(
            id: SharedCalendar.id(deviceId: deviceId, calendarId: calendar.id),
            feedId: CalendarFeed.id(deviceId: deviceId),
            title: source.sharing == .busy ? "" : calendar.title,
            accountKind: calendar.accountKind,
            colorHex: calendar.colorHex,
            ownerId: source.ownerId,
            choice: source.sharing
        )
    }

    /// One occurrence as passed on, or nil for Just me. Busy only passes on the times and
    /// nothing else: no title, place or notes reach the record.
    ///
    /// An all-day event's days are the ones this device shows it on, given as the
    /// household calendar's midnights, so every device puts it on the same days.
    static func eventRecord(
        _ event: ExternalEvent, choice: CalendarChoice, calendarId: SharedCalendar.ID,
        deviceCalendar: Calendar, householdCalendar: Calendar
    ) -> SharedEvent? {
        guard choice.passesOn else { return nil }
        var start = event.start, end = max(event.end, event.start)
        if event.isAllDay {
            let first = DayKey(start, calendar: deviceCalendar)
            let last = DayKey(end > start ? end.addingTimeInterval(-1) : start, calendar: deviceCalendar)
            start = first.startDate(in: householdCalendar)
            end = last.adding(days: 1, calendar: householdCalendar).startDate(in: householdCalendar)
        }
        let words = choice == .busy ? nil : Words(event)
        return SharedEvent(
            id: SharedEvent.id(sharedCalendarId: calendarId, occurrence: event.id),
            sharedCalendarId: calendarId,
            matchKey: matchKey(event.externalItemId),
            title: words?.title,
            location: words?.location,
            notes: words?.notes,
            start: milliseconds(start),
            end: milliseconds(end),
            isAllDay: event.isAllDay
        )
    }

    /// An event's words, read only for the choices that pass them on.
    private struct Words {
        var title: String
        var location: String?
        var notes: String?

        init(_ event: ExternalEvent) {
            title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            location = event.location
            notes = event.notes.map { String($0.prefix(CalendarPassOn.notesLimit)) }
        }
    }

    /// What the database keeps, so a pass compares like with like.
    static func milliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    // MARK: What is wanted

    struct Plan: Equatable {
        var calendars: [SharedCalendar]
        var events: [SharedEvent]
    }

    /// Everything this device passes on: each calendar the provider has whose choice isn't
    /// Just me, and its occurrences in `window`.
    static func plan(
        sources: [CalendarSource], calendars: [ExternalCalendar], events: [ExternalEvent],
        deviceId: Device.ID, deviceCalendar: Calendar, householdCalendar: Calendar
    ) -> Plan {
        let sourceById = Dictionary(sources.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
        var shared: [String: SharedCalendar] = [:]
        var choices: [String: CalendarChoice] = [:]
        for calendar in calendars {
            guard let source = sourceById[calendar.id], let record = calendarRecord(source, calendar: calendar, deviceId: deviceId) else { continue }
            shared[calendar.id] = record
            choices[calendar.id] = source.sharing
        }
        var byId: [SharedEvent.ID: SharedEvent] = [:]
        for event in events {
            guard let record = shared[event.calendarId], let choice = choices[event.calendarId],
                  let row = eventRecord(event, choice: choice, calendarId: record.id, deviceCalendar: deviceCalendar, householdCalendar: householdCalendar)
            else { continue }
            byId[row.id] = row
        }
        return Plan(
            calendars: shared.values.sorted { $0.id.description < $1.id.description },
            events: byId.values.sorted { ($0.start, $0.id.description) < ($1.start, $1.id.description) }
        )
    }

    // MARK: What changed

    struct Diff: Equatable {
        var insertCalendars: [SharedCalendar] = []
        var updateCalendars: [SharedCalendar] = []
        var deleteCalendars: [SharedCalendar.ID] = []
        var insertEvents: [SharedEvent] = []
        var updateEvents: [SharedEvent] = []
        /// Events gone from calendars that stay; a removed calendar's go with it.
        var deleteEvents: [SharedEvent.ID] = []

        var isEmpty: Bool {
            insertCalendars.isEmpty && updateCalendars.isEmpty && deleteCalendars.isEmpty
                && insertEvents.isEmpty && updateEvents.isEmpty && deleteEvents.isEmpty
        }
    }

    /// The writes that turn what was passed on into what is wanted, touching nothing else.
    static func diff(wanted: Plan, calendars existingCalendars: [SharedCalendar], events existingEvents: [SharedEvent]) -> Diff {
        var diff = Diff()
        let had = Dictionary(existingCalendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wantedCalendarIds = Set(wanted.calendars.map(\.id))
        for calendar in wanted.calendars {
            if let old = had[calendar.id] {
                if old != calendar { diff.updateCalendars.append(calendar) }
            } else {
                diff.insertCalendars.append(calendar)
            }
        }
        diff.deleteCalendars = existingCalendars.map(\.id).filter { !wantedCalendarIds.contains($0) }
        let gone = Set(diff.deleteCalendars)
        let hadEvents = Dictionary(existingEvents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wantedEventIds = Set(wanted.events.map(\.id))
        for event in wanted.events {
            if let old = hadEvents[event.id] {
                if !old.sameContent(as: event) { diff.updateEvents.append(event) }
            } else {
                diff.insertEvents.append(event)
            }
        }
        diff.deleteEvents = existingEvents.filter { !wantedEventIds.contains($0.id) && !gone.contains($0.sharedCalendarId) }.map(\.id)
        return diff
    }
}

extension SharedEvent {
    /// The same occurrence, to the millisecond the database keeps.
    func sameContent(as other: SharedEvent) -> Bool {
        func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
        return id == other.id && sharedCalendarId == other.sharedCalendarId && matchKey == other.matchKey
            && title == other.title && location == other.location && notes == other.notes
            && ms(start) == ms(other.start) && ms(end) == ms(other.end) && isAllDay == other.isAllDay
    }
}

// MARK: - Writing

/// What one pass wrote, for the feed and for tests.
struct CalendarPassResult: Equatable, Sendable {
    var calendars: Int
    var events: Int
    var inserted: Int
    var updated: Int
    var deleted: Int
}

extension AppDatabase {
    /// Writes this device's pass: the difference from what it passed on before, and its
    /// feed row (when, why, the window and how many events). It only ever writes under
    /// this device's own row.
    @discardableResult
    func passOnCalendars(
        _ plan: CalendarPassOn.Plan, householdId: Household.ID, trigger: CalendarPassTrigger, window: DateInterval, now: Date
    ) throws -> CalendarPassResult? {
        try writer.write { db in
            let deviceId = thisDeviceId(in: householdId)
            guard try Device.exists(db, id: deviceId) else { return nil }
            let feedId = CalendarFeed.id(deviceId: deviceId)
            let feed = CalendarFeed(
                id: feedId, deviceId: deviceId, passedOnAt: now, passedOnBy: trigger,
                windowStart: window.start, windowEnd: window.end, eventCount: plan.events.count
            )
            try feed.save(db)
            let calendars = try SharedCalendar.filter(Column("feedId") == feedId).fetchAll(db)
            let events = try SharedEvent.filter(calendars.map(\.id).contains(Column("sharedCalendarId"))).fetchAll(db)
            let diff = CalendarPassOn.diff(wanted: plan, calendars: calendars, events: events)
            for id in diff.deleteCalendars { _ = try SharedCalendar.deleteOne(db, id: id) }
            for id in diff.deleteEvents { _ = try SharedEvent.deleteOne(db, id: id) }
            for calendar in diff.insertCalendars { try calendar.insert(db) }
            for calendar in diff.updateCalendars { try calendar.update(db) }
            for event in diff.insertEvents { try event.insert(db) }
            for event in diff.updateEvents { try event.update(db) }
            let removedWithCalendars = events.filter { Set(diff.deleteCalendars).contains($0.sharedCalendarId) }.count
            return CalendarPassResult(
                calendars: plan.calendars.count, events: plan.events.count,
                inserted: diff.insertCalendars.count + diff.insertEvents.count,
                updated: diff.updateCalendars.count + diff.updateEvents.count,
                deleted: diff.deleteCalendars.count + diff.deleteEvents.count + removedWithCalendars
            )
        }
    }

    /// Removes everything this device passed on: its feed, calendars and events, for
    /// everyone. Before leaving a household, and when calendar access is taken away.
    func withdrawCalendars(householdId: Household.ID) throws {
        try writer.write { db in
            _ = try CalendarFeed.deleteOne(db, id: CalendarFeed.id(deviceId: thisDeviceId(in: householdId)))
        }
    }
}
