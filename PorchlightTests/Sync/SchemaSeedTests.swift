import CloudKit
import Foundation
import GRDB
import SQLiteData
import Testing
@testable import Porchlight

/// The CloudKit schema seed (docs/design/sync-icloud.md, "Deploying the CloudKit schema").
/// Real iCloud is out of reach here; SQLiteData's stand-in for it takes the seed's records
/// the way CloudKit's Development environment does, field by field.
@Suite("CloudKit schema seed")
@MainActor
struct SchemaSeedTests {
    @Test("Every column of every synced table gets a value, so CloudKit learns every field")
    func fillsEveryColumn() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { try SchemaSeed.fill($0, now: .now) }
        try database.writer.read { db in
            for table in SyncSchema.synced {
                let rows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(table.name)\"") ?? 0
                #expect(rows == 1, "\(table.name)")
                // The table itself, not the mirror: a column added to one but not the other
                // fails here and in SyncMirrorTests.
                for column in try db.columns(in: table.name) {
                    let empty = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(table.name)\" WHERE \"\(column.name)\" IS NULL") ?? 0
                    #expect(empty == 0, "\(table.name).\(column.name) has no value, so its field would be missing in Production")
                }
            }
        }
    }

    @Test("The seed knows every type a mirror column can have")
    func knowsEveryColumnType() {
        for mirror in SyncMirror.all {
            for column in SchemaSeed.columns(of: mirror) {
                #expect(column.kind != nil, "\(mirror.tableName).\(column.name)")
            }
        }
    }

    @Test("Id columns point at the seeded rows, so the engine can give each record its parent")
    func linksRows() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { try SchemaSeed.fill($0, now: .now) }
        try database.writer.read { db in
            let violations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            #expect(violations.isEmpty)
            let person = try String.fetchOne(db, sql: "SELECT id FROM person")
            let device = try String.fetchOne(db, sql: "SELECT id FROM device")
            #expect(try String.fetchOne(db, sql: "SELECT personId FROM careLogPerson") == person)
            #expect(try String.fetchOne(db, sql: "SELECT deviceId FROM careLog") == device)
        }
    }

    @Test("A run sends a record of every type with every field, shares the household, then removes it all")
    func runsEndToEnd() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("schema-seed-test-\(UUID().uuidString)", isDirectory: true)
        var deletedZones: [CKRecordZone.ID] = []
        let seeder = SchemaSeeder(folder: folder) { deletedZones.append($0) }
        await seeder.run(requireSigned: false)

        guard case let .done(report, cleanedUp) = seeder.phase else {
            Issue.record("the seed didn't finish: \(seeder.phase)")
            return
        }
        #expect(cleanedUp == nil)
        #expect(report.records == SyncMirror.all.count)
        #expect(report.shared)
        #expect(Set(report.fields.keys) == Set(SyncMirror.all.map { $0.tableName } + ["cloudkit.share"]))
        for mirror in SyncMirror.all {
            // Exactly the fields docs/design/sync-icloud.md lists: each column, SQLiteData's
            // merge time beside each, a hash beside each asset, and the record's own time.
            let columns = SchemaSeed.columns(of: mirror)
            let expected = Set(columns.map(\.name))
                .union(columns.map { "sqlitedata_icloud_userModificationTime_\($0.name)" })
                .union(columns.filter { $0.kind == .data }.map { "\($0.name)_hash" })
                .union(["sqlitedata_icloud_userModificationTime"])
            let fields = report.fields[mirror.tableName] ?? []
            #expect(fields == expected, "\(mirror.tableName): extra \(fields.subtracting(expected).sorted()), missing \(expected.subtracting(fields).sorted())")
        }
        // Photos travel as assets, with a hash beside them.
        #expect(report.fields["companionPhoto"]?.contains("image_hash") == true)
        #expect(deletedZones == [SchemaSeed.zone.zoneID])
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("A run never touches the household's own zone")
    func usesItsOwnZone() {
        #expect(SchemaSeed.zone.zoneID.zoneName != SyncMirror.householdZone.zoneID.zoneName)
    }

    @Test("Asked for only by its launch argument")
    func isOnlyRequestedByArgument() {
        #expect(!SchemaSeed.isRequested)
        #expect(SchemaSeed.argument == "-seedCloudSchema")
    }
}

@Suite("Changes iCloud turns down")
@MainActor
struct SyncUnsentTests {
    @Test("Rows iCloud never took show as not accepted, a stuck state, with nothing deleted")
    func showsNotAccepted() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try harness.fill()
        try await engine.syncChanges()
        await controller.checkUnsent()
        #expect(controller.status == .upToDate(lastSynced: controller.lastSynced))

        // As after Production refused them: rows here with no record of them in iCloud.
        try await harness.database.writer.write { db in
            try db.execute(sql: """
                UPDATE sqlitedata_icloud_metadata SET lastKnownServerRecord = NULL, _lastKnownServerRecordAllFields = NULL
                WHERE recordType = 'careLog'
                """)
        }
        await controller.checkUnsent()
        #expect(controller.status == .notAccepted(count: 1))
        #expect(controller.status.isStuck)
        #expect(controller.status.summary.contains("safe on this iPad"))
        #expect(try harness.counts()["careLog"] == 1, "nothing is deleted")
    }

    @Test("A row iCloud dropped is offered again when sync starts, and goes up")
    func resendsDroppedRows() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try harness.fill()
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])

        // A walk logged while sync was paused, then dropped from what the engine sends, the
        // way SQLiteData drops a record iCloud refused.
        controller.setEnabled(false)
        await controller.settle()
        let routine = try #require(try await harness.database.writer.read { db in try CareRoutine.fetchOne(db) })
        _ = try harness.database.logCare(routineId: routine.id, CareLogDraft(people: try harness.database.snapshot().people.map(\.id), occurredAt: CompanionClock.now()))
        try await harness.database.writer.write { db in
            try db.execute(sql: "DELETE FROM sqlitedata_icloud_pendingRecordZoneChanges")
        }
        #expect(try harness.unsynced().contains { $0.hasPrefix("careLog ") }, "the walk waits, unsent and unqueued")

        controller.setEnabled(true)
        await controller.settle()
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])
        await controller.checkUnsent()
        #expect(controller.unsentCount == 0)
        #expect(controller.status == .upToDate(lastSynced: controller.lastSynced))
    }

    @Test("Offline or syncing wins over not accepted, which only shows once sync is quiet")
    func statusOrder() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        try harness.fill()
        await controller.checkUnsent()
        #expect(controller.unsentCount > 0, "written but never sent")
        #expect(controller.status == .notAccepted(count: controller.unsentCount))
        controller.networkChanged(isOnline: false)
        #expect(controller.status == .waiting(lastSynced: controller.lastSynced))
        controller.networkChanged(isOnline: true)
        controller.activityChanged(isSynchronizing: true)
        #expect(controller.status == .syncing)
    }
}
