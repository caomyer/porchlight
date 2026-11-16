import Foundation
import GRDB
import Testing
@testable import Porchlight

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    calendar.firstWeekday = 1
    return calendar
}()

/// 2026-11-<day> at the given hour, Los Angeles time.
private func date(_ day: Int, _ hour: Double = 0, month: Int = 11) -> Date {
    let midnight = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    return midnight.addingTimeInterval(hour * 3600)
}

private func key(_ day: Int, month: Int = 11) -> DayKey {
    DayKey(date(day, month: month), calendar: calendar)
}

private func event(
    _ id: String,
    _ title: String = "Event",
    start: Date,
    end: Date,
    allDay: Bool = false,
    owner: Owner = .everyone,
    celebration: EventDecoration.Celebration? = nil,
    busy: Bool = false,
    special: Bool = false
) -> CalendarEvent {
    CalendarEvent(
        id: id, calendarId: "c", title: title, emoji: nil, celebration: celebration, location: nil, notes: nil,
        start: start, end: end, isAllDay: allDay, owner: owner, isBusy: busy, calendarTitle: "Cal", isFromSpecialCalendar: special
    )
}

private func source(visibility: CalendarVisibility = .full, shown: Bool = true, ownerId: Person.ID? = nil) -> CalendarSource {
    CalendarSource(
        id: 1, householdId: 1, externalId: "c", title: "Cal", account: "iCloud", colorHex: 0,
        ownerId: ownerId, visibility: visibility, isShown: shown, createdAt: .now
    )
}

// MARK: - Mapping

@Suite("Calendar mapping")
struct CalendarMappingTests {
    private func household(_ db: AppDatabase, people: [String] = ["James", "Mia"]) throws -> (Household.ID, [Person]) {
        let household = try db.createHousehold(name: "Home", people: people.map { PersonDraft(name: $0, color: .blue) })
        return (household.id, try db.snapshot().people)
    }

    @Test("New calendars default to shown, full details and a guessed owner")
    func defaults() throws {
        let db = try AppDatabase.inMemory()
        let (id, people) = try household(db)
        try db.syncCalendarSources(householdId: id, calendars: [
            ExternalCalendar(id: "a", title: "James", account: "Google · james@example.com", colorHex: 0x112233),
            ExternalCalendar(id: "b", title: "Work", account: "mia@example.com", colorHex: 0),
            ExternalCalendar(id: "c", title: "Us", account: "james@example.com", colorHex: 0),
            ExternalCalendar(id: "d", title: "Soccer club", account: "Subscribed link", colorHex: 0, kind: .subscribed),
        ])
        let sources = Dictionary(uniqueKeysWithValues: try db.calendarSnapshot().sources.map { ($0.externalId, $0) })
        let james = people.first { $0.name == "James" }?.id
        let mia = people.first { $0.name == "Mia" }?.id
        #expect(sources.count == 4)
        #expect(sources.values.allSatisfy { $0.isShown && $0.visibility == .full })
        #expect(sources["a"]?.ownerId == james)
        #expect(sources["a"]?.colorHex == 0x112233)
        #expect(sources["b"]?.ownerId == mia)       // from the account
        #expect(sources["c"]?.ownerId == nil)       // "Us" is shared, despite the account
        #expect(sources["d"]?.ownerId == nil)       // subscribed calendars belong to everyone
    }

    @Test("Owner guess", arguments: [
        ("James", "", "James"),
        ("james & mia", "", nil),
        ("Family", "james@example.com", nil),
        ("US Holidays", "", nil),
        ("Gym", "Mia's iPad", "Mia"),
        ("Gym", "someone@example.com", nil),
        ("Jameson", "", nil),
    ] as [(String, String, String?)])
    func ownerGuess(title: String, account: String, expected: String?) {
        let people = [
            Person(id: 1, householdId: 1, name: "James", color: .blue, sortOrder: 0, createdAt: .now),
            Person(id: 2, householdId: 1, name: "Mia", color: .coral, sortOrder: 1, createdAt: .now),
        ]
        let guess = CalendarOwnerGuess.owner(for: ExternalCalendar(id: "x", title: title, account: account, colorHex: 0), people: people)
        #expect(guess == people.first { $0.name == expected }?.id)
    }

