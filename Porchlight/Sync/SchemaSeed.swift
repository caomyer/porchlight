#if DEBUG
import CloudKit
import Foundation
import GRDB
import Observation
import SQLiteData
import SwiftUI
import UIKit

/// Teaches CloudKit's Development environment every record type and field the app syncs, so
/// the schema can be deployed to Production (docs/design/sync-icloud.md, "Deploying the
/// CloudKit schema"). CloudKit only creates a record type when a record of it is saved, and a
/// field when a non-nil value is saved, so the seed writes one row to every synced table with
/// a value in every column, sends them, shares the household, and removes it all again.
///
/// It never touches a household: it works in a throwaway database with its own sync
/// metadata, in its own iCloud zone, from its own app (`scripts/cloud-schema.sh seed`).
enum SchemaSeed {
    /// The launch argument that starts it, in a Debug build.
    static let argument = "-seedCloudSchema"

    /// The seed's own zone in the private database, never the household's.
    static let zone = CKRecordZone(zoneName: "porchlight.schemaSeed")

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    /// The bytes every BLOB column gets: sent as an asset, like a photo.
    static let blob = Data("Porchlight schema seed".utf8)

    /// Writes one row to every synced table, parents first, with a non-nil value in every
    /// column. Driven by the mirrors, so a new table or column is seeded without anyone
    /// remembering to (and `SchemaSeedTests` fails if a column type isn't handled).
    static func fill(_ db: Database, now: Date) throws {
        // Every table's row id up front, so any id column can point at a real row.
        var ids: [String: String] = [:]
        for mirror in SyncMirror.all { ids[mirror.tableName] = UUID().uuidString.lowercased() }
        for mirror in SyncMirror.all {
            let table = mirror.tableName
            let foreignKeys = try db.foreignKeys(on: table)
            let primaryKey = try db.primaryKey(table).columns
            var names: [String] = []
            var values: [DatabaseValue] = []
            for column in columns(of: mirror) {
                names.append(column.name)
                values.append(try value(for: column, isPrimaryKey: primaryKey == [column.name], table: table, ids: ids, foreignKeys: foreignKeys, now: now))
            }
            let quoted = names.map { "\"\($0)\"" }.joined(separator: ", ")
            let marks = Array(repeating: "?", count: names.count).joined(separator: ", ")
            try db.execute(sql: "INSERT INTO \"\(table)\" (\(quoted)) VALUES (\(marks))", arguments: StatementArguments(values))
        }
    }

    /// One mirror column: its name and the plain Swift type the engine reads it as.
    struct Column {
        enum Kind: String { case uuid, string, date, int, bool, double, data }
        var name: String
        var kind: Kind?
    }

    static func columns(of mirror: any PrimaryKeyedTable.Type) -> [Column] {
        func open<T: PrimaryKeyedTable>(_: T.Type) -> [Column] {
            T.TableColumns.allColumns.map { column in Column(name: column.name, kind: kind(of: column)) }
        }
        return open(mirror)
    }

    private static let kinds: [ObjectIdentifier: Column.Kind] = [
        ObjectIdentifier(UUID.self): .uuid, ObjectIdentifier(UUID?.self): .uuid,
        ObjectIdentifier(String.self): .string, ObjectIdentifier(String?.self): .string,
        ObjectIdentifier(Date.self): .date, ObjectIdentifier(Date?.self): .date,
        ObjectIdentifier(Int.self): .int, ObjectIdentifier(Int?.self): .int,
        ObjectIdentifier(Bool.self): .bool, ObjectIdentifier(Bool?.self): .bool,
        ObjectIdentifier(Double.self): .double, ObjectIdentifier(Double?.self): .double,
        ObjectIdentifier(Data.self): .data, ObjectIdentifier(Data?.self): .data,
    ]

    private static func kind<C: TableColumnExpression>(of _: C) -> Column.Kind? {
        kinds[ObjectIdentifier(C.Value.self)]
    }

    /// Id columns that aren't foreign keys, and the table whose row they name.
    private static let references = [
        "personId": "person", "ownerId": "person", "addedById": "person",
        "placeId": "foodPlace", "deviceId": "device", "dishId": "dish", "mergedInto": "dish", "recipeId": "recipe", "chosenById": "device", "setById": "device",
    ]

