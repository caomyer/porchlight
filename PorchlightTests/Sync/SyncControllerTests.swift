import CloudKit
import Foundation
import SQLiteData
import Testing
@testable import Porchlight

@Suite("Sync engine")
@MainActor
struct SyncEngineTests {
    @Test("The engine accepts the app's real schema")
    func acceptsSchema() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        #expect(controller.engine != nil)
        #expect(controller.status == .upToDate(lastSynced: nil))
    }

    @Test("Rows written before the engine first starts are all uploaded once the owner turns sync on")
    func uploadsExistingRows() async throws {
        let harness = try SyncHarness()
        try harness.fill()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)

        // A wall that already has a household starts with sync off: nothing is sent.
        #expect(controller.status == .off(.switchedOff))
        #expect(!engine.isRunning)
        #expect(try harness.knownRows() == 0)

        controller.setEnabled(true)
        await controller.settle()
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])
        #expect(try harness.knownRows() == harness.counts().values.reduce(0, +))
    }

    @Test("Every row the app writes while sync runs reaches iCloud, with none left pending")
    func uploadsNewRows() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        #expect(engine.isRunning)

        try harness.fill()
        let counts = try harness.counts()
        #expect(counts.values.allSatisfy { $0 > 0 }, "the fill writes every synced table: \(counts)")
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])
        #expect(try harness.knownRows() == counts.values.reduce(0, +))
    }

    @Test("Rows a data migration writes once sync has been on are recorded for upload")
    func dataMigrationsAreRecorded() async throws {
        let harness = try SyncHarness()
        try harness.fill()
        harness.preferences.isEnabled = true
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])

        // Paused, so the change waits in the engine's queue where the test can see it.
        controller.setEnabled(false)
        await controller.settle()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("test: rename the household") { db in
            try db.execute(sql: "UPDATE household SET name = 'Lake House'")
        }
        try harness.database.migrateData(migrator)
        let queued = try await harness.database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlitedata_icloud_pendingRecordZoneChanges")
        }
        #expect(queued == 1, "the engine recorded the migration's write")

        controller.setEnabled(true)
        await controller.settle()
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])
    }

    @Test("The household can be shared")
    func sharesHousehold() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try harness.fill()
        try await engine.syncChanges()

        let household = try #require(try await harness.database.writer.read { db in
            try SyncMirror.Household.all.fetchOne(db)
        })
        let shared = try await engine.share(record: household) { share in
            share[CKShare.SystemFieldKey.title] = "The Lake House"
        }
        #expect(shared.share[CKShare.SystemFieldKey.title] as? String == "The Lake House")
    }
}

@Suite("Sync switch")
@MainActor
struct SyncSwitchTests {
    @Test("A new install starts with sync on")
    func newInstall() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        #expect(controller.isEnabled)
        #expect(harness.preferences.isEnabled == true)
    }

    @Test("A device that already has a household starts with sync off, and keeps it off")
    func existingHousehold() async throws {
        let harness = try SyncHarness()
        try harness.fill()
        #expect(await !harness.controller().isEnabled)
        #expect(harness.preferences.isEnabled == false)
        // Once decided, the switch is the owner's: a later launch keeps it.
        harness.preferences.isEnabled = true
        #expect(await harness.controller().isEnabled)
    }

    @Test("The switch's first state is decided only when sync can run")
    func undecidedWithoutEngine() throws {
        let preferences = SyncPreferences(defaults: UserDefaults(suiteName: "sync-tests-\(UUID().uuidString)")!)
        for reason in [SyncOffReason.sampleData, .noEntitlement] {
            let controller = SyncController(.unavailable(reason), preferences: preferences, hasHousehold: true, removeFiles: {})
            #expect(controller.status == .off(reason))
            #expect(controller.engine == nil)
            #expect(!controller.isAvailable)
        }
        #expect(preferences.isEnabled == nil)
    }

    @Test("Switching off stops the engine; writes still save and go once it is back on")
    func switchOffAndOn() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)

        controller.setEnabled(false)
        await controller.settle()
        #expect(!engine.isRunning)
        #expect(controller.status == .off(.switchedOff))
        try harness.fill()

        controller.setEnabled(true)
        await controller.settle()
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])
    }
}

@Suite("Sync account changes")
@MainActor
struct SyncAccountTests {
    /// A wall with a household, syncing with the owner's account.
    private func syncingWall() async throws -> (SyncHarness, SyncController, SyncEngine) {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try harness.fill()
        try await engine.syncChanges()
        return (harness, controller, engine)
    }