    @Test("Syncing again keeps the household's choices and follows renames")
    func resync() throws {
        let db = try AppDatabase.inMemory()
        let (id, people) = try household(db)
        try db.syncCalendarSources(householdId: id, calendars: [ExternalCalendar(id: "a", title: "James", account: "x", colorHex: 1)])
        let source = try #require(try db.calendarSnapshot().sources.first)
        let mia = try #require(people.first { $0.name == "Mia" }?.id)
        try db.setCalendarSourceOwner(id: source.id, owner: .person(mia))
        try db.setCalendarSourceVisibility(id: source.id, visibility: .busy)
        try db.setCalendarSourceShown(id: source.id, isShown: false)

        try db.syncCalendarSources(householdId: id, calendars: [ExternalCalendar(id: "a", title: "Renamed", account: "y", colorHex: 2)])
        let updated = try #require(try db.calendarSnapshot().sources.first)
        #expect(try db.calendarSnapshot().sources.count == 1)
        #expect(updated.title == "Renamed" && updated.account == "y" && updated.colorHex == 2)
        #expect(updated.ownerId == mia && updated.visibility == .busy && !updated.isShown)
    }

    @Test("Owners must live in the same household; removing a person hands calendars to everyone")
    func ownerRules() throws {
        let db = try AppDatabase.inMemory()
        let (id, people) = try household(db)
        try db.syncCalendarSources(householdId: id, calendars: [ExternalCalendar(id: "a", title: "Mia", account: "", colorHex: 0)])
        let source = try #require(try db.calendarSnapshot().sources.first)
        #expect(throws: CalendarSourceError.ownerNotInHousehold) {
            try db.setCalendarSourceOwner(id: source.id, owner: .person(9999))
        }
        #expect(throws: CalendarSourceError.unknownCalendar) {
            try db.setCalendarSourceShown(id: 9999, isShown: false)
        }
        let mia = try #require(people.first { $0.name == "Mia" })
        #expect(source.ownerId == mia.id)
        try db.archivePerson(id: mia.id)
        #expect(try db.calendarSnapshot().sources.first?.owner == .everyone)
    }
}

// MARK: - Resolution and decoration

@Suite("Calendar events")
struct CalendarEventTests {
    private let raw = ExternalEvent(
        id: "e1", calendarId: "c", title: "Dentist", location: "Dr. Patel", notes: "Bring forms",
        start: date(9, 11), end: date(9, 12), isAllDay: false
    )

    @Test("Busy-only calendars reveal nothing but the time")
    func busyRedaction() throws {
        let resolved = try #require(CalendarEvent.resolve(raw, source: source(visibility: .busy, ownerId: 3)))
        #expect(resolved.title == "Busy")
        #expect(resolved.location == nil && resolved.notes == nil && resolved.emoji == nil && resolved.celebration == nil)
        #expect(resolved.isBusy)
        #expect(resolved.start == raw.start && resolved.end == raw.end)
        #expect(resolved.owner == .person(3))
        #expect(resolved.sticker == nil)
    }

    @Test("Full calendars keep the details and get an emoji; hidden ones are dropped")
    func fullAndHidden() throws {
        let resolved = try #require(CalendarEvent.resolve(raw, source: source()))
        #expect(resolved.title == "Dentist" && resolved.emoji == "🦷")
        #expect(resolved.location == "Dr. Patel" && resolved.notes == "Bring forms")
        #expect(resolved.owner == .everyone)
        #expect(CalendarEvent.resolve(raw, source: source(shown: false)) == nil)
    }

    @Test("A typed leading emoji wins and is not repeated in the title")
    func typedEmoji() throws {
        var typed = raw
        typed.title = "🎾 Dentist then tennis"
        let resolved = try #require(CalendarEvent.resolve(typed, source: source()))
        #expect(resolved.emoji == "🎾")
        #expect(resolved.title == "Dentist then tennis")
    }