    private static func value(for column: Column, isPrimaryKey: Bool, table: String, ids: [String: String], foreignKeys: [ForeignKeyInfo], now: Date) throws -> DatabaseValue {
        switch column.kind {
        case .uuid?:
            if let key = foreignKeys.first(where: { $0.originColumns == [column.name] }) {
                return (ids[key.destinationTable] ?? UUID().uuidString.lowercased()).databaseValue
            }
            if isPrimaryKey { return (ids[table] ?? UUID().uuidString.lowercased()).databaseValue }
            return (references[column.name].flatMap { ids[$0] } ?? UUID().uuidString.lowercased()).databaseValue
        case .string?: return "seed".databaseValue
        case .date?: return now.databaseValue
        case .int?: return 1.databaseValue
        case .bool?: return true.databaseValue
        case .double?: return 0.5.databaseValue
        case .data?: return blob.databaseValue
        case nil: throw SeedError.unsupportedColumn("\(table).\(column.name)")
        }
    }

    enum SeedError: LocalizedError {
        case unsupportedColumn(String)
        case notSent([String])
        case missingFields([String])
        case notSigned

        var errorDescription: String? {
            switch self {
            case let .unsupportedColumn(column): "The seed doesn't know how to fill \(column)."
            case let .notSent(records): "iCloud didn't take \(records.count) records: \(records.joined(separator: ", "))."
            case let .missingFields(fields): "These fields never reached iCloud: \(fields.joined(separator: ", "))."
            case .notSigned: "This build isn't signed for iCloud. Seed from a signed Debug build (scripts/cloud-schema.sh seed)."
            }
        }
    }

    // MARK: What was sent

    /// What reached iCloud, read back from the engine's own record of each saved record.
    struct Report: Equatable {
        /// Every field of every record type, as CloudKit stores it.
        var fields: [String: Set<String>]
        var records: Int
        var shared: Bool

        var recordTypes: Int { fields.count }

        var summary: String {
            "Schema seeded: \(recordTypes) record types, \(records) records sent\(shared ? ", household shared" : "")."
        }
    }

    /// Reads back every saved record and checks that every mirror column is one of its
    /// fields. Throws when a row never reached iCloud or a column is missing.
    static func report(_ db: Database) throws -> Report {
        let metadata = try SyncMetadata.all.fetchAll(db)
        let unsent = metadata.filter { $0._lastKnownServerRecordAllFields == nil }.map(\.recordName)
        guard unsent.isEmpty else { throw SeedError.notSent(unsent) }
        var fields: [String: Set<String>] = [:]
        var shared = false
        for row in metadata {
            guard let record = row._lastKnownServerRecordAllFields else { continue }
            fields[row.recordType, default: []].formUnion(Self.fields(of: record))
            if let share = row.share {
                shared = true
                fields[share.recordType, default: []].formUnion(Self.fields(of: share))
            }
        }
        let missing = SyncMirror.all.flatMap { mirror in
            columns(of: mirror).map(\.name)
                .filter { !(fields[mirror.tableName]?.contains($0) ?? false) }
                .map { "\(mirror.tableName).\($0)" }
        }
        guard missing.isEmpty else { throw SeedError.missingFields(missing) }
        return Report(fields: fields, records: metadata.count, shared: shared)
    }

    /// A record's fields: plain ones (assets) and encrypted ones (every other value).
    /// SQLiteData's stand-in for iCloud keeps its version of the system fields (change tag,
    /// modification date) as "_" keys; CloudKit keeps those apart, so they are no fields.
    static func fields(of record: CKRecord) -> Set<String> {
        Set(record.allKeys()).union(record.encryptedValues.allKeys()).filter { !$0.hasPrefix("_") }
    }
}

/// Runs the seed: a throwaway database, an engine on the seed's zone, every row sent, the
/// household shared, then the zone deleted from iCloud and the database from the device.
@MainActor
@Observable
final class SchemaSeeder: StoredFirstObservable {
    enum Phase: Equatable {
        case running(String)
        case done(SchemaSeed.Report, cleanedUp: String?)
        case failed(String)
    }

    @ObservationIgnored @StoredFirst private(set) var phase: Phase = .running("Starting")

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let deleteZone: (CKRecordZone.ID) async throws -> Void
    @ObservationIgnored private let now: Date

    /// - Parameter deleteZone: Removes the seed's zone from iCloud; tests leave the stand-in
    ///   for iCloud alone.
    init(
        folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("schema-seed-\(UUID().uuidString)", isDirectory: true),
        now: Date = .now,
        deleteZone: @escaping (CKRecordZone.ID) async throws -> Void
    ) {
        self.folder = folder
        self.now = now
        self.deleteZone = deleteZone
    }

