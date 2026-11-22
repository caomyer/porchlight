import Foundation
import Testing
@testable import Porchlight

/// Adding, changing and deleting events, the home calendar and who an event is for
/// (docs/design/calendar-add-edit.md), against the fake provider, which writes in memory as
/// EventKit would and can change an event's shared id after it is saved. Clock pinned.
@MainActor
@Suite("Adding and editing events in the real calendar")
struct CalendarWriteTests {
    static let home = ExternalCalendar(id: "family", title: "Family", account: "Google · a@b.c", colorHex: 0x336699, accountKind: "Google", allowsWrites: true)
    static let work = ExternalCalendar(id: "work", title: "Work", account: "Exchange", colorHex: 0x777777, accountKind: "Exchange", allowsWrites: false)

    private func make(calendars: [ExternalCalendar] = [home, work]) throws -> (CalendarStore, FixedCalendarProvider, AppDatabase, [Person]) {
        let db = try AppDatabase.inMemory(installId: "writes")
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "Mia", color: .coral), PersonDraft(name: "Leo", color: .blue)])
        try db.saveThisDevice(ThisDevice(name: "Mia's iPhone", role: .personal, model: "iPhone"), in: household.id)
        let provider = FixedCalendarProvider(calendars: calendars, events: [])
        let store = CalendarStore(database: db, provider: provider, now: { SharedCalendarFixture.now }, passesOn: false)
        try db.markCalendarChoicesSeen()
        return (store, provider, db, try db.snapshot().people)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(400)) }

    private static func draft(_ title: String, hours: Double = 26, repeats: EventRepeat? = nil, calendar: String = "family") -> EventDraft {
        let start = SharedCalendarFixture.now.addingTimeInterval(hours * 3600)
        return EventDraft(calendarId: calendar, title: title, start: start, end: start.addingTimeInterval(3600), isAllDay: false, repeats: repeats)
    }

    // MARK: The home calendar

    @Test("A device finds the home calendar among its own: one writable match, none, read only, or two to ask about")
    func resolving() {
        let chosen = HomeCalendar(id: .derived("h"), householdId: .derived("h"), title: "Family", accountKind: "Google", chosenById: nil, chosenAt: .distantPast)
        #expect(HomeCalendarLogic.resolve(home: nil, calendars: [Self.home], sources: []) == .notChosen)
        #expect(HomeCalendarLogic.resolve(home: chosen, calendars: [Self.home, Self.work], sources: []) == .found(Self.home))
        #expect(HomeCalendarLogic.resolve(home: chosen, calendars: [Self.work], sources: []) == .notHere(chosen))
        var readOnly = Self.home
        readOnly.allowsWrites = false
        #expect(HomeCalendarLogic.resolve(home: chosen, calendars: [readOnly], sources: []) == .readOnly(readOnly))
        var twin = Self.home
        twin.id = "family-2"
        #expect(HomeCalendarLogic.resolve(home: chosen, calendars: [Self.home, twin], sources: []) == .ambiguous([Self.home, twin]))
        // Once told which, it is that one.
        var source = CalendarSource(householdId: .derived("h"), externalId: "family-2", title: "Family", account: "", colorHex: 0, visibility: .full, isShown: true, createdAt: .distantPast)
        source.isHome = true
        #expect(HomeCalendarLogic.resolve(home: chosen, calendars: [Self.home, twin], sources: [source]) == .found(twin))
        // Renamed in Google: it isn't found by its old name.
        var renamed = Self.home
        renamed.title = "Our family"
        #expect(HomeCalendarLogic.resolve(home: chosen, calendars: [renamed], sources: []) == .notHere(chosen))
    }

    @Test("Choosing a calendar, or making one, makes it the household's home calendar")
    func choosing() async throws {
        let (store, _, _, _) = try make()
        #expect(store.home == .notChosen)
        #expect(store.writableCalendars == [Self.home], "only the calendars it may write")
        store.chooseHome(Self.home)
        try await settle()
        #expect(store.home == .found(Self.home))
        try store.makeHomeCalendar(title: "Home")
        try await settle()
        #expect(store.home.calendar?.title == "Home")
        #expect(store.snapshot.home?.title == "Home" && store.snapshot.home?.accountKind == "iCloud")
    }

    // MARK: Adding

    @Test("An added event is in the calendar, shows at once, and is for whom the sheet said")
    func adding() async throws {
        let (store, provider, db, people) = try make()
        store.chooseHome(Self.home)
        try await settle()
        let leo = try #require(people.first { $0.name == "Leo" })
        try store.save(Self.draft("Leo dentist"), for: [leo.id])
        try await settle()
        #expect(provider.store.events.map(\.title) == ["Leo dentist"])
        let shown = try #require(store.events.first { $0.title == "Leo dentist" })
        #expect(shown.owner == .person(leo.id), "for Leo, not the calendar's owner")
        let householdId = try #require(store.snapshot.household?.id)
        #expect(try db.eventFors(householdId: householdId).count == 1)
    }

    @Test("For the calendar's own owner, no record is kept; for everyone on a person's calendar, one is")
    func forTheOwner() async throws {
        let (store, _, db, people) = try make()
        let mia = try #require(people.first { $0.name == "Mia" })
        let source = try #require(store.mappings.first { $0.calendar.id == "family" }?.source)
        store.setOwner(.person(mia.id), for: source)
        try await settle()
        let householdId = try #require(store.snapshot.household?.id)
        try store.save(Self.draft("Gym"), for: [mia.id])
        try await settle()
        #expect(try db.eventFors(householdId: householdId).isEmpty)
        try store.save(Self.draft("Movie night", hours: 30), for: [])
        try await settle()
        #expect(try db.eventFors(householdId: householdId).map(\.personIds) == [""])
        #expect(store.events.first { $0.title == "Movie night" }?.owner == .everyone)
    }

    @Test("A calendar that can't be written to refuses, and says which")
    func readOnly() throws {
        let (store, _, _, _) = try make()
        #expect(throws: CalendarWriteError.readOnly("Work")) { try store.save(Self.draft("Standup", calendar: "work"), for: []) }
    }

    // MARK: Editing and deleting

    @Test("Changing one occurrence of a weekly event leaves the others; changing this and future ones changes those after")
    func spans() async throws {
        let (store, provider, _, _) = try make()
        try store.save(Self.draft("Piano", repeats: .weekly), for: [])
        try await settle()
        let occurrences = provider.store.events.sorted { $0.start < $1.start }
        #expect(occurrences.count == 8)
        let second = try #require(store.events.first { $0.id == occurrences[1].id })
        var changed = try #require(store.draft(for: second))
        changed.title = "Piano recital"
        try store.save(changed, span: .thisEvent, for: [])
        try await settle()
        #expect(provider.store.events.filter { $0.title == "Piano recital" }.count == 1)
        #expect(provider.store.events.filter { $0.title == "Piano" }.count == 7)

        let fourth = try #require(store.events.first { $0.id == occurrences[3].id })
        var moved = try #require(store.draft(for: fourth))
        moved.title = "Piano, new teacher"
        try store.save(moved, span: .futureEvents, for: [])
        try await settle()
        #expect(provider.store.events.filter { $0.title == "Piano" }.count == 2, "the first and third keep their title")
        #expect(provider.store.events.filter { $0.title == "Piano, new teacher" }.count == 8)
    }

    @Test("Deleting gives back what Undo needs, and Undo puts it back with who it is for")
    func deleteAndUndo() async throws {
        let (store, provider, _, people) = try make()
        let leo = try #require(people.first { $0.name == "Leo" })
        try store.save(Self.draft("Leo dentist"), for: [leo.id])
        try await settle()
        let event = try #require(store.events.first { $0.title == "Leo dentist" })
        let undo = try #require(try store.delete(event, span: .thisEvent))
        #expect(provider.store.events.isEmpty)
        #expect(undo.people == [leo.id] && undo.draft.title == "Leo dentist" && undo.draft.occurrenceId == nil)
        try store.save(undo.draft, for: undo.people)
        try await settle()
        #expect(store.events.first { $0.title == "Leo dentist" }?.owner == .person(leo.id))
    }

    @Test("Only this device's own events in calendars it may write can be changed")
    func whoCanChange() async throws {
        let (store, provider, _, _) = try make()
        provider.store.events.append(ExternalEvent(id: "standup@1", calendarId: "work", title: "Standup", start: SharedCalendarFixture.now.addingTimeInterval(3600), end: SharedCalendarFixture.now.addingTimeInterval(5400), isAllDay: false))
        try store.save(Self.draft("Soccer"), for: [])
        try await settle()
        #expect(store.events.first { $0.title == "Soccer" }.map(store.canChange) == true)
        #expect(store.events.first { $0.title == "Standup" }.map(store.canChange) == false)
        var other = try #require(store.events.first { $0.title == "Soccer" })
        other.from = "From Sam's Google"
        #expect(!store.canChange(other))
    }

    // MARK: The shared id changes

    @Test("An event made here keeps its For when its server hands back a new id, through the next pass")
    func idChangesAfterSave() async throws {
        let (store, provider, db, people) = try make()
        let leo = try #require(people.first { $0.name == "Leo" })
        let occurrence = try store.save(Self.draft("Leo dentist"), for: [leo.id])
        try await settle()
        let householdId = try #require(store.snapshot.household?.id)
        provider.store.changeExternalId(ofItem: EventForLogic.itemId(ofOccurrence: occurrence), to: "settled@google.com")
        store.reload()
        try await settle()
        // Before the pass: the fallback, by title and start.
        #expect(store.events.first { $0.title == "Leo dentist" }?.owner == .person(leo.id))
        store.passOn(.change)
        try await settle()
        let records = try db.eventFors(householdId: householdId)
        #expect(records.map(\.matchKey) == [CalendarPassOn.matchKey("settled@google.com")], "re-keyed by the pass")
        #expect(store.events.first { $0.title == "Leo dentist" }?.owner == .person(leo.id))
    }
}