    @Test("Contacts' birthdays are celebrations even without the word")
    func birthdaysCalendar() throws {
        var birthday = raw
        birthday.title = "Sam Lee"
        let resolved = try #require(CalendarEvent.resolve(birthday, source: source(), kind: .birthdays))
        #expect(resolved.celebration == .birthday && resolved.emoji == "🎂" && resolved.isFromSpecialCalendar)
        #expect(resolved.sticker == "🎂")
    }

    @Test("Emoji decoration", arguments: [
        ("Soccer practice", "⚽️"),
        ("TENNIS with Sam", "🎾"),
        ("Pottery class", "🏺"),
        ("Book club", "📚"),
        ("Book club lunch", "📚"),
        ("Climbing gym", "🧗"),
        ("Grandma's birthday dinner", "🎂"),
        ("Grandma's 80th", "🎂"),
        ("Leo turns 6", "🎂"),
        ("Our anniversary", "🥂"),
        ("Flight to Seattle", "✈️"),
        ("Taco Tuesday", "🌮"),
        ("Yoga", "🧘"),
        ("Haircut", "✂️"),
        ("Movies with the kids", "🎬"),
        ("Thanksgiving", "🦃"),
    ])
    func decoration(title: String, emoji: String) {
        #expect(EventDecoration.match(title)?.emoji == emoji)
    }

    @Test("Matching is by whole words, and misses return nil")
    func wholeWords() {
        #expect(EventDecoration.match("Gymnastics recital") == nil)   // not "gym"
        #expect(EventDecoration.match("Design review") == nil)
        #expect(EventDecoration.match("") == nil)
        #expect(EventDecoration.match("Car service 300th mile") == nil)  // not a plausible age
        #expect(EventDecoration.match("Birthdays")?.celebration == .birthday)  // plural
        #expect(EventDecoration.match("Dinner")?.celebration == nil)
    }

    @Test("All-day days: an end at midnight does not spill into the next day")
    func dayRange() {
        let rosa = event("r", start: date(6), end: date(9), allDay: true)
        let range = rosa.dayRange(in: calendar)
        #expect(range.first == key(6) && range.last == key(8))
        #expect(rosa.touches(key(8), in: calendar) && !rosa.touches(key(9), in: calendar))
        #expect(EventText.daySpan(rosa, calendar: calendar) == "Fri-Sun")
        let single = event("s", start: date(6), end: date(7), allDay: true)
        #expect(EventText.daySpan(single, calendar: calendar) == nil)
        let late = event("l", start: date(6, 22), end: date(7, 1))
        #expect(late.dayRange(in: calendar) == (key(6), key(7)))
        #expect(!late.isAllDayLike)
    }
}

// MARK: - Countdowns

@Suite("Countdowns")
struct CountdownTests {
    @Test("Picks upcoming celebrations and special all-day events, nearest first")
    func selection() {
        let events = [
            event("past", "Old birthday", start: date(1), end: date(2), allDay: true, celebration: .birthday),
            event("gran", "Grandma's 80th", start: date(12, 18), end: date(12, 21), celebration: .birthday),
            event("anniv", "Our anniversary", start: date(21), end: date(22), allDay: true, celebration: .anniversary),
            event("holiday", "Veterans Day", start: date(11), end: date(12), allDay: true, special: true),
            event("special-timed", "Holiday party prep", start: date(10, 9), end: date(10, 10), special: true),
            event("plain", "Seattle trip", start: date(9), end: date(10), allDay: true),
            event("busy", "Busy", start: date(8), end: date(9), allDay: true, celebration: .birthday, busy: true),
            event("far", "Sam's birthday", start: date(20, month: 12), end: date(21, month: 12), allDay: true, celebration: .birthday),
        ]
        let picked = CountdownPicker.pick(from: events, today: key(7), calendar: calendar, limit: 5)
        #expect(picked.map(\.id) == ["holiday", "gran", "anniv"])
        #expect(picked.map(\.daysUntil) == [4, 5, 14])
    }

