import Foundation
import Testing
@testable import Porchlight

/// Showing what the other devices passed on (docs/design/calendar-shared.md, "Showing"):
/// each event once with every owner's face, quiet calendars as one block a day, and how
/// fresh each device's calendars are. The clock and the calendar are handed in.
@Suite("Showing the shared calendar: once each, quiet blocks and freshness")
struct SharedCalendarViewTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    static let alex = Person(id: .derived("alex"), householdId: .derived("h"), name: "Alex", color: .blue, sortOrder: 0, createdAt: .distantPast)
    static let sam = Person(id: .derived("sam"), householdId: .derived("h"), name: "Sam", color: .coral, sortOrder: 1, createdAt: .distantPast)
    static let people = [alex, sam]

    static func at(_ text: String) -> Date { CalendarPassOnTests.date(text, calendar) }

    /// The formatter's narrow space before AM and PM, as a plain one.
    static func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }

    static func event(
        _ id: String, _ title: String, _ start: String, _ end: String, owner: Person, key: String? = nil,
        busy: Bool = false, quiet: Bool = false
    ) -> CalendarEvent {
        var event = CalendarEvent.resolve(
            ExternalEvent(id: id, calendarId: "c-\(owner.name)", title: title, start: at(start), end: at(end), isAllDay: false),
            owner: .person(owner.id), isBusy: busy, calendarTitle: "Cal"
        )
        event.matchKey = key
        event.isQuiet = quiet
        return event
    }

    // MARK: Once each

    @Test("The same invite from two devices is one event with both faces; this device's own copy is the one kept")
    func sameInvite() {
        let mine = Self.event("mine", "Dinner with the Lees", "2026-11-24 19:00", "2026-11-24 21:00", owner: Self.sam, key: "k1")
        let theirs = Self.event("theirs", "Dinner with the Lees", "2026-11-24 19:00", "2026-11-24 21:00", owner: Self.alex, key: "k1")
        let merged = SharedCalendarView.merge(own: [mine], others: [theirs])
        #expect(merged.map(\.id) == ["mine"])
        #expect(merged[0].owners == [.person(Self.sam.id), .person(Self.alex.id)])
    }

    @Test("Without a key on either side, title, start and end match; a different time or title doesn't")
    func byWords() {
        let mine = Self.event("mine", "Dentist", "2026-11-26 16:00", "2026-11-26 17:00", owner: Self.sam)
        let same = Self.event("a", "dentist", "2026-11-26 16:00", "2026-11-26 17:00", owner: Self.alex, key: "k9")
        let later = Self.event("b", "Dentist", "2026-11-26 16:30", "2026-11-26 17:00", owner: Self.alex)
        let other = Self.event("c", "Piano", "2026-11-26 16:00", "2026-11-26 17:00", owner: Self.alex)
        let merged = SharedCalendarView.merge(own: [mine], others: [same, later, other])
        #expect(merged.map(\.id) == ["mine", "b", "c"])
        #expect(merged[0].alsoFor == [.person(Self.alex.id)])
    }

    @Test("Two keyed events with different keys never match by their words, and Busy only matches by key alone")
    func keysWin() {
        let one = Self.event("a", "Standup", "2026-11-24 09:00", "2026-11-24 09:15", owner: Self.sam, key: "k1")
        let two = Self.event("b", "Standup", "2026-11-24 09:00", "2026-11-24 09:15", owner: Self.alex, key: "k2")
        #expect(SharedCalendarView.merge(own: [one], others: [two]).count == 2)

        let busyMine = Self.event("c", "", "2026-11-24 13:00", "2026-11-24 14:00", owner: Self.sam, busy: true)
        let busyTheirs = Self.event("d", "", "2026-11-24 13:00", "2026-11-24 14:00", owner: Self.alex, busy: true)
        #expect(SharedCalendarView.merge(own: [busyMine], others: [busyTheirs]).count == 2, "two people busy at one time are two")
        let keyed = Self.event("e", "", "2026-11-24 13:00", "2026-11-24 14:00", owner: Self.alex, key: "kb", busy: true)
        var keyedMine = busyMine
        keyedMine.matchKey = "kb"
        #expect(SharedCalendarView.merge(own: [keyedMine], others: [keyed]).count == 1)
    }

    @Test("An event seen in full on one device and quietly on another is shown in full")
    func fullWins() {
        let mine = Self.event("mine", "Offsite", "2026-11-24 10:00", "2026-11-24 12:00", owner: Self.sam, key: "k")
        let quiet = Self.event("q", "Offsite", "2026-11-24 10:00", "2026-11-24 12:00", owner: Self.alex, key: "k", quiet: true)
        let merged = SharedCalendarView.merge(own: [mine], others: [quiet])
        #expect(merged.count == 1 && !merged[0].isQuiet)
    }

    // MARK: Quiet

    @Test("Keep it quiet is one block per person per day, first start to last end, standing for its meetings")
    func quietBlocks() throws {
        let events = [
            Self.event("1", "Standup", "2026-11-24 09:00", "2026-11-24 09:15", owner: Self.alex, quiet: true),
            Self.event("2", "Review", "2026-11-24 14:00", "2026-11-24 17:30", owner: Self.alex, quiet: true),
            Self.event("3", "Planning", "2026-11-24 11:00", "2026-11-24 12:00", owner: Self.alex, quiet: true),
            Self.event("4", "Standup", "2026-11-25 09:00", "2026-11-25 09:15", owner: Self.alex, quiet: true),
            Self.event("5", "Soccer practice", "2026-11-24 15:30", "2026-11-24 17:00", owner: Self.sam),
        ]
        let shown = SharedCalendarView.quietBlocks(events, people: Self.people, calendar: Self.calendar)
        #expect(shown.count == 3)
        let tuesday = try #require(shown.first { $0.isQuiet && DayKey($0.start, calendar: Self.calendar).rawValue == "2026-11-24" })
        #expect(tuesday.title == "Alex at work")
        #expect(tuesday.start == Self.at("2026-11-24 09:00") && tuesday.end == Self.at("2026-11-24 17:30"))
        #expect(tuesday.quietEvents.map(\.title) == ["Standup", "Planning", "Review"])
        #expect(Self.plain(QuietWords.detail(tuesday, calendar: Self.calendar)) == "Until 5:30 PM · 3 meetings")
        #expect(Self.plain(QuietWords.gridTitle(tuesday, calendar: Self.calendar)) == "Alex at work until 5:30 PM")
        #expect(shown.contains { $0.title == "Soccer practice" && !$0.isQuiet })
    }

    // MARK: How fresh

    static func snapshot(passedOn: Date) -> SharedCalendarSnapshot {
        let samsPhone = Device(id: .derived("sams-phone"), householdId: .derived("h"), name: "Sam's iPhone", role: .personal, personId: sam.id, createdAt: .distantPast, seenAt: .distantPast)
        let wall = Device(id: .derived("wall"), householdId: .derived("h"), name: "Hallway iPad", role: .sharedScreen, createdAt: .distantPast, seenAt: .distantPast)
        let feeds = [samsPhone, wall].map {
            CalendarFeed(id: CalendarFeed.id(deviceId: $0.id), deviceId: $0.id, passedOnAt: passedOn, passedOnBy: .background, windowStart: passedOn, windowEnd: passedOn, eventCount: 12)
        }
        let calendars = feeds.map {
            SharedCalendar(id: .derived($0.id.description, "c"), feedId: $0.id, title: "Home", accountKind: "iCloud", colorHex: 0, ownerId: nil, choice: .everything)
        }
        return SharedCalendarSnapshot(thisDeviceId: .derived("alexs-phone"), devices: [samsPhone, wall], feeds: feeds, calendars: calendars, events: [])
    }

    @Test("A device's calendars over a day old are named with the day they were updated; fresher ones aren't")
    func freshness() {
        let now = Self.at("2026-11-26 09:00")
        let stale = CalendarFreshness.stale(Self.snapshot(passedOn: Self.at("2026-11-24 18:00")), people: Self.people, now: now, calendar: Self.calendar)
        #expect(stale.map(\.words) == ["Sam's calendar, updated Tuesday", "The Hallway iPad's calendar, updated Tuesday"])
        #expect(CalendarFreshness.stale(Self.snapshot(passedOn: Self.at("2026-11-25 10:00")), people: Self.people, now: now, calendar: Self.calendar).isEmpty)
        #expect(CalendarFreshness.day(Self.at("2026-11-25 22:00"), now: now, calendar: Self.calendar) == "yesterday")
        #expect(CalendarFreshness.day(Self.at("2026-11-12 22:00"), now: now, calendar: Self.calendar) == "Nov 12")
    }

    @Test("Sync details has a line per device: calendars, events, when and why")
    func detailLines() {
        let lines = CalendarFreshness.detailLines(Self.snapshot(passedOn: Self.at("2026-11-26 08:14")), now: Self.at("2026-11-26 09:00"), calendar: Self.calendar)
        #expect(lines.map(\.device) == ["Hallway iPad", "Sam's iPhone"])
        #expect(Self.plain(lines[1].line) == "1 calendar, 12 events, passed on 8:14 AM today, in the background")
    }
}
