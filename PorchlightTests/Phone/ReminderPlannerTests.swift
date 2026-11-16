import Foundation
import Testing
@testable import Porchlight

/// The reminder planner: only what this person chose, never for something done or
/// handed off, nothing for someone who was removed, at most 64 and the nearest first.
@Suite("Reminder planner")
struct ReminderPlannerTests {
    private typealias F = CareFixture

    private static let household = Household(
        id: 100, name: "Home", timeZoneIdentifier: "America/Los_Angeles", firstWeekday: 1,
        setupCompleted: true, createdAt: F.date(day: 1, 0)
    )
    private static let yoyo = Companion(
        id: 1, householdId: 100, name: "Yo-Yo", species: .dog, coat: .honey, about: "",
        captionTone: .off, sortOrder: 0, createdAt: F.date(day: 1, 0)
    )

    private func people(archivedMe: Bool = false) -> [Person] {
        [
            Person(id: F.james, householdId: 100, name: "James", color: .blue, sortOrder: 0, createdAt: F.date(day: 1, 0), archivedAt: archivedMe ? F.date(day: 5, 0) : nil),
            Person(id: F.mia, householdId: 100, name: "Mia", color: .coral, sortOrder: 1, createdAt: F.date(day: 1, 0)),
        ]
    }

    private func snapshot(_ entries: [CareEntry] = [], archivedMe: Bool = false) -> CompanionSnapshot {
        let everyone = people(archivedMe: archivedMe)
        return CompanionSnapshot(
            household: Self.household, people: everyone.active, everyone: everyone,
            companions: [Self.yoyo], routines: [F.walk], entries: entries
        )
    }

    /// The evening walk (slot 1) on, when it opens.
    private var evening: ReminderChoices {
        var choices = ReminderChoices()
        choices.chores = false
        choices.care[ReminderChoices.slotKey(F.walk.id, slot: 1)] = .opens
        return choices
    }

    private func plan(_ snapshot: CompanionSnapshot, choices: ReminderChoices, now: Date = F.date(14, 0), chores: [Chore] = [], completions: [ChoreCompletion] = [], me: Person.ID? = F.james, limit: Int = ReminderPlanner.limit) -> [PlannedReminder] {
        ReminderPlanner.plan(companions: snapshot, chores: chores, completions: completions, me: me, choices: choices, now: now, limit: limit)
    }

    @Test("A chosen slot reminds when its window opens, each day ahead; others never")
    func chosenSlot() {
        let reminders = plan(snapshot(), choices: evening)
        #expect(reminders.count == ReminderPlanner.horizonDays)
        #expect(reminders.first?.fireDate == F.date(17, 0))
        #expect(reminders.first?.title == "Yo-Yo's evening walk")
        #expect(reminders.first?.body == "Open until 8pm. Nobody has logged it yet.")
        #expect(reminders.first?.logTitle == "I walked Yo-Yo")
        #expect(reminders.allSatisfy { if case let .care(_, slot, _) = $0.kind { slot == 1 } else { false } })
        #expect(plan(snapshot(), choices: ReminderChoices(chores: false)).isEmpty, "Nothing is on until chosen")
    }

    @Test("A slot already logged, here or on another device, has no reminder")
    func doneSlot() {
        let logged = snapshot([F.entry(1, 16, 50, by: [F.mia])])
        let reminders = plan(logged, choices: evening, now: F.date(16, 55))
        #expect(!reminders.contains { $0.fireDate == F.date(17, 0) }, "Mia walked early, so today's reminder is gone")
        #expect(reminders.first?.fireDate == F.date(day: 8, 17, 0), "Tomorrow's stays")
        let settled = ReminderPlanner.settledIDs(companions: logged, now: F.date(16, 55))
        #expect(settled.contains(PlannedReminder.prefix + "care." + ReminderChoices.dayKey(F.walk.id, slot: 1, day: F.key(7))))
    }

    @Test("If missed, it reminds when the window closes; a past time is never scheduled")
    func missed() {
        var choices = evening
        choices.care[ReminderChoices.slotKey(F.walk.id, slot: 1)] = .missed
        let reminders = plan(snapshot(), choices: choices, now: F.date(18, 0))
        #expect(reminders.first?.fireDate == F.date(20, 0))
        #expect(reminders.first?.body == "Nobody logged it before 8pm.")
        #expect(plan(snapshot(), choices: evening, now: F.date(18, 0)).first?.fireDate == F.date(day: 8, 17, 0), "Today's window already opened")
    }

    @Test("Snoozing moves today's reminder; handing it off removes it")
    func snoozeAndHandOff() {
        let today = ReminderChoices.dayKey(F.walk.id, slot: 1, day: F.key(7))
        var snoozed = evening
        snoozed.snoozes[today] = F.date(18, 15)
        #expect(plan(snapshot(), choices: snoozed, now: F.date(17, 15)).first?.fireDate == F.date(18, 15))
        var handedOff = evening
        handedOff.handedOff.insert(today)
        #expect(plan(snapshot(), choices: handedOff).first?.fireDate == F.date(day: 8, 17, 0))
    }

    @Test("Someone removed from the household, or a phone that isn't anyone's, gets nothing")
    func archived() {
        #expect(plan(snapshot(archivedMe: true), choices: evening).isEmpty)
        #expect(plan(snapshot(), choices: evening, me: nil).isEmpty)
    }