    @Test("Limit, today, and repeats of the same day")
    func limitsAndDuplicates() {
        let events = [
            event("a", "Mia's birthday", start: date(7), end: date(8), allDay: true, celebration: .birthday),
            event("a2", "Mia's Birthday", start: date(7), end: date(8), allDay: true, celebration: .birthday),
            event("b", "Anniversary", start: date(8), end: date(9), allDay: true, celebration: .anniversary),
            event("c", "Thanksgiving", start: date(26), end: date(27), allDay: true, celebration: .holiday),
            event("d", "Christmas", start: date(25, month: 12), end: date(26, month: 12), allDay: true, celebration: .holiday),
        ]
        let picked = CountdownPicker.pick(from: events, today: key(7), calendar: calendar, limit: 2)
        #expect(picked.map(\.id) == ["a", "b"])
        #expect(picked.first?.daysUntil == 0)
        #expect(CountdownPicker.pick(from: events, today: key(7), calendar: calendar).map(\.id) == ["a", "b", "c"])
        #expect(CountdownPicker.pick(from: [], today: key(7), calendar: calendar).isEmpty)
    }
}

// MARK: - Layout

@Suite("Calendar layout")
struct CalendarLayoutTests {
    private func item(_ id: String, _ start: Double, _ end: Double) -> OverlapLayout.Item<String> {
        OverlapLayout.Item(id: id, start: date(9, start), end: date(9, end))
    }

    @Test("Separate events take the full width")
    func noOverlap() {
        let slots = OverlapLayout.slots([item("a", 9, 10), item("b", 10, 11), item("c", 13, 14)])
        #expect(slots.values.allSatisfy { $0 == .init(column: 0, columns: 1) })
    }

    @Test("Overlapping events sit side by side")
    func sideBySide() {
        let slots = OverlapLayout.slots([item("a", 9, 11), item("b", 10, 12)])
        #expect(slots["a"] == .init(column: 0, columns: 2))
        #expect(slots["b"] == .init(column: 1, columns: 2))
    }

    @Test("A chain shares one width and reuses free columns")
    func chain() {
        let slots = OverlapLayout.slots([item("a", 9, 10.5), item("b", 10, 12), item("c", 11, 12), item("d", 15, 16)])
        #expect(slots["a"] == .init(column: 0, columns: 2))
        #expect(slots["b"] == .init(column: 1, columns: 2))
        #expect(slots["c"] == .init(column: 0, columns: 2))
        #expect(slots["d"] == .init(column: 0, columns: 1))
    }

    @Test("Three at once get three columns")
    func three() {
        let slots = OverlapLayout.slots([item("a", 9, 12), item("b", 9, 10), item("c", 9.5, 11)])
        #expect(Set(slots.values.map(\.column)) == [0, 1, 2])
        #expect(slots.values.allSatisfy { $0.columns == 3 })
        #expect(slots["a"]?.column == 0)  // the longest starts on the left
    }

    @Test("All-day bars span days, clip to the week and pack into rows")
    func allDayBars() {
        let days = (1...7).map { key($0) }
        let bars = AllDayLayout.bars(for: [
            event("rosa", start: date(6), end: date(9), allDay: true),
            event("before", start: date(28, month: 10), end: date(3), allDay: true),
            event("mon", start: date(2), end: date(3), allDay: true),
            event("wed", start: date(4), end: date(5), allDay: true),
            event("long", start: date(4, 9), end: date(5, 12)),
            event("short", start: date(4, 9), end: date(4, 10)),
            event("outside", start: date(10), end: date(11), allDay: true),
        ], days: days, calendar: calendar)
        let byId = Dictionary(uniqueKeysWithValues: bars.map { ($0.id, $0) })
        #expect(bars.count == 5)
        #expect(byId["before"] == .init(id: "before", startIndex: 0, endIndex: 1, row: 0, continuesBefore: true, continuesAfter: false))
        #expect(byId["mon"]?.row == 1)
        #expect(byId["rosa"].map { ($0.startIndex, $0.endIndex, $0.row, $0.continuesAfter) } ?? (0, 0, 0, false) == (5, 6, 0, true))
        #expect(byId["long"].map { ($0.startIndex, $0.endIndex) } ?? (0, 0) == (3, 4))
        #expect(Set([byId["wed"]?.row, byId["long"]?.row]) == [0, 1])
    }

