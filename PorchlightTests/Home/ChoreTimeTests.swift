import CloudKit
import Foundation
import GRDB
import Testing
@testable import Porchlight

/// A chore's time (docs/design/phone-shell.md, "A chore's time"): what its line says, the order on
/// the board, when the line turns the accent color, the editor's save, the migration and
/// the field it carries to iCloud.
@Suite("Chores: a chore's time")
struct ChoreTimeTests {
    private var calendar: Calendar { HomeLogicTests.calendar }
    private let today = DayKey(rawValue: "2026-11-04")
    private let clock = ClockStyle(uses24Hours: false)

    private func chore(_ id: Int, time: Int? = nil, hint: String? = nil, _ recurrence: Recurrence = .daily, anchor: String = "2026-11-01") -> Chore {
        var chore = HomeLogicTests.chore(id: id, recurrence, anchor: anchor)
        chore.timeOfDay = time
        chore.timeHint = hint
        return chore
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: hour * 60 + minute, to: today.startDate(in: calendar))!
    }

    @Test("The line under a chore: its time, else an old typed hint, else when it is due")
    func subtitlePrecedence() {
        #expect(ChoreSchedule.subtitle(for: chore(1, time: 19 * 60, hint: "after dinner"), today: today, calendar: calendar, clock: clock) == "7:00 PM")
        #expect(ChoreSchedule.subtitle(for: chore(1, hint: "after dinner"), today: today, calendar: calendar, clock: clock) == "after dinner")
        #expect(ChoreSchedule.subtitle(for: chore(1), today: today, calendar: calendar, clock: clock) == "every day")
        #expect(ChoreSchedule.subtitle(for: chore(1, time: 7 * 60), today: today, calendar: calendar, clock: ClockStyle(uses24Hours: true)) == "07:00")
        #expect(ChoreSchedule.subtitle(for: chore(1, hint: ""), today: today, calendar: calendar, clock: clock) == "every day", "an empty hint is no hint")
    }

    @Test("On the board, open chores with a time come first by time, then the rest in today's order; done ones stay where they were")
    func order() {
        let chores = [chore(1), chore(2, time: 19 * 60), chore(3), chore(4, time: 7 * 60), chore(5, time: 12 * 60), chore(6, time: 7 * 60)]
        let board = ChoreBoard(
            people: [Person(id: .number(1), householdId: 1, name: "A", color: .blue, sortOrder: 1, createdAt: .now)],
            chores: chores, completions: [HomeLogicTests.done(5, today.rawValue, by: 1)], earnings: [], rewards: [],
            today: today, calendar: calendar
        )
        let ids = board.columns[0].tasks.map(\.chore.id)
        #expect(ids == [4, 6, 2, 1, 3, 5].map { Chore.ID.number($0) }, "7:00, 7:00 (as listed), 7:00 PM, then 1, 3 and the done noon one in their own order")
    }

    @Test("A time's line turns the accent color once the time has come today and the chore is open; an overdue one-off as before")
    func late() {
        let bins = chore(1, time: 19 * 60)
        #expect(!ChoreSchedule.isLate(bins, isDone: false, today: today, now: at(18, 59), calendar: calendar))
        #expect(ChoreSchedule.isLate(bins, isDone: false, today: today, now: at(19), calendar: calendar))
        #expect(ChoreSchedule.isLate(bins, isDone: false, today: today, now: at(23, 30), calendar: calendar))
        #expect(!ChoreSchedule.isLate(bins, isDone: true, today: today, now: at(23, 30), calendar: calendar), "done is done")
        #expect(!ChoreSchedule.isLate(chore(2), isDone: false, today: today, now: at(23, 30), calendar: calendar), "any time is never late")
        let overdue = chore(3, .once, anchor: "2026-11-02")
        #expect(ChoreSchedule.isLate(overdue, isDone: false, today: today, now: at(6), calendar: calendar), "an overdue one-off, as now")
        let dueToday = chore(4, time: 9 * 60, .once, anchor: today.rawValue)
        #expect(!ChoreSchedule.isLate(dueToday, isDone: false, today: today, now: at(8), calendar: calendar))
        #expect(ChoreSchedule.isLate(dueToday, isDone: false, today: today, now: at(9), calendar: calendar), "a one-off due today, once its time has come")
    }

    @Test("Saving a time keeps it; clearing it goes back to any time; an old hint is never wiped by the editor's save")
    func saving() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "A", color: .blue)])
        let person = try #require(try db.snapshot().people.first).id
        var draft = ChoreDraft(title: "Bins", ownerId: person, anchorDay: today, timeHint: "after dinner", stars: 2)
        let saved = try db.saveChore(draft, householdId: household.id)
        #expect(saved.timeOfDay == nil && saved.timeHint == "after dinner")
        draft.timeOfDay = 19 * 60
        let timed = try db.saveChore(draft, id: saved.id, householdId: household.id)
        #expect(timed.timeOfDay == 1140 && timed.timeHint == "after dinner", "the hint stays stored; the time shows over it")
        draft.timeOfDay = nil
        let cleared = try db.saveChore(draft, id: saved.id, householdId: household.id)
        #expect(cleared.timeOfDay == nil && cleared.timeHint == "after dinner", "cleared: the old hint shows again")
        draft.timeOfDay = TimeEntry.day
        #expect(throws: HomeValidationError.invalidTime) { try db.saveChore(draft, id: saved.id, householdId: household.id) }
    }

    @Test("Chores from before times have none after the migration, and keep their hints")
    func migration() throws {
        let queue = try DatabaseQueue(configuration: AppDatabase.configuration)
        try AppDatabase.migrator(files: nil).migrate(queue, upTo: AppDatabase.characterMigration)
        let household = UUID().uuidString.lowercased(), chore = UUID().uuidString.lowercased()
        try queue.write { db in
            #expect(try !db.columns(in: "chore").map(\.name).contains("timeOfDay"))
            try db.execute(sql: """
                INSERT INTO household (id, name, timeZoneIdentifier, firstWeekday, createdAt) VALUES (?, 'Home', 'UTC', 1, '2026-01-01 00:00:00.000');
                INSERT INTO chore (id, householdId, title, repeatKind, weekdayMask, intervalDays, anchorDay, timeHint, stars, archived, sortOrder, createdAt)
                VALUES (?, ?, 'Bins', 'daily', 0, 1, '2026-01-01', 'after dinner', 2, 0, 0, '2026-01-01 00:00:00.000');
                """, arguments: [household, chore, household])
        }
        let db = try AppDatabase(queue)
        let column = try db.writer.read { db in try db.columns(in: "chore").first { $0.name == "timeOfDay" } }
        #expect(column?.type == "INTEGER" && column?.isNotNull == false)
        let stored = try #require(try db.writer.read { db in try Chore.fetchOne(db) })
        #expect(stored.timeOfDay == nil && stored.timeHint == "after dinner")
    }
}

/// The time through SQLiteData's stand-in for iCloud.
@Suite("Chores: a chore's time through iCloud")
@MainActor
struct ChoreTimeSyncTests {
    @Test("A chore's time goes up as its own field, with its modification time")
    func field() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try harness.fill()
        try await engine.syncChanges()
        let record = try await harness.database.writer.read { db -> CKRecord in
            let data = try #require(try Data.fetchOne(db, sql: """
                SELECT _lastKnownServerRecordAllFields FROM sqlitedata_icloud_metadata WHERE recordType = 'chore'
                """))
            let coder = try NSKeyedUnarchiver(forReadingFrom: data)
            coder.requiresSecureCoding = true
            return try #require(CKRecord(coder: coder))
        }
        let value = record.encryptedValues["timeOfDay"]
        #expect((value as? NSNumber)?.intValue == 19 * 60, "timeOfDay: \(String(describing: value)), fields: \(record.encryptedValues.allKeys().sorted())")
        #expect(record.encryptedValues["sqlitedata_icloud_userModificationTime_timeOfDay"] != nil)
        #expect(try harness.unsynced().isEmpty)
    }
}