    @Test("My chores remind the evening before, but not daily ones, others' or done ones")
    func chores() {
        func chore(_ id: Chore.ID, _ title: String, owner: Person.ID?, _ recurrence: Recurrence, anchor: String = "2026-11-01") -> Chore {
            var chore = Chore(
                id: id, householdId: 100, title: title, ownerId: owner, repeatKind: "daily", weekdayMask: 0, intervalDays: 1,
                anchorDay: anchor, stars: 2, archived: false, sortOrder: 0, createdAt: F.date(day: 1, 0)
            )
            chore.recurrence = recurrence
            return chore
        }
        let list = [
            chore(1, "Breakfast", owner: F.james, .daily),
            chore(2, "Recycling", owner: F.james, .weekdays([2])),   // Mondays: Nov 9
            chore(3, "Faucet", owner: F.james, .once, anchor: "2026-11-08"),
            chore(4, "Dishes", owner: F.mia, .weekdays([2])),
        ]
        var choices = ReminderChoices()
        let reminders = plan(snapshot(), choices: choices, chores: list)
        #expect(reminders.map(\.title) == ["Tomorrow: Faucet", "Tomorrow: Recycling"])
        #expect(reminders.first?.fireDate == F.date(19, 0))
        let done = ChoreCompletion(choreId: 3, day: F.key(7), personId: F.james, stars: 2, completedAt: F.date(10, 0))
        #expect(plan(snapshot(), choices: choices, chores: list, completions: [done]).map(\.title) == ["Tomorrow: Recycling"], "Done early")
        choices.chores = false
        #expect(plan(snapshot(), choices: choices, chores: list).isEmpty)
    }

    @Test("At most 64, the nearest first")
    func cap() {
        var choices = ReminderChoices(chores: false)
        let routines = (0..<12).map { index in
            CareRoutine(
                id: .number(500 + index), companionId: 1, kind: .feed, title: "Feed \(index)", emoji: "🥣", everyDays: 1,
                windows: [.hours("Breakfast", 6, 9), .hours("Dinner", 17, 19)], trackedFields: [], stars: 1, nudgeAfterMinutes: nil, sortOrder: index
            )
        }
        for routine in routines {
            choices.care[ReminderChoices.slotKey(routine.id, slot: 0)] = .opens
            choices.care[ReminderChoices.slotKey(routine.id, slot: 1)] = .opens
        }
        let everyone = people()
        let many = CompanionSnapshot(household: Self.household, people: everyone, everyone: everyone, companions: [Self.yoyo], routines: routines, entries: [])
        let reminders = plan(many, choices: choices)
        #expect(reminders.count == 64, "12 routines x 2 slots x 7 days would be 168")
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
        #expect(reminders.first?.fireDate == F.date(17, 0))
        #expect(reminders.last?.fireDate == F.date(day: 10, 6, 0), "Today's 12 dinners, two whole days, then 4 breakfasts")
        #expect(Set(reminders.map(\.id)).count == 64, "Ids are unique and stable")
    }

    @Test("A walk that arrives from another device, written straight into the tables, takes its reminder away")
    func remoteLog() async throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(
            name: "Home", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)],
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        let people = try db.snapshot().people
        var yoyo = CompanionDraft.new(species: .dog)
        yoyo.name = "Yo-Yo"
        let companionId = try db.saveCompanion(yoyo, householdId: household.id, now: F.date(day: 1, 0))
        let walk = try #require(try await db.writer.read(CompanionSnapshot.fetch).routines(of: companionId).first { $0.kind == .walk })
        var choices = ReminderChoices(chores: false)
        choices.care[ReminderChoices.slotKey(walk.id, slot: 1)] = .opens
        let now = F.date(16, 30)
        func plan() async throws -> [PlannedReminder] {
            ReminderPlanner.plan(companions: try await db.writer.read(CompanionSnapshot.fetch), chores: [], completions: [], me: people[0].id, choices: choices, now: now)
        }
        let todays = PlannedReminder.prefix + "care." + ReminderChoices.dayKey(walk.id, slot: 1, day: F.key(7))
        #expect(try await plan().contains { $0.id == todays })

        // As the sync engine writes Mia's walk: plain inserts, no app write path.
        let log = CareLog.ID.new()
        try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO careLog (id, careRoutineId, occurredAt, stars, createdAt) VALUES (?, ?, ?, 2, ?)
                """, arguments: [log, walk.id, F.date(16, 10), F.date(16, 10)])
            try db.execute(sql: "INSERT INTO careLogPerson (id, careLogId, personId) VALUES (?, ?, ?)",
                           arguments: [CareLogPerson.id(careLogId: log, personId: people[1].id), log, people[1].id])
        }
        #expect(try await !plan().contains { $0.id == todays }, "Mia already walked Yo-Yo this evening")
    }

    @Test("Choices keep only today's and later snoozes and hand-offs")
    func prune() {
        var choices = ReminderChoices()
        choices.snoozes[ReminderChoices.dayKey(F.walk.id, slot: 1, day: F.key(6))] = F.date(day: 6, 18)
        choices.snoozes[ReminderChoices.dayKey(F.walk.id, slot: 1, day: F.key(7))] = F.date(18)
        choices.handedOff = [ReminderChoices.dayKey(F.walk.id, slot: 0, day: F.key(5))]
        choices.prune(before: F.key(7))
        #expect(choices.snoozes.count == 1)
        #expect(choices.handedOff.isEmpty)
    }
}
