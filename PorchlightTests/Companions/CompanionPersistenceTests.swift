import Foundation
import GRDB
import Testing
@testable import Porchlight

@Suite("Companion persistence")
struct CompanionPersistenceTests {
    struct Home {
        let db: AppDatabase
        let householdId: Int64
        let people: [Int64]
    }

    private func home() throws -> Home {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [
            PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral),
        ])
        let people = try db.snapshot().people.compactMap(\.id)
        return Home(db: db, householdId: try #require(household.id), people: people)
    }

    private func dog(_ home: Home, name: String = "Yo-Yo") throws -> Int64 {
        var draft = CompanionDraft.new(species: .dog, rotation: home.people)
        draft.name = name
        return try home.db.saveCompanion(draft, householdId: home.householdId)
    }

    @Test("Saving a companion stores it with its species preset routines")
    func saveNew() throws {
        let home = try home()
        let id = try dog(home)
        let snapshot = try home.db.writer.read(CompanionSnapshot.fetch)
        #expect(snapshot.companions.map(\.name) == ["Yo-Yo"])
        let routines = snapshot.routines(of: id)
        #expect(routines.map(\.kind) == [.walk, .feed])
        #expect(routines[0].windows.map(\.label) == ["Morning", "Evening"])
        #expect(routines[0].rotation == home.people)
        #expect(routines[0].trackedFields == CareField.allCases)
        #expect(routines[0].stars == 2)
    }

    @Test("Every species has sensible starting routines")
    func presets() {
        for species in Species.allCases {
            let routines = CompanionPresets.routines(for: species, rotation: [1])
            #expect(!routines.isEmpty, "\(species)")
            for routine in routines {
                #expect(throws: Never.self) { try CareRules.validated(routine, companionId: 1, sortOrder: 0, people: [1]) }
            }
        }
        #expect(CompanionPresets.routines(for: .cat, rotation: []).map(\.kind) == [.feed, .litter])
        #expect(CompanionPresets.routines(for: .plant, rotation: []).first?.everyDays == 3)
    }

    @Test("Updating keeps routine ids and history; removed routines go with their logs")
    func updateRoutines() throws {
        let home = try home()
        let id = try dog(home)
        var snapshot = try home.db.writer.read(CompanionSnapshot.fetch)
        let walk = snapshot.routines(of: id)[0]
        try home.db.logCare(routineId: walk.id!, CareLogDraft(people: [home.people[0]], occurredAt: .now.addingTimeInterval(-60)))
        let feed = snapshot.routines(of: id)[1]
        try home.db.logCare(routineId: feed.id!, CareLogDraft(people: [home.people[1]], occurredAt: .now.addingTimeInterval(-60)))

        var draft = CompanionDraft(snapshot.companions[0], routines: snapshot.routines(of: id))
        draft.name = "Yo-Yo Ma"
        draft.routines[0].stars = 3
        draft.routines.remove(at: 1)
        draft.routines.append(CareRoutineDraft(kind: .meds, windows: [.hours("Night", 20, 22)]))
        try home.db.saveCompanion(draft, householdId: home.householdId)

        snapshot = try home.db.writer.read(CompanionSnapshot.fetch)
        #expect(snapshot.companions[0].name == "Yo-Yo Ma")
        let routines = snapshot.routines(of: id)
        #expect(routines.map(\.kind) == [.walk, .meds])
        #expect(routines[0].id == walk.id)
        #expect(routines[0].stars == 3)
        #expect(snapshot.entries.count == 1, "the feed log was deleted with its routine")
        #expect(snapshot.entries[0].log.stars == 2, "logs keep the stars they earned")
    }

    @Test("Routine validation rejects bad windows, cadences and stars")
    func validation() throws {
        let people: Set<Int64> = [1, 2]
        func check(_ change: (inout CareRoutineDraft) -> Void) -> Error? {
            var draft = CompanionPresets.routines(for: .dog, rotation: [1, 2])[0]
            change(&draft)
            do {
                _ = try CareRules.validated(draft, companionId: 1, sortOrder: 0, people: people)
                return nil
            } catch {
                return error
            }
        }
        #expect(check { _ in } == nil)
        #expect(check { $0.title = "  " } as? ValidationError == .emptyName)
        #expect(check { $0.windows = [] } as? CareValidationError == .noWindows)
        #expect(check { $0.windows[0] = CareWindow("Morning", start: 600, end: 500) } as? CareValidationError == .invalidWindow("Morning"))
        #expect(check { $0.windows[1] = CareWindow("Evening", start: 540, end: 700) } as? CareValidationError == .overlappingWindows)
        #expect(check { $0.windows = Array(repeating: .hours("x", 1, 2), count: 7) } != nil)
        #expect(check { $0.everyDays = 0 } as? CareValidationError == .invalidCadence)
        #expect(check { $0.everyDays = 61 } as? CareValidationError == .invalidCadence)
        #expect(check { $0.stars = 11 } as? CareValidationError == .invalidStars)
        #expect(check { $0.nudgeAfterMinutes = 2 } as? CareValidationError == .invalidNudge)
        #expect(check { $0.windows[0].label = "" } as? ValidationError == .emptyName)
    }

    @Test("Validation cleans rotation, sorts windows and keeps one window for every-N-days")
    func validationCleanup() throws {
        var draft = CareRoutineDraft(
            kind: .walk, emoji: "  ", windows: [.hours("Evening", 17, 20), .hours("Morning", 6, 10)],
            rotation: [2, 99, 1, 2], trackedFields: [.pee, .pee]
        )
        let routine = try CareRules.validated(draft, companionId: 1, sortOrder: 0, people: [1, 2])
        #expect(routine.windows.map(\.label) == ["Morning", "Evening"])
        #expect(routine.rotation == [2, 1])
        #expect(routine.trackedFields == [.pee])
        #expect(routine.emoji == CareKind.walk.defaultEmoji)
        draft.everyDays = 3
        let sparse = try CareRules.validated(draft, companionId: 1, sortOrder: 0, people: [1, 2])
        #expect(sparse.windows.count == 1)
    }

    @Test("Companion names are validated")
    func companionName() throws {
        let home = try home()
        var draft = CompanionDraft.new(species: .cat, rotation: [])
        draft.name = "   "
        #expect(throws: ValidationError.emptyName) { try home.db.saveCompanion(draft, householdId: home.householdId) }
        draft.name = String(repeating: "a", count: 41)
        #expect(throws: ValidationError.nameTooLong(limit: 40)) { try home.db.saveCompanion(draft, householdId: home.householdId) }
    }

    @Test("Logging stores walkers together and only the routine's tracked fields")
    func logCare() throws {
        let home = try home()
        let id = try dog(home)
        let routines = try home.db.writer.read(CompanionSnapshot.fetch).routines(of: id)
        let walk = routines[0], feed = routines[1]
        let now = Date.now
        try home.db.logCare(routineId: walk.id!, CareLogDraft(
            people: home.people + [home.people[0]], occurredAt: now.addingTimeInterval(-1800), durationMinutes: 25,
            pee: true, poo: false, vibe: .squirrel, note: "  Squirrel situation handled  "
        ), now: now)
        try home.db.logCare(routineId: feed.id!, CareLogDraft(
            people: [home.people[1]], occurredAt: now, durationMinutes: 10, pee: true, vibe: .soggy
        ), now: now)
        let entries = try home.db.writer.read(CompanionSnapshot.fetch).entries
        #expect(entries.count == 2)
        let walkEntry = entries[0]
        #expect(walkEntry.people == home.people)
        #expect(walkEntry.log.durationMinutes == 25)
        #expect(walkEntry.log.vibe == .squirrel)
        #expect(walkEntry.log.note == "Squirrel situation handled")
        #expect(walkEntry.log.stars == 2)
        let feedEntry = entries[1]
        #expect(feedEntry.log.durationMinutes == nil)
        #expect(feedEntry.log.pee == nil)
        #expect(feedEntry.log.vibe == nil)
        #expect(feedEntry.log.stars == 1)
    }

    @Test("Logging rejects missing walkers, odd durations, long notes and future times")
    func logValidation() throws {
        let home = try home()
        let id = try dog(home)
        let walk = try home.db.writer.read(CompanionSnapshot.fetch).routines(of: id)[0]
        let now = Date.now
        func log(_ draft: CareLogDraft) throws { try home.db.logCare(routineId: walk.id!, draft, now: now) }
        #expect(throws: CareValidationError.noWalkers) { try log(CareLogDraft(people: [], occurredAt: now)) }
        #expect(throws: CareValidationError.invalidDuration) { try log(CareLogDraft(people: home.people, occurredAt: now, durationMinutes: 0)) }
        #expect(throws: CareValidationError.noteTooLong(limit: 280)) {
            try log(CareLogDraft(people: home.people, occurredAt: now, note: String(repeating: "x", count: 281)))
        }
        #expect(throws: CareValidationError.inTheFuture) { try log(CareLogDraft(people: home.people, occurredAt: now.addingTimeInterval(3600))) }
        #expect(throws: CareValidationError.unknownRoutine) { try home.db.logCare(routineId: 999, CareLogDraft(people: home.people, occurredAt: now)) }
    }

    @Test("Deleting a person removes their credit; deleting a companion removes everything")
    func cascades() throws {
        let home = try home()
        let id = try dog(home)
        let walk = try home.db.writer.read(CompanionSnapshot.fetch).routines(of: id)[0]
        try home.db.logCare(routineId: walk.id!, CareLogDraft(people: home.people, occurredAt: .now.addingTimeInterval(-60)))
        try home.db.deletePerson(id: home.people[1])
        var snapshot = try home.db.writer.read(CompanionSnapshot.fetch)
        #expect(snapshot.entries.first?.people == [home.people[0]])

        let second = try dog(home, name: "Biscuit")
        try home.db.deleteCompanion(id: id)
        snapshot = try home.db.writer.read(CompanionSnapshot.fetch)
        #expect(snapshot.companions.map(\.id) == [second])
        #expect(snapshot.companions.first?.sortOrder == 0, "remaining companions are renumbered")
        #expect(snapshot.entries.isEmpty)
        let routineCount = try home.db.writer.read { try CareRoutine.fetchCount($0) }
        #expect(routineCount == 2)

        _ = try home.db.writer.write { try Household.deleteAll($0) }
        let companions = try home.db.writer.read { try Companion.fetchCount($0) }
        #expect(companions == 0)
    }

    @Test("Companions can be reordered and logs deleted")
    func reorderAndDeleteLog() throws {
        let home = try home()
        let first = try dog(home, name: "A")
        let second = try dog(home, name: "B")
        try home.db.reorderCompanions(householdId: home.householdId, ids: [second, first])
        var snapshot = try home.db.writer.read(CompanionSnapshot.fetch)
        #expect(snapshot.companions.map(\.name) == ["B", "A"])
        let walk = snapshot.routines(of: first)[0]
        let log = try home.db.logCare(routineId: walk.id!, CareLogDraft(people: [home.people[0]], occurredAt: .now.addingTimeInterval(-60)))
        try home.db.deleteCareLog(id: log.id!)
        snapshot = try home.db.writer.read(CompanionSnapshot.fetch)
        #expect(snapshot.entries.isEmpty)
    }

    @Test("The report ties it together: slots, turns, streak and podium")
    func report() throws {
        let home = try home()
        let id = try dog(home)
        let walk = try home.db.writer.read(CompanionSnapshot.fetch).routines(of: id)[0]
        let calendar = try home.db.snapshot().household!.calendar
        let today = DayKey(.now, calendar: calendar)
        let morning = CareLogic.date(today, minute: 8 * 60, calendar: calendar)
        let now = CareLogic.date(today, minute: 18 * 60 + 30, calendar: calendar)
        try home.db.logCare(routineId: walk.id!, CareLogDraft(people: [home.people[1]], occurredAt: morning, durationMinutes: 25), now: now)

        let snapshot = try home.db.writer.read(CompanionSnapshot.fetch)
        let report = try #require(CompanionReport.make(snapshot: snapshot, companionId: id, now: now))
        #expect(report.primary?.slots.map(\.isDone) == [true, false])
        #expect(report.primary?.nextTurn == home.people[0], "Mia walked last, so it's James' turn")
        #expect(report.streak == 0)
        #expect(report.weekStats.count == 1)
        #expect(report.leaderboard.first?.carer == .person(home.people[1]))
        #expect(report.diary.count == 1)
        #expect(report.diary.first?.caption != nil)
        #expect(report.milestones.contains { $0.id == "longest" && $0.title == "Longest walk: 25 min" })
        #expect(report.mood != nil)

        let items = CompanionTimeline.items(snapshot: snapshot, day: today, now: now)
        let log = try #require(items.first { $0.kind == .log && $0.title.hasPrefix("Mia walked") })
        #expect(log.title == "Mia walked Yo-Yo · 25 min")
        let expected = items.filter { $0.kind == .expected }
        #expect(expected.contains { $0.title == "Evening walk" && ($0.subtitle ?? "").contains("James' turn") })
    }
}
