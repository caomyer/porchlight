import Foundation
import GRDB
import Testing
@testable import Porchlight

/// A database replaced underneath the app (a restored backup) never syncs on its own
/// (docs/design/sync-icloud.md, "Backups and restore").
@Suite("A restored database")
@MainActor
struct RestoreTests {
    private typealias Evidence = DatabaseIdentity.Evidence

    @Test("Tokens that disagree, or a lost metadata database after syncing, mean the database was replaced")
    func evidence() {
        let same = Evidence(databaseToken: "b", knownTokens: ["b"], metadataExisted: true, hasSynced: true, hasHousehold: true)
        #expect(!DatabaseIdentity.isReplaced(same))
        #expect(!DatabaseIdentity.isReplaced(Evidence(databaseToken: "a", knownTokens: ["a", "b"], metadataExisted: true, hasSynced: true, hasHousehold: true)),
                "a launch that crashed while rotating")
        #expect(DatabaseIdentity.isReplaced(Evidence(databaseToken: "a", knownTokens: ["b"], metadataExisted: true, hasSynced: true, hasHousehold: true)),
                "an older backup")
        #expect(DatabaseIdentity.isReplaced(Evidence(databaseToken: nil, knownTokens: ["b"], metadataExisted: true, hasSynced: false, hasHousehold: true)),
                "a backup from before tokens")
        #expect(!DatabaseIdentity.isReplaced(Evidence(databaseToken: "a", knownTokens: [], metadataExisted: true, hasSynced: false, hasHousehold: true)),
                "a data folder copied into a fresh install, which starts with sync off")
        #expect(DatabaseIdentity.isReplaced(Evidence(databaseToken: "b", knownTokens: ["b"], metadataExisted: false, hasSynced: true, hasHousehold: true)),
                "the engine's metadata is gone, so every row would look new")
        #expect(!DatabaseIdentity.isReplaced(Evidence(databaseToken: nil, knownTokens: [], metadataExisted: false, hasSynced: false, hasHousehold: true)),
                "the first launch of an install")
        #expect(!DatabaseIdentity.isReplaced(Evidence(databaseToken: "a", knownTokens: ["b"], metadataExisted: false, hasSynced: true, hasHousehold: false)),
                "nothing to send")
    }

    /// Opens the data folder as a launch does, and checks it.
    private func launch(_ folder: URL, preferences: SyncPreferences) throws -> AppDatabase {
        let metadataExisted = FileManager.default.fileExists(atPath: DatabaseIdentity.metadataURL(in: folder).path)
        let database = try AppDatabase.openOnDisk(folder: folder)
        try DatabaseIdentity.check(database, metadataExisted: metadataExisted, preferences: preferences)
        return database
    }

    @Test("Putting back a backup of the data folder is noticed at the next launch; ordinary launches aren't")
    func restoredBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Porchlight")
        let backup = root.appendingPathComponent("Backup")
        let suite = "restore-\(UUID().uuidString)"
        let preferences = SyncPreferences(defaults: UserDefaults(suiteName: suite)!)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        var database = try launch(folder, preferences: preferences)
        try database.createHousehold(name: "The Lake House", people: [PersonDraft(name: "James", color: .blue)])
        try database.writer.close()
        database = try launch(folder, preferences: preferences)
        #expect(preferences.restoredCopy == nil, "a relaunch is the same database")
        try database.writer.close()
        try FileManager.default.copyItem(at: folder, to: backup)

        database = try launch(folder, preferences: preferences)
        try database.writer.close()
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.copyItem(at: backup, to: folder)
        database = try launch(folder, preferences: preferences)
        #expect(preferences.restoredCopy == .undecided)
        try database.writer.close()
    }

    // MARK: The decision

    @Test("A restored copy keeps sync off and waits for a choice, across relaunches, before anything is sent")
    func waitsForChoice() async throws {
        let harness = try SyncHarness()
        try harness.fill()
        harness.preferences.isEnabled = true
        harness.preferences.restoredCopy = .undecided
        let controller = await harness.controller()
        #expect(controller.status == .needsDecision(.restoredCopy))
        #expect(controller.engine?.isRunning == false)
        #expect(try harness.knownRows() == 0, "nothing was sent")
        #expect(await harness.controller().status == .needsDecision(.restoredCopy))
    }

    @Test("Keeping the copy without sync keeps every row and asks again when sync is turned on")
    func keepCopy() async throws {
        let harness = try SyncHarness()
        try harness.fill()
        let counts = try harness.counts()
        harness.preferences.isEnabled = true
        harness.preferences.restoredCopy = .undecided
        let controller = await harness.controller()
        controller.keepRestoredCopyWithoutSync()
        await controller.settle()
        #expect(controller.status == .off(.switchedOff))
        #expect(try harness.counts() == counts)
        controller.setEnabled(true)
        await controller.settle()
        #expect(controller.status == .needsDecision(.restoredCopy))
        #expect(controller.engine?.isRunning == false)
    }

    @Test("Using what is in iCloud drops this copy, starts sync and looks for the household")
    func useICloud() async throws {
        let harness = try SyncHarness()
        try harness.fill()
        harness.preferences.isEnabled = true
        harness.preferences.restoredCopy = .undecided
        let controller = await harness.controller()
        await controller.useCopyInICloud()
        await controller.settle()
        #expect(harness.preferences.restoredCopy == nil)
        #expect(controller.decision == nil)
        #expect(controller.isLookingForHousehold)
        #expect(try harness.counts().values.allSatisfy { $0 == 0 }, "the copy is gone, never sent")
        #expect(harness.removedFiles == 1)
        controller.stopLookingForHousehold()
    }
}