    @Test("The hour range widens to fit early and late events")
    func hours() {
        let days = [key(9)]
        #expect(HourRange.fitting([], days: days, calendar: calendar) == 8...21)
        let early = event("e", start: date(9, 6.5), end: date(9, 7))
        let late = event("l", start: date(9, 21), end: date(9, 22.25))
        #expect(HourRange.fitting([early, late], days: days, calendar: calendar) == 6...23)
        let overnight = event("o", start: date(9, 23), end: date(10, 2))
        #expect(HourRange.fitting([overnight], days: days, calendar: calendar) == 8...24)
        #expect(HourRange.fitting([overnight], days: [key(10)], calendar: calendar) == 0...21)
    }

    @Test("The hour range also fits the household's moments")
    func hoursForMoments() {
        let days = [key(9)]
        #expect(HourRange.fitting([], moments: [date(9, 6.25)], days: days, calendar: calendar) == 6...21)
        #expect(HourRange.fitting([], moments: [date(9, 22.5)], days: days, calendar: calendar) == 8...23)
    }

    @Test("Moment marks sit at their times and never overlap")
    func momentLayout() {
        // Far apart: centered on their times.
        #expect(MomentLayout.tops(centers: [50, 200], size: 28, spacing: 2, limit: 500) == [36, 186])
        // Close together: each pushed just below the one before.
        #expect(MomentLayout.tops(centers: [100, 105, 110], size: 28, spacing: 2, limit: 500) == [86, 116, 146])
        // Near the top: kept inside the grid.
        #expect(MomentLayout.tops(centers: [0], size: 28, spacing: 2, limit: 500) == [2])
        // Pushed past the bottom: stacked back up from it.
        #expect(MomentLayout.tops(centers: [480, 490], size: 28, spacing: 2, limit: 500) == [442, 472])
    }
}

// MARK: - Store

@MainActor
private final class FakeProvider: CalendarProvider {
    var access: CalendarAccess = .granted
    var onChange: (@MainActor () -> Void)?
    var calendarList: [ExternalCalendar] = []
    var eventList: [ExternalEvent] = []

    func requestAccess() async -> CalendarAccess { access }
    func calendars() -> [ExternalCalendar] { calendarList }
    func events(in interval: DateInterval, calendarIds: Set<String>) -> [ExternalEvent] {
        eventList.filter { calendarIds.contains($0.calendarId) && $0.end > interval.start && $0.start < interval.end }
    }
}

