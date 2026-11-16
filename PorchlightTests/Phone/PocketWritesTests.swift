import Foundation
import GRDB
import Testing
@testable import Porchlight

/// The phone's writes against an in-memory database: logging one slot never doubles
/// a slot someone already did ("never confidently out of date"), joining and undoing,
/// and checking off a chore that someone else just did.
@Suite("Phone writes")
struct PocketWritesTests {
    private let db: AppDatabase
    private let householdId: Household.ID
    private let james: Person.ID
    private let mia: Person.ID
    private let walk: CareRoutine
    private let calendar: Calendar

    /// Saturday, November 7 2026 at 6:05 pm in the household's time zone: the evening walk is open.
    private let now: Date
    private var today: DayKey { DayKey(now, calendar: calendar) }

    init() throws {
        db = try AppDatabase.inMemory()
        let household = try db.createHousehold(
            name: "Home", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)],
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        householdId = household.id
        calendar = household.calendar
        let people = try db.snapshot().people
        james = people[0].id
        mia = people[1].id
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        let companionId = try db.saveCompanion(draft, householdId: household.id)
        walk = try #require(try db.writer.read(CompanionSnapshot.fetch).routines(of: companionId).first { $0.kind == .walk })
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 18, minute: 5))!
    }

    private func draft(_ people: [Person.ID], at date: Date) -> CareLogDraft {
        CareLogDraft(people: people, occurredAt: date, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
    }

    private func entries() throws -> [CareEntry] {
        try db.writer.read(CompanionSnapshot.fetch).entries(of: walk.id)
    }

    @Test("Logging an open slot adds the log, credited to who was given")
    func logsAnOpenSlot() throws {
        let result = try db.logCare(routineId: walk.id, slot: 1, on: today, draft([james, mia], at: now), now: now)
        guard case let .logged(log) = result else { Issue.record("Expected a new log"); return }
        let stored = try entries()
        #expect(stored.map(\.id) == [log.id])
        #expect(Set(stored[0].people) == [james, mia])
        #expect(stored[0].log.stars == walk.stars)
    }

    @Test("A slot someone already logged gets their log back, and nothing is added")
    func alreadyLogged() throws {
        let miasWalk = try db.logCare(routineId: walk.id, draft([mia], at: now.addingTimeInterval(-25 * 60)), now: now)
        let result = try db.logCare(routineId: walk.id, slot: 1, on: today, draft([james], at: now), now: now)
        #expect(result == .alreadyLogged(CareEntry(log: miasWalk, people: [mia])))
        #expect(try entries().count == 1)
    }

    @Test("Another slot of the same day is still logged")
    func otherSlotStillLogs() throws {
        let morning = calendar.date(byAdding: .hour, value: -10, to: now)!
        _ = try db.logCare(routineId: walk.id, draft([mia], at: morning), now: now)
        let result = try db.logCare(routineId: walk.id, slot: 1, on: today, draft([james], at: now), now: now)
        if case .alreadyLogged = result { Issue.record("The evening was still open") }
        #expect(try entries().count == 2)
    }

    @Test("\"I went too\" adds me to the log, and its undo takes only me off")
    func joinAndUndo() throws {
        let miasWalk = try db.logCare(routineId: walk.id, draft([mia], at: now), now: now)
        try db.addPeople([james], toCareLog: miasWalk.id)
        #expect(Set(try entries()[0].people) == [james, mia])
        try db.addPeople([james], toCareLog: miasWalk.id)
        #expect(try entries()[0].people.count == 2, "Joining twice is still one credit")
        try db.removePeople([james], fromCareLog: miasWalk.id)
        #expect(try entries()[0].people == [mia])
        #expect(throws: CareValidationError.noWalkers) { try db.removePeople([mia], fromCareLog: miasWalk.id) }
    }

    @Test("Undo removes the log, with its credit and stars")
    func undoLog() throws {
        guard case let .logged(log) = try db.logCare(routineId: walk.id, slot: 1, on: today, draft([james], at: now), now: now) else {
            Issue.record("Expected a new log"); return
        }
        try db.deleteCareLog(id: log.id)
        #expect(try entries().isEmpty)
        #expect(try db.writer.read { try CareLogPerson.fetchCount($0) } == 0)
    }

    // MARK: Chores

    private func chore(owner: Person.ID?) throws -> Chore {
        try db.saveChore(
            ChoreDraft(title: "Vacuum", emoji: "🧹", ownerId: owner, recurrence: .daily, anchorDay: today.adding(days: -3, calendar: calendar), timeHint: nil, stars: 2),
            householdId: householdId
        )
    }

    @Test("Checking off a shared chore credits me; a second check-off finds it done instead of unchecking it")
    func completeChore() throws {
        let vacuum = try chore(owner: nil)
        guard case let .done(mine) = try db.completeChore(id: vacuum.id, day: today, personId: james, now: now) else {
            Issue.record("Expected it checked off"); return
        }
        #expect(mine.personId == james)
        #expect(try db.completeChore(id: vacuum.id, day: today, personId: mia, now: now) == .alreadyDone(mine))
        let completions = try db.homeSnapshot(since: today.adding(days: -7, calendar: calendar)).completions
        #expect(completions.map(\.personId) == [james], "Still done, still by me")
    }

    @Test("Undoing a check-off removes just that completion")
    func undoChore() throws {
        let vacuum = try chore(owner: james)
        guard case let .done(completion) = try db.completeChore(id: vacuum.id, day: today, personId: nil, now: now) else {
            Issue.record("Expected it checked off"); return
        }
        #expect(completion.personId == james, "An owned chore credits its owner")
        try db.deleteChoreCompletion(id: completion.id)
        #expect(try db.homeSnapshot(since: today.adding(days: -7, calendar: calendar)).completions.isEmpty)
        try db.deleteChoreCompletion(id: completion.id)
    }
}
