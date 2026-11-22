import Foundation
import GRDB
import Testing
@testable import Porchlight

/// Passing a device's calendars on (docs/design/calendar-shared.md): what each of the four
/// choices lets out, the window, the cross-device key, all-day days, and the difference
/// from one pass to the next. The clock and both calendars are handed in.
@Suite("Passing calendars on: the four choices, the window and the difference")
struct CalendarPassOnTests {
    static let household: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static let device = Device.ID.derived("test-device")
    /// Words that must never reach a record for Busy only or Just me.
    static let secrets = ["SECRET-TITLE", "SECRET-PLACE", "SECRET-NOTE", "secret@example.com", "SECRET-CALENDAR", "SECRET-UID"]

    static func date(_ text: String, _ calendar: Calendar = household) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    static let calendar = ExternalCalendar(
        id: "cal-1", title: "SECRET-CALENDAR", account: "Google · secret@example.com", colorHex: 0x3366CC, accountKind: "Google"
    )

    static func event(id: String = "item-1@1", start: String = "2026-11-24 15:30", end: String = "2026-11-24 17:00", allDay: Bool = false) -> ExternalEvent {
        ExternalEvent(
            id: id, calendarId: calendar.id, title: " SECRET-TITLE ", location: "SECRET-PLACE",
            notes: "SECRET-NOTE " + String(repeating: "x", count: 1_500),
            start: date(start), end: date(end), isAllDay: allDay, externalItemId: "SECRET-UID"
        )
    }

    static func source(_ choice: CalendarChoice) -> CalendarSource {
        var source = CalendarSource(
            householdId: .derived("h"), externalId: calendar.id, title: calendar.title, account: calendar.account,
            colorHex: calendar.colorHex, ownerId: .derived("mia"), visibility: .full, isShown: true, createdAt: .distantPast
        )
        choice.apply(to: &source)
        return source
    }

    /// Every string anywhere in a value, however deep.
    static func strings(in value: Any) -> [String] {
        if let string = value as? String { return [string] }
        return Mirror(reflecting: value).children.flatMap { strings(in: $0.value) }
    }

    static func plan(_ choice: CalendarChoice, events: [ExternalEvent] = [event()]) -> CalendarPassOn.Plan {
        CalendarPassOn.plan(
            sources: [source(choice)], calendars: [calendar], events: events,
            deviceId: device, deviceCalendar: household, householdCalendar: household
        )
    }

    // MARK: The four choices

