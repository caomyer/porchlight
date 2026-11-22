import Foundation
import Testing
@testable import Porchlight

/// Whose a newly seen calendar is (`CalendarOwnerGuess`): a name in it wins; shared-sounding,
/// home, birthday, holiday and subscribed calendars are the household's; anything else is the
/// phone's own person's on a phone and the household's on the wall. And the one-time
/// correction of calendars an earlier build guessed as everyone's, which leaves alone any
/// owner someone picked.
@MainActor
@Suite("Whose a calendar is")
struct CalendarOwnerTests {
    static let james = Person(id: .derived("james"), householdId: .derived("h"), name: "James", color: .blue, sortOrder: 0, createdAt: .distantPast)
    static let mia = Person(id: .derived("mia"), householdId: .derived("h"), name: "Mia", color: .coral, sortOrder: 1, createdAt: .distantPast)

    static func calendar(_ title: String, account: String = "Google · jc1984@gmail.com", kind: ExternalCalendar.Kind = .regular) -> ExternalCalendar {
        var calendar = ExternalCalendar(id: title.isEmpty ? "untitled" : title, title: title, account: account, colorHex: 0x336699, accountKind: "Google")
        calendar.kind = kind
        return calendar
    }

    @Test(
        "The guess, swept over titles, on James's phone and on the wall",
        arguments: [
            ("James", "James", "James"),
            ("jc1984@gmail.com", "James", nil),
            ("Work", "James", nil),
            ("Family", nil, nil),
            ("Mia", "Mia", "Mia"),
            ("", "James", nil),
            ("Kids' soccer", nil, nil),
            ("US Holidays", nil, nil),
        ] as [(String, String?, String?)]
    )
    func guess(title: String, onPhone: String?, onWall: String?) {
        let people = [Self.james, Self.mia]
        func name(_ id: Person.ID?) -> String? { people.first { $0.id == id }?.name }
        let calendar = Self.calendar(title)
        #expect(name(CalendarOwnerGuess.owner(for: calendar, people: people, phoneOwner: Self.james.id)) == onPhone, "on James's phone")
        #expect(name(CalendarOwnerGuess.owner(for: calendar, people: people)) == onWall, "on the wall")
        // On Mia's phone the phone's own default is Mia, and a name still wins.
        let onMias = name(CalendarOwnerGuess.owner(for: calendar, people: people, phoneOwner: Self.mia.id))
        #expect(onMias == (onPhone == "James" && title != "James" ? "Mia" : onPhone))
    }

    @Test("Birthdays, subscribed calendars, the home calendar and an owner no longer in the household are the household's")
    func householdOnes() {
        let people = [Self.james, Self.mia]
        #expect(CalendarOwnerGuess.owner(for: Self.calendar("Birthdays", kind: .birthdays), people: people, phoneOwner: Self.james.id) == nil)
        #expect(CalendarOwnerGuess.owner(for: Self.calendar("Team", kind: .subscribed), people: people, phoneOwner: Self.james.id) == nil)
        #expect(CalendarOwnerGuess.owner(for: Self.calendar("Chen"), people: people, phoneOwner: Self.james.id, isHome: true) == nil)
        #expect(CalendarOwnerGuess.owner(for: Self.calendar("Chen"), people: people, phoneOwner: .derived("gone")) == nil)
        // A name in the account still counts, as before.
        #expect(CalendarOwnerGuess.owner(for: Self.calendar("Chen", account: "iCloud · mia@me.com"), people: people) == Self.mia.id)
    }

    @Test("An email address as a title is known, and passed on as no title at all")
    func addresses() {
        #expect(CalendarOwnerGuess.isAddress("jc1984@gmail.com"))
        #expect(CalendarOwnerGuess.isAddress(" james.c@example.co.uk "))
        #expect(!CalendarOwnerGuess.isAddress("James"))
        #expect(!CalendarOwnerGuess.isAddress("@home"))
        #expect(!CalendarOwnerGuess.isAddress("lunch @ noon"))
        #expect(!CalendarOwnerGuess.isAddress("x@y"))
        let source = CalendarSource(householdId: .derived("h"), externalId: "jc1984@gmail.com", title: "jc1984@gmail.com", account: "", colorHex: 0, visibility: .full, isShown: true, createdAt: .distantPast)
        let record = CalendarPassOn.calendarRecord(source, calendar: Self.calendar("jc1984@gmail.com"), deviceId: .derived("d"))
        #expect(record?.title == "" && record?.accountKind == "Google", "the household reads: From James's Google")
    }

    // MARK: On a device