    @Test("Signing out pauses sync and keeps every row")
    func signOut() async throws {
        let (harness, controller, engine) = try await syncingWall()
        let counts = try harness.counts()

        await harness.device.signOut()
        controller.accountChanged(.ownerSignedOut)
        await controller.settle()
        #expect(controller.status == .noAccount)
        #expect(!engine.isRunning)
        #expect(try harness.counts() == counts)

        // The wall keeps working on its own.
        try harness.database.renameHousehold(id: #require(harness.database.snapshot().household).id, to: "Lake House")
    }

    @Test("Signing back in to the same account resumes and sends what queued up")
    func signBackIn() async throws {
        let (harness, controller, engine) = try await syncingWall()
        await harness.device.signOut()
        controller.accountChanged(.ownerSignedOut)
        let household = try #require(harness.database.snapshot().household)
        try harness.database.renameHousehold(id: household.id, to: "Lake House")

        await harness.device.signIn(as: "owner")
        try await eventually { engine.isRunning }
        await controller.settle()
        #expect(controller.status == .upToDate(lastSynced: nil))
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])
    }

    @Test("A different account waits for the owner's choice, and nothing is sent to it")
    func switchAccounts() async throws {
        let (harness, controller, engine) = try await syncingWall()
        let counts = try harness.counts()

        await harness.device.signIn(as: "someone else")
        controller.accountChanged(.switched)
        await controller.settle()
        #expect(controller.status == .needsDecision)
        #expect(!engine.isRunning)
        #expect(try harness.counts() == counts)

        // The choice is remembered: the next launch doesn't sync either.
        let relaunched = await harness.controller()
        #expect(relaunched.status == .needsDecision)
        #expect(relaunched.engine?.isRunning == false)
    }

    @Test("A different account at launch is noticed before anything is sent")
    func switchedWhileClosed() async throws {
        let (harness, _, _) = try await syncingWall()
        await harness.device.signIn(as: "someone else")
        let relaunched = await harness.controller()
        #expect(relaunched.status == .needsDecision)
        #expect(relaunched.engine?.isRunning == false)
    }

    @Test("Keeping the data without sync keeps every row and keeps asking while the other account is signed in")
    func keepWithoutSync() async throws {
        let (harness, controller, engine) = try await syncingWall()
        let counts = try harness.counts()
        await harness.device.signIn(as: "someone else")
        controller.accountChanged(.switched)

        controller.keepDataWithoutSync()
        await controller.settle()
        #expect(controller.status == .off(.switchedOff))
        #expect(!engine.isRunning)
        #expect(try harness.counts() == counts)

        controller.setEnabled(true)
        await controller.settle()
        #expect(controller.status == .needsDecision)
        #expect(!engine.isRunning)
    }

    @Test("Removing the data clears this device and syncs with the new account")
    func removeFromDevice() async throws {
        let (harness, controller, engine) = try await syncingWall()
        await harness.device.signIn(as: "someone else")
        controller.accountChanged(.switched)

        await controller.removeDataFromDevice()
        await controller.settle()
        #expect(try harness.counts().values.allSatisfy { $0 == 0 })
        #expect(harness.removedFiles == 1)
        #expect(engine.isRunning)
        #expect(controller.isEnabled)
        #expect(controller.status == .upToDate(lastSynced: nil))
        #expect(harness.preferences.accountName == "someone else")
    }

    @Test("No iCloud account at launch: sync waits, the data stays")
    func noAccount() async throws {
        let harness = try SyncHarness()
        try harness.fill()
        harness.preferences.isEnabled = true
        await harness.device.signOut()
        let controller = await harness.controller()
        #expect(controller.status == .noAccount)
        #expect(controller.engine?.isRunning == false)
    }

    @Test("A full iCloud pauses sync until there is room; changes keep saving")
    func iCloudFull() async throws {
        let (harness, controller, _) = try await syncingWall()
        controller.quotaChanged(isExceeded: true)
        #expect(controller.status == .iCloudFull)
        try harness.database.renameHousehold(id: #require(harness.database.snapshot().household).id, to: "Lake House")
        controller.quotaChanged(isExceeded: false)
        #expect(controller.status == .upToDate(lastSynced: nil))
    }
}

@Suite("Sync status")
@MainActor
struct SyncStatusTests {
    @Test("A round of syncing that ends online is the last-synced time, kept on the device")
    func lastSynced() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let noon = Date(timeIntervalSince1970: 1_800_000_000)

        controller.activityChanged(isSynchronizing: true)
        #expect(controller.status == .syncing)
        controller.activityChanged(isSynchronizing: false, at: noon)
        #expect(controller.status == .upToDate(lastSynced: noon))
        #expect(harness.preferences.lastSynced == noon)
        #expect(await harness.controller().lastSynced == noon)
    }

    @Test("Offline, sync is waiting and keeps the last time it reached iCloud")
    func offline() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let noon = Date(timeIntervalSince1970: 1_800_000_000)
        controller.activityChanged(isSynchronizing: true)
        controller.activityChanged(isSynchronizing: false, at: noon)

        controller.networkChanged(isOnline: false)
        controller.activityChanged(isSynchronizing: true)
        controller.activityChanged(isSynchronizing: false, at: noon.addingTimeInterval(60))
        #expect(controller.status == .waiting(lastSynced: noon))
        controller.networkChanged(isOnline: true)
        #expect(controller.status == .upToDate(lastSynced: noon))
    }
}

/// Waits up to two seconds for something the controller does on its own.
@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}