    @Test("Busy only passes on the times and no word of the event, the calendar or the account", arguments: [CalendarChoice.busy])
    func busyOnly(choice: CalendarChoice) throws {
        let plan = Self.plan(choice)
        let event = try #require(plan.events.first)
        #expect(event.title == nil && event.location == nil && event.notes == nil)
        #expect(event.start == Self.date("2026-11-24 15:30") && event.end == Self.date("2026-11-24 17:00"))
        #expect(plan.calendars.first?.title == "")
        for text in Self.strings(in: plan) {
            for secret in Self.secrets { #expect(!text.contains(secret), "\(secret) reached \(text.prefix(40))") }
        }
    }

    @Test("Just me passes on nothing at all")
    func justMe() {
        let plan = Self.plan(.justMe)
        #expect(plan.calendars.isEmpty && plan.events.isEmpty)
        #expect(CalendarPassOn.eventRecord(Self.event(), choice: .justMe, calendarId: .derived("x"), deviceCalendar: Self.household, householdCalendar: Self.household) == nil)
        #expect(CalendarPassOn.calendarRecord(Self.source(.justMe), calendar: Self.calendar, deviceId: Self.device) == nil)
    }

    @Test("Show everything and Keep it quiet pass on the words, notes cut short, and never the account or the raw id", arguments: [CalendarChoice.everything, .quiet])
    func words(choice: CalendarChoice) throws {
        let plan = Self.plan(choice)
        let event = try #require(plan.events.first)
        #expect(event.title == "SECRET-TITLE")
        #expect(event.location == "SECRET-PLACE")
        #expect(event.notes?.count == CalendarPassOn.notesLimit)
        let calendar = try #require(plan.calendars.first)
        #expect(calendar.title == "SECRET-CALENDAR" && calendar.choice == choice && calendar.accountKind == "Google")
        #expect(calendar.ownerId == .derived("mia"))
        for text in Self.strings(in: plan) {
            #expect(!text.contains("secret@example.com"), "the account never leaves")
            #expect(!text.contains("SECRET-UID"), "the raw id never leaves")
        }
    }

    @Test("Today's choices become the four: full is Show everything, busy is Busy only, Just me stays")
    func migration() throws {
        let queue = try DatabaseQueue()
        let migrator = AppDatabase.migrator(files: nil)
        try migrator.migrate(queue, upTo: AppDatabase.recipeMigration)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO household (id, name, timeZoneIdentifier, firstWeekday, createdAt) VALUES ('11111111-1111-1111-1111-111111111111', 'Home', 'UTC', 1, '2026-01-01 00:00:00.000');
                INSERT INTO calendarSource (id, householdId, externalId, title, account, colorHex, visibility, isShown, createdAt, isPersonal) VALUES
                  ('22222222-2222-2222-2222-222222222221', '11111111-1111-1111-1111-111111111111', 'a', 'A', '', 0, 'full', 1, '2026-01-01 00:00:00.000', 0),
                  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'b', 'B', '', 0, 'busy', 1, '2026-01-01 00:00:00.000', 0),
                  ('22222222-2222-2222-2222-222222222223', '11111111-1111-1111-1111-111111111111', 'c', 'C', '', 0, 'busy', 1, '2026-01-01 00:00:00.000', 1),
                  ('22222222-2222-2222-2222-222222222224', '11111111-1111-1111-1111-111111111111', 'd', 'D', '', 0, 'full', 1, '2026-01-01 00:00:00.000', 1);
                """)
        }
        try migrator.migrate(queue)
        let choices = try queue.read { try [String: String](uniqueKeysWithValues: Row.fetchAll($0, sql: "SELECT externalId, sharing FROM calendarSource").map { ($0["externalId"], $0["sharing"]) }) }
        #expect(choices == ["a": "everything", "b": "busy", "c": "justMe", "d": "justMe"])
    }

    // MARK: The window

    @Test("The window is 14 days back to the end of the 90th day ahead, on the household's midnights, swept across a year in two zones")
    func window() {
        for zone in ["America/Los_Angeles", "Europe/Berlin"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            var day = DayKey(rawValue: "2026-01-01")
            for _ in 0..<366 {
                let window = CalendarPassOn.window(today: day, calendar: calendar)
                #expect(DayKey(window.start, calendar: calendar) == day.adding(days: -14, calendar: calendar))
                #expect(calendar.component(.hour, from: window.start) == 0 && calendar.component(.hour, from: window.end) == 0)
                #expect(DayKey(window.end.addingTimeInterval(-1), calendar: calendar) == day.adding(days: 90, calendar: calendar))
                day = day.adding(days: 1, calendar: calendar)
            }
        }
    }

    // MARK: Matching and days

    @Test("The match key is the same for the same event's id, differs for another, and is never the id itself")
    func matchKey() throws {
        let key = try #require(CalendarPassOn.matchKey("abc@google.com"))
        #expect(key == CalendarPassOn.matchKey(" abc@google.com "))
        #expect(key != CalendarPassOn.matchKey("abd@google.com"))
        #expect(!key.contains("google") && key.count == 32)
        #expect(CalendarPassOn.matchKey(nil) == nil && CalendarPassOn.matchKey("  ") == nil)
    }

    @Test("An all-day event keeps the days the device shows it on, as the household's midnights, wherever the device is")
    func allDay() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // Thanksgiving as a device in Berlin shows it: midnight to midnight there.
        let event = ExternalEvent(
            id: "t@1", calendarId: Self.calendar.id, title: "Thanksgiving", start: Self.date("2026-11-26 00:00", berlin),
            end: Self.date("2026-11-27 00:00", berlin), isAllDay: true
        )
        let row = try #require(CalendarPassOn.eventRecord(event, choice: .everything, calendarId: .derived("c"), deviceCalendar: berlin, householdCalendar: Self.household))
        #expect(row.start == Self.date("2026-11-26 00:00") && row.end == Self.date("2026-11-27 00:00"))
        #expect(row.isAllDay)
    }

    // MARK: The difference

    @Test("A second pass with nothing new writes nothing; a changed, added or gone event writes only that")
    func difference() throws {
        let first = Self.plan(.everything, events: [Self.event(id: "a@1"), Self.event(id: "b@1", start: "2026-11-25 09:00", end: "2026-11-25 10:00")])
        #expect(CalendarPassOn.diff(wanted: first, calendars: first.calendars, events: first.events).isEmpty)

        var moved = Self.event(id: "a@1")
        moved.end = Self.date("2026-11-24 18:00")
        let second = Self.plan(.everything, events: [moved, Self.event(id: "c@1", start: "2026-11-26 09:00", end: "2026-11-26 10:00")])
        let diff = CalendarPassOn.diff(wanted: second, calendars: first.calendars, events: first.events)
        #expect(diff.updateEvents.map(\.end) == [Self.date("2026-11-24 18:00")])
        #expect(diff.insertEvents.count == 1 && diff.deleteEvents.count == 1)
        #expect(diff.insertCalendars.isEmpty && diff.updateCalendars.isEmpty && diff.deleteCalendars.isEmpty)
    }

    @Test("Switching a calendar to Just me removes the calendar, its events going with it")
    func toJustMe() {
        let before = Self.plan(.everything)
        let diff = CalendarPassOn.diff(wanted: Self.plan(.justMe), calendars: before.calendars, events: before.events)
        #expect(diff.deleteCalendars == before.calendars.map(\.id))
        #expect(diff.deleteEvents.isEmpty, "they go with their calendar")
    }

    @Test("Switching to Busy only rewrites the events without their words")
    func toBusy() {
        let before = Self.plan(.everything)
        let diff = CalendarPassOn.diff(wanted: Self.plan(.busy), calendars: before.calendars, events: before.events)
        #expect(diff.updateCalendars.map(\.title) == [""])
        #expect(diff.updateEvents.allSatisfy { $0.title == nil && $0.location == nil && $0.notes == nil })
        #expect(diff.updateEvents.count == 1)
    }
}