    private func household(role: DeviceRole, person: String?) throws -> (AppDatabase, Household.ID, [Person]) {
        let db = try AppDatabase.inMemory(installId: "owners")
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)])
        let people = try db.snapshot().people
        let personId = people.first { $0.name == person }?.id
        try db.saveThisDevice(ThisDevice(name: "This one", role: role, model: role == .personal ? "iPhone" : "iPad", personId: personId), in: household.id)
        return (db, household.id, people)
    }

    private func owners(_ db: AppDatabase) throws -> [String: Person.ID?] {
        Dictionary(uniqueKeysWithValues: try db.calendarSnapshot().sources.map { ($0.title, $0.ownerId) })
    }

    @Test("On James's phone his address calendar is his; on the wall it is everyone's")
    func newCalendars() throws {
        let calendars = [Self.calendar("jc1984@gmail.com"), Self.calendar("Family"), Self.calendar("Mia")]
        let (phone, phoneHousehold, phonePeople) = try household(role: .personal, person: "James")
        try phone.syncCalendarSources(householdId: phoneHousehold, calendars: calendars)
        let james = phonePeople.first { $0.name == "James" }?.id
        let mia = phonePeople.first { $0.name == "Mia" }?.id
        #expect(try owners(phone) == ["jc1984@gmail.com": james, "Family": nil, "Mia": mia])

        let (wall, wallHousehold, _) = try household(role: .sharedScreen, person: nil)
        try wall.syncCalendarSources(householdId: wallHousehold, calendars: calendars)
        #expect(try owners(wall)["jc1984@gmail.com"] == .some(nil))
    }

    @Test("Once the phone's person is known, calendars an earlier build guessed as everyone's are guessed again, once; a picked owner is left alone")
    func correction() async throws {
        let (db, householdId, people) = try household(role: .personal, person: nil)
        let james = try #require(people.first { $0.name == "James" }?.id)
        let calendars = [Self.calendar("jc1984@gmail.com"), Self.calendar("Work"), Self.calendar("Family")]
        // As an earlier build left them: everyone's, the person not yet known.
        try db.syncCalendarSources(householdId: householdId, calendars: calendars)
        #expect(try owners(db).values.allSatisfy { $0 == nil })
        // Someone picked Everyone for Work by hand.
        let work = try #require(try db.calendarSnapshot().sources.first { $0.title == "Work" })
        try db.setCalendarSourceOwner(id: work.id, owner: .everyone)

        // This phone becomes James's (or the new build starts with him known).
        try db.saveThisDevice(ThisDevice(name: "James's iPhone", role: .personal, model: "iPhone", personId: james), in: householdId)
        try db.syncCalendarSources(householdId: householdId, calendars: calendars)
        let after = try owners(db)
        #expect(after["jc1984@gmail.com"] == .some(james), "his own, guessed again")
        #expect(after["Work"] == .some(nil), "picked by hand, left alone")
        #expect(after["Family"] == .some(nil), "the household's still")

        // Once: an owner set back to everyone afterwards, by any path, stays.
        let address = try #require(try db.calendarSnapshot().sources.first { $0.title == "jc1984@gmail.com" })
        try await db.writer.write { db in try db.execute(sql: "UPDATE calendarSource SET ownerId = NULL WHERE id = ?", arguments: [address.id]) }
        try db.syncCalendarSources(householdId: householdId, calendars: calendars)
        #expect(try owners(db)["jc1984@gmail.com"] == .some(nil))
    }

    @Test("Choosing a calendar as the home calendar makes it everyone's, unless someone picked its owner")
    func homeIsEveryones() throws {
        let (db, householdId, people) = try household(role: .personal, person: "James")
        let james = try #require(people.first { $0.name == "James" }?.id)
        let chen = Self.calendar("Chen")
        try db.syncCalendarSources(householdId: householdId, calendars: [chen])
        #expect(try owners(db)["Chen"] == .some(james))
        try db.chooseHomeCalendar(chen, householdId: householdId)
        #expect(try owners(db)["Chen"] == .some(nil))
    }

    @Test("An event in James's address calendar keeps only James busy in Free together")
    func freeTogether() async throws {
        let (db, householdId, people) = try household(role: .personal, person: "James")
        let james = try #require(people.first { $0.name == "James" }?.id)
        let mia = try #require(people.first { $0.name == "Mia" }?.id)
        let now = Date(timeIntervalSince1970: 1_795_017_600)  // Wednesday 8 AM in Los Angeles
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let address = Self.calendar("jc1984@gmail.com")
        let evening = DayKey(rawValue: "2026-11-18").startDate(in: calendar).addingTimeInterval(18 * 3600)
        let dinner = ExternalEvent(id: "d@1", calendarId: address.id, title: "Dinner with Sam", start: evening, end: evening.addingTimeInterval(3 * 3600), isAllDay: false)
        try db.syncCalendarSources(householdId: householdId, calendars: [address])
        let store = CalendarStore(database: db, provider: FixedCalendarProvider(calendars: [address], events: [dinner]), now: { now }, passesOn: false)
        for _ in 0..<50 where store.events.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        let tonight = try #require(FreeTogetherLogic.times(events: store.events, people: [james, mia], from: now, calendar: calendar).first)
        #expect(tonight.free[james] == nil && tonight.free[mia] != nil, "James busy, Mia free")
        #expect(tonight.busy.first?.people == [james])
    }

    @Test("Whose a calendar is, changed on the phone, reaches the calendar it passes on")
    func passedOn() async throws {
        let (db, householdId, people) = try household(role: .personal, person: "James")
        let james = try #require(people.first { $0.name == "James" }?.id)
        let address = Self.calendar("jc1984@gmail.com")
        try db.syncCalendarSources(householdId: householdId, calendars: [address])
        try db.markCalendarChoicesSeen()
        let store = CalendarStore(database: db, provider: FixedCalendarProvider(calendars: [address], events: []), passesOn: false)
        for _ in 0..<50 where !store.snapshot.choicesSeen { try await Task.sleep(for: .milliseconds(100)) }
        func passedOwner() throws -> Person.ID?? {
            try db.writer.read { try SharedCalendar.fetchAll($0).first.map(\.ownerId) }
        }
        _ = store.passOn(.open)
        #expect(try passedOwner() == .some(james))
        let source = try #require(store.snapshot.sources.first)
        store.setOwner(.everyone, for: source)
        for _ in 0..<50 where store.snapshot.sources.first?.ownerId != nil { try await Task.sleep(for: .milliseconds(100)) }
        _ = store.passOn(.choice)
        #expect(try passedOwner() == .some(nil), "everyone's, for every device")
        #expect(try db.calendarSnapshot().sources.first?.ownerChosen == true, "and picked, so no guess changes it again")
    }
}