@MainActor
@Suite("Calendar store")
struct CalendarStoreTests {
    private func makeStore() throws -> (CalendarStore, FakeProvider, AppDatabase, [Person]) {
        let db = try AppDatabase.inMemory()
        try db.createHousehold(
            name: "Home",
            people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)],
            timeZone: calendar.timeZone,
            calendar: calendar
        )
        let provider = FakeProvider()
        provider.calendarList = [
            ExternalCalendar(id: "james", title: "James", account: "", colorHex: 0),
            ExternalCalendar(id: "work", title: "Work", account: "james@example.com", colorHex: 0),
            ExternalCalendar(id: "us", title: "Us", account: "", colorHex: 0),
        ]
        provider.eventList = [
            ExternalEvent(id: "climb", calendarId: "james", title: "Climbing gym", location: "Mission Cliffs", start: date(7, 10), end: date(7, 11.5), isAllDay: false),
            ExternalEvent(id: "standup", calendarId: "work", title: "Secret project", location: "Room 4", start: date(7, 9), end: date(7, 9.5), isAllDay: false),
            ExternalEvent(id: "rosa", calendarId: "us", title: "Aunt Rosa visiting", start: date(6), end: date(9), isAllDay: true),
            ExternalEvent(id: "gran", calendarId: "us", title: "Grandma's 80th", location: "Lucia's", start: date(12, 18), end: date(12, 21), isAllDay: false),
        ]
        let store = CalendarStore(database: db, provider: provider, now: { date(7, 9.7) })
        return (store, provider, db, try db.snapshot().people)
    }

    @Test("Today outputs: timeline items, all-day chips and countdowns")
    func todayOutputs() throws {
        let (store, _, _, people) = try makeStore()
        store.setVisibility(.busy, for: try #require(store.mappings.first { $0.calendar.id == "work" }?.source))
        store.reload()
        let items = store.timelineItems(for: key(7))
        #expect(items.map(\.title) == ["Busy", "Climbing gym"])
        let climb = try #require(items.last)
        #expect(climb.kind == .event)
        #expect(climb.owner == .person(try #require(people.first { $0.name == "James" }?.id)))
        #expect(climb.subtitle?.hasSuffix(" · Mission Cliffs") == true)
        #expect(climb.subtitle?.contains(" - ") == true)
        #expect(items.first?.subtitle?.contains("Room 4") == false)

        let allDay = store.allDayItems(for: key(7))
        #expect(allDay.map(\.title) == ["🧳 Aunt Rosa visiting · Fri-Sun"])
        #expect(allDay.first?.owner == .everyone)
        #expect(store.allDayItems(for: key(9)).isEmpty)

        #expect(store.countdowns().map(\.event.title) == ["Grandma's 80th"])
        #expect(store.countdowns().first?.daysUntil == 5)
    }

    @Test("Mapping edits flow through to the events")
    func edits() throws {
        let (store, _, db, people) = try makeStore()
        let work = try #require(store.mappings.first { $0.calendar.id == "work" }?.source)
        #expect(work.visibility == .full)
        store.setVisibility(.busy, for: work)
        store.reload()
        #expect(store.timelineItems(for: key(7)).map(\.title) == ["Busy", "Climbing gym"])

        store.setVisibility(.full, for: try #require(store.mappings.first { $0.calendar.id == "work" }?.source))
        store.reload()
        #expect(store.timelineItems(for: key(7)).map(\.title) == ["Secret project", "Climbing gym"])

        let james = try #require(store.mappings.first { $0.calendar.id == "james" }?.source)
        store.setShown(false, for: james)
        let mia = try #require(people.first { $0.name == "Mia" }?.id)
        store.setOwner(.person(mia), for: try #require(store.mappings.first { $0.calendar.id == "work" }?.source))
        store.reload()
        let items = store.timelineItems(for: key(7))
        #expect(items.map(\.title) == ["Secret project"])
        #expect(items.first?.owner == .person(mia))
        #expect(store.lastError == nil)

        store.setOwner(.person(12345), for: try #require(store.mappings.first?.source))
        #expect(store.lastError != nil)
        _ = db
    }

    @Test("New calendars from the provider are picked up on change")
    func providerChange() throws {
        let (store, provider, _, _) = try makeStore()
        provider.calendarList.append(ExternalCalendar(id: "mia", title: "Mia", account: "", colorHex: 0))
        provider.eventList.append(ExternalEvent(id: "pottery", calendarId: "mia", title: "Pottery class", start: date(7, 15), end: date(7, 17), isAllDay: false))
        provider.onChange?()
        #expect(store.mappings.count == 4)
        #expect(store.timelineItems(for: key(7)).map(\.title).contains("Pottery class"))
    }

    @Test("Without access there is nothing to show")
    func noAccess() throws {
        let (store, provider, _, _) = try makeStore()
        provider.access = .denied
        provider.calendarList = []
        provider.eventList = []
        store.reload()
        #expect(store.access == .denied)
        #expect(store.timelineItems(for: key(7)).isEmpty)
        #expect(store.mappings.isEmpty)
    }
}
