import Foundation
import GRDB
import Testing
@testable import Porchlight

/// A record iCloud refuses is kept and sent again, never lost, and Sync details says so in
/// words a person can read aloud (docs/design/sync-icloud.md, "A record sent before its
/// parent").
@MainActor
@Suite("Records held and sent again", .serialized)
struct SyncDeferralsTests {
    @Test("Who walked reaches iCloud after its walk, rather than being deleted when it arrives first")
    func whoWalkedWaitsForItsWalk() async throws {
        let harness = try SyncHarness()
        try harness.fill()
        harness.preferences.isEnabled = true
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])

        // A walk logged while paused, then only who walked queued for iCloud: the walk itself
        // is on this device and has never been sent, as when its own save was lost.
        controller.setEnabled(false)
        await controller.settle()
        let routine = try #require(try await harness.database.writer.read { db in try CareRoutine.fetchOne(db) })
        let people = try harness.database.snapshot().people.map(\.id)
        let log = try harness.database.logCare(routineId: routine.id, CareLogDraft(people: people, occurredAt: CompanionClock.now()))
        try await harness.database.writer.write { db in
            try db.execute(sql: "DELETE FROM sqlitedata_icloud_pendingRecordZoneChanges")
            for row in try CareLogPerson.filter(Column("careLogId") == log.id).fetchAll(db) {
                try row.update(db)
            }
        }
        controller.setEnabled(true)
        await controller.settle()

        // iCloud refuses who walked, as its walk isn't there: it stays here.
        try await engine.syncChanges()
        #expect(try walkers(of: log.id, in: harness) == people.count)
        await controller.settle()
        #expect(controller.trace.deferrals.held == people.count)
        #expect(controller.trace.deferrals.heldLine().hasPrefix("Held \(people.count) records until their parent arrived. Last: who walked or fed, "))

        // The next change sends the walk, then who walked, and every row reaches iCloud.
        try await harness.database.writer.write { db in
            try db.execute(sql: "UPDATE household SET name = 'Lake House'")
        }
        try await engine.syncChanges()
        #expect(try walkers(of: log.id, in: harness) == people.count)
        #expect(try harness.unsynced() == [])
    }

    @Test("The lines say how many and the last one, in words, and are kept across launches")
    func linesInWords() throws {
        let suite = "sync-deferrals-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let at = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 18, minute: 41)))

        var deferrals = SyncDeferrals(defaults: defaults)
        #expect(deferrals.heldLine(calendar: calendar) == "None")
        #expect(deferrals.resentLine(calendar: calendar) == "None")
        deferrals.note(recordType: "careLog", waitingForParent: true, at: at)
        deferrals.note(recordType: "journalEntryEater", waitingForParent: true, at: at)
        deferrals.note(recordType: "careLogPerson", waitingForParent: true, at: at)
        deferrals.note(recordType: "careLog", waitingForParent: false, at: at)
        deferrals.save(to: defaults)

        let reopened = SyncDeferrals(defaults: defaults)
        #expect(reopened == deferrals)
        #expect(reopened.heldLine(calendar: calendar).replacingOccurrences(of: "\u{202F}", with: " ")
            == "Held 3 records until their parent arrived. Last: who walked or fed, Nov 23, 6:41 PM.")
        #expect(reopened.resentLine(calendar: calendar).replacingOccurrences(of: "\u{202F}", with: " ")
            == "Sent again 1 record iCloud turned down. Last: a walk or meal, Nov 23, 6:41 PM.")
        #expect(SyncDeferrals.words("somethingNew") == "a change")
    }

    private func walkers(of log: CareLog.ID, in harness: SyncHarness) throws -> Int {
        try harness.database.writer.read { db in
            try CareLogPerson.filter(Column("careLogId") == log).fetchCount(db)
        }
    }
}
