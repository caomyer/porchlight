import CloudKit
import Foundation
import GRDB
import Testing
@testable import Porchlight
@testable import SQLiteData

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

        // A walk logged, then its own save dropped from what the engine will send, as when
        // it was lost: who walked goes to iCloud without it.
        let routine = try #require(try await harness.database.writer.read { db in try CareRoutine.fetchOne(db) })
        let people = try harness.database.snapshot().people.map(\.id)
        let log = try harness.database.logCare(routineId: routine.id, CareLogDraft(people: people, occurredAt: CompanionClock.now()))
        let walk = CKRecord.ID(recordName: SyncMirror.CareLog.recordName(for: log.id.uuid), zoneID: SyncMirror.householdZone.zoneID)
        let state = engine.private.state
        for _ in 0..<100 where !state.pendingRecordZoneChanges.contains(.saveRecord(walk)) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(state.pendingRecordZoneChanges.contains(.saveRecord(walk)), "the walk was queued: \(state.pendingRecordZoneChanges)")
        state.remove(pendingRecordZoneChanges: [.saveRecord(walk)])

        // iCloud refuses who walked, as its walk isn't there: it stays here.
        try await engine.sendChanges()
        #expect(try walkers(of: log.id, in: harness) == people.count)
        // The engine tells the app from its own task; the count lands on the main actor.
        for _ in 0..<100 where controller.trace.deferrals.held < people.count {
            try await Task.sleep(for: .milliseconds(20))
        }
        let deferrals = controller.trace.deferrals
        #expect(deferrals.held == people.count, "\(deferrals)")
        let line = deferrals.heldLine()
        #expect(line.hasPrefix("Held \(people.count) records until their parent arrived. Last: who walked or fed, "), "got \(line)")

        // The next change sends the walk, then who walked, and every row reaches iCloud.
        try await harness.database.writer.write { db in
            try db.execute(sql: "UPDATE household SET name = 'Lake House'")
        }
        try await engine.sendChanges()
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
        calendar.locale = Locale(identifier: "en_US")
        let at = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 18, minute: 41)))

        var deferrals = SyncDeferrals(defaults: defaults)
        #expect(deferrals.heldLine(calendar: calendar) == "none")
        #expect(deferrals.resentLine(calendar: calendar) == "none")
        deferrals.note(recordType: "careLog", waitingForParent: true, at: at)
        deferrals.note(recordType: "journalEntryEater", waitingForParent: true, at: at)
        deferrals.note(recordType: "careLogPerson", waitingForParent: true, at: at)
        deferrals.note(recordType: "careLog", waitingForParent: false, at: at)
        deferrals.save(to: defaults)

        let reopened = SyncDeferrals(defaults: defaults)
        #expect(reopened == deferrals)
        let held = reopened.heldLine(calendar: calendar).replacingOccurrences(of: "\u{202F}", with: " ")
        #expect(held == "Held 3 records until their parent arrived. Last: who walked or fed, Nov 23 at 6:41 PM.", "got \(held)")
        let resent = reopened.resentLine(calendar: calendar).replacingOccurrences(of: "\u{202F}", with: " ")
        #expect(resent == "Sent again 1 record iCloud turned down. Last: a walk or meal, Nov 23 at 6:41 PM.", "got \(resent)")
        #expect(SyncDeferrals.words("somethingNew") == "a change")
    }

    private func walkers(of log: CareLog.ID, in harness: SyncHarness) throws -> Int {
        try harness.database.writer.read { db in
            try CareLogPerson.filter(Column("careLogId") == log).fetchCount(db)
        }
    }
}
