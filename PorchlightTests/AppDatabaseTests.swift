import Foundation
import GRDB
import Testing
@testable import Porchlight

@Suite("AppDatabase")
struct AppDatabaseTests {
    private let db: AppDatabase

    init() throws {
        db = try AppDatabase.inMemory()
    }

    @Test("Migrations create the household and person tables")
    func schema() throws {
        let tables = try db.writer.read { db in
            (household: try db.tableExists("household"), person: try db.tableExists("person"))
        }
        #expect(tables.household)
        #expect(tables.person)
    }

    @Test("A fresh database has no household")
    func emptySnapshot() throws {
        #expect(try db.snapshot() == .empty)
    }

    @Test("Creating a household stores trimmed names and keeps people in order")
    func createHousehold() throws {
        let tz = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        try db.createHousehold(
            name: "  The Lake House ",
            people: [PersonDraft(name: " James", color: .blue), PersonDraft(name: "Mia ", color: .coral)],
            timeZone: tz,
            calendar: calendar
        )

        let snapshot = try db.snapshot()
        #expect(snapshot.household?.name == "The Lake House")
        #expect(snapshot.household?.timeZoneIdentifier == "America/Los_Angeles")
        #expect(snapshot.household?.firstWeekday == 1)
        #expect(snapshot.people.map(\.name) == ["James", "Mia"])
        #expect(snapshot.people.map(\.color) == [.blue, .coral])
        #expect(snapshot.people.map(\.sortOrder) == [0, 1])
    }

    @Test("Invalid names are rejected and nothing is written")
    func validation() throws {
        #expect(throws: ValidationError.emptyName) {
            try db.createHousehold(name: "   ", people: [PersonDraft(name: "James", color: .blue)])
        }
        #expect(throws: ValidationError.emptyName) {
            try db.createHousehold(name: "Home", people: [PersonDraft(name: "", color: .blue)])
        }
        #expect(throws: ValidationError.noPeople) {
            try db.createHousehold(name: "Home", people: [])
        }
        #expect(throws: ValidationError.nameTooLong(limit: Names.limit)) {
            try db.createHousehold(name: String(repeating: "a", count: Names.limit + 1), people: [PersonDraft(name: "J", color: .blue)])
        }
        #expect(try db.snapshot() == .empty)
    }

    @Test("Adding, editing and reordering people")
    func editPeople() throws {
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        let householdId = household.id

        let mia = try db.addPerson(PersonDraft(name: "Mia", color: .coral), to: householdId)
        #expect(mia.sortOrder == 1)

        try db.updatePerson(id: mia.id, name: "Mia C", color: .plum)
        var people = try db.snapshot().people
        #expect(people[1].name == "Mia C")
        #expect(people[1].color == .plum)

        try db.reorderPeople(householdId: householdId, ids: people.reversed().map(\.id))
        people = try db.snapshot().people
        #expect(people.map(\.name) == ["Mia C", "James"])
    }

    @Test("Removing archives the person and renumbers the rest, and the last person cannot be removed")
    func removePeople() throws {
        try db.createHousehold(
            name: "Home",
            people: [PersonDraft(name: "A", color: .blue), PersonDraft(name: "B", color: .coral), PersonDraft(name: "C", color: .sage)]
        )
        var people = try db.snapshot().people
        let removed = people[1]
        try db.archivePerson(id: removed.id, now: Date(timeIntervalSince1970: 1_000))
        people = try db.snapshot().people
        #expect(people.map(\.name) == ["A", "C"])
        #expect(people.map(\.sortOrder) == [0, 1])
        let kept = try #require(try db.snapshot().everyone.first { $0.id == removed.id })
        #expect(kept.name == "B")
        #expect(kept.archivedAt == Date(timeIntervalSince1970: 1_000))

        try db.archivePerson(id: people[0].id)
        let last = try #require(try db.snapshot().people.first)
        #expect(throws: ValidationError.noPeople) {
            try db.archivePerson(id: last.id)
        }
        #expect(try db.snapshot().people.map(\.name) == ["C"])
        #expect(try db.snapshot().everyone.count == 3)
    }

    @Test("A new person goes after the people who live here now")
    func addAfterRemoving() throws {
        let household = try db.createHousehold(
            name: "Home", people: [PersonDraft(name: "A", color: .blue), PersonDraft(name: "B", color: .coral)]
        )
        try db.archivePerson(id: try db.snapshot().people[1].id)
        let added = try db.addPerson(PersonDraft(name: "C", color: .sage), to: household.id)
        #expect(added.sortOrder == 1)
        #expect(try db.snapshot().people.map(\.name) == ["A", "C"])
    }

    @Test("Renaming the household validates the name")
    func renameHousehold() throws {
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "J", color: .blue)])
        let id = household.id
        try db.renameHousehold(id: id, to: " Cao Home ")
        #expect(try db.snapshot().household?.name == "Cao Home")
        #expect(throws: ValidationError.emptyName) { try db.renameHousehold(id: id, to: "") }
    }

    @Test("Observation emits a new snapshot after a write")
    func observation() async throws {
        var iterator = db.householdUpdates().makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first == .empty)

        try db.createHousehold(name: "Home", people: [PersonDraft(name: "J", color: .blue)])
        let second = try await iterator.next()
        #expect(second?.household?.name == "Home")
        #expect(second?.people.count == 1)
    }
}

@Suite("Person")
struct PersonTests {
    @Test("Initial is the uppercased first letter", arguments: [("james", "J"), ("  mia", "M"), ("élodie", "É"), ("", "?")])
    func initial(name: String, expected: String) {
        let person = Person(householdId: 1, name: name, color: .blue, sortOrder: 0, createdAt: .now)
        #expect(person.initial == expected)
    }

    @Test("Suggested colors cycle through the palette")
    func suggestedColors() {
        #expect(PersonColor.suggested(for: 0) == .blue)
        #expect(PersonColor.suggested(for: 1) == .coral)
        #expect(PersonColor.suggested(for: PersonColor.allCases.count) == .blue)
    }
}