    /// The seeder for a launch with `-seedCloudSchema`, on the build's iCloud container.
    static func live() -> SchemaSeeder {
        SchemaSeeder { zoneID in
            _ = try await CKContainer(identifier: SyncController.containerIdentifier).privateCloudDatabase
                .modifyRecordZones(saving: [], deleting: [zoneID])
        }
    }

    /// Runs every step and leaves the outcome in `phase`; also prints it, for the console.
    func run(requireSigned: Bool = true) async {
        do {
            if requireSigned && !SyncController.isSignedForICloud { throw SchemaSeed.SeedError.notSigned }
            let report = try await seed()
            let cleanedUp = await cleanUp()
            phase = .done(report, cleanedUp: cleanedUp)
            log(report.summary)
            for (type, fields) in report.fields.sorted(by: { $0.key < $1.key }) {
                log("\(type): \(fields.sorted().joined(separator: ", "))")
            }
            log(cleanedUp ?? "Removed the seed from iCloud and from this device.")
        } catch {
            _ = await cleanUp()
            phase = .failed(error.localizedDescription)
            log("Failed: \(error.localizedDescription)")
        }
    }

    private var database: AppDatabase?
    private var engine: SyncEngine?
    private let events = SeedEvents()

    private func seed() async throws -> SchemaSeed.Report {
        step("Writing one row to every table")
        let database = try AppDatabase.openOnDisk(folder: folder)
        self.database = database
        let engine = try SyncMirror.engine(for: database.writer, delegate: events, zone: SchemaSeed.zone)
        self.engine = engine
        let now = now
        try await database.writer.write { try SchemaSeed.fill($0, now: now) }

        step("Sending every row to iCloud (Development)")
        try await engine.start()
        // The engine sends in batches; a few rounds bring everything up.
        for _ in 0..<5 {
            try await engine.sendChanges()
            let unsent = try await database.writer.read(SyncUnsent.count)
            if unsent == 0 { break }
        }

        step("Sharing the seed household")
        guard let household = try await database.writer.read({ try SyncMirror.Household.all.fetchOne($0) }) else {
            throw SchemaSeed.SeedError.notSent(["household"])
        }
        let thumbnail = Self.thumbnail()
        _ = try await engine.share(record: household) { share in
            // Every field the app or the share sheet sets on a share, so each exists in the schema.
            share[CKShare.SystemFieldKey.title] = "Porchlight schema seed"
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnail
            share.publicPermission = .readWrite
        }

        step("Checking what reached iCloud")
        return try await database.writer.read(SchemaSeed.report)
    }

    /// Deletes the seed's zone (its records and share go with it) and the throwaway files.
    /// Returns what went wrong, or nil when everything is gone.
    private func cleanUp() async -> String? {
        step("Removing the seed")
        engine?.stop()
        engine = nil
        var problem: String?
        do {
            try await deleteZone(SchemaSeed.zone.zoneID)
        } catch {
            problem = "The seed zone \(SchemaSeed.zone.zoneID.zoneName) is still in iCloud (Development): \(error.localizedDescription). Delete it in the CloudKit Console."
        }
        try? database?.writer.close()
        database = nil
        try? FileManager.default.removeItem(at: folder)
        return problem
    }

    private static func thumbnail() -> Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.pngData()
    }

    private func step(_ text: String) {
        if case .running = phase { phase = .running(text) }
        log(text)
    }

    private func log(_ text: String) {
        print("SchemaSeed: \(text)")
    }
}

/// The seed's engine never deletes anything on an account change: it has nothing to lose.
private final class SeedEvents: SyncEngineDelegate {
    func syncEngine(_ syncEngine: SyncEngine, accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType) async {}
}

/// The whole screen of a `-seedCloudSchema` launch: what it is doing, then the outcome.
struct SchemaSeedView: View {
    @State private var seeder = SchemaSeeder.live()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CloudKit schema seed")
                .font(.system(size: 28, weight: .bold))
            switch seeder.phase {
            case let .running(step):
                HStack(spacing: 10) {
                    ProgressView()
                    Text(step + "…")
                }
                .font(.system(size: 18))
            case let .done(report, cleanedUp):
                Text(report.summary)
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityIdentifier("schema-seed-result")
                Text(cleanedUp ?? "The seed is removed from iCloud and from this device. Export the schema next: scripts/cloud-schema.sh export.")
                    .font(.system(size: 16))
                ScrollView {
                    Text(report.fields.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.count) fields" }.joined(separator: "\n"))
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case let .failed(message):
                Text("Schema seed failed")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityIdentifier("schema-seed-result")
                Text(message)
                    .font(.system(size: 16))
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .task { await seeder.run() }
    }
}
#endif
