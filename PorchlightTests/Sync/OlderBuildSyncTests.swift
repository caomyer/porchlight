import CloudKit
import Foundation
import GRDB
import OSLog
import Testing
@testable import Porchlight
@testable import SQLiteData

/// What a device on an older build does with what a newer build writes: new record types
/// it has no table for, and new fields on a record it knows (docs/design/dishes.md,
/// "Older builds").
///
/// Two devices share one stand-in for iCloud: the newer one knows a `dish` table, a
/// `mealDish` table under each meal, and a new `otherSources` column on the meal; the older one
/// is today's schema. Nothing here is the dish feature itself, only the shapes it adds.
@MainActor
@Suite("Older builds", .serialized)
struct OlderBuildSyncTests {
    @Test("An older build keeps records it doesn't know, and a meal it edits keeps the newer fields")
    func olderBuildEditsAMeal() async throws {
        let cloud = Cloud()
        let newer = try await Phone(cloud, newer: true)
        let older = try await Phone(cloud, newer: false)
        let entryId = try newer.logMealWithDish()
        try await newer.engine.sendChanges()

        try await older.engine.fetchChanges()
        // The meal arrives as today's meal, its title the dishes, and the dish records wait
        // in the engine's metadata rather than failing.
        #expect(try older.title(of: entryId) == "Pho tai, spring rolls")
        #expect(try older.hasTable("dish") == false)
        #expect(try older.waiting(recordType: "dish") == 2)
        #expect(try older.waiting(recordType: "mealDish") == 2)

        try older.write("UPDATE journalEntry SET title = 'Pho', rating = 4 WHERE id = ?", entryId)
        try await older.engine.sendChanges()

        // iCloud's record still has the field the older build doesn't know.
        let record = try #require(cloud.record(entryId, type: "journalEntry"))
        #expect(record.encryptedValues["otherSources"] as? String == "dineOut,delivery")
        #expect(record.encryptedValues["title"] as? String == "Pho")

        try await newer.engine.fetchChanges()
        #expect(try newer.title(of: entryId) == "Pho")
        #expect(try newer.string("SELECT otherSources FROM journalEntry WHERE id = ?", entryId) == "dineOut,delivery")
        #expect(try newer.count("SELECT COUNT(*) FROM mealDish WHERE entryId = ?", entryId) == 2)
    }

    @Test("Updating to the newer build brings in the records an older build kept waiting")
    func updatingAppliesWaitingRecords() async throws {
        let cloud = Cloud()
        let newer = try await Phone(cloud, newer: true)
        var older = try await Phone(cloud, newer: false)
        let entryId = try newer.logMealWithDish()
        try await newer.engine.sendChanges()
        try await older.engine.fetchChanges()

        older = try await older.updated()
        #expect(try older.count("SELECT COUNT(*) FROM dish") == 2)
        #expect(try older.count("SELECT COUNT(*) FROM mealDish WHERE entryId = ?", entryId) == 2)
        #expect(try older.string("SELECT otherSources FROM journalEntry WHERE id = ?", entryId) == "dineOut,delivery")
    }

    @Test("An older build can't remove a meal that has dishes: iCloud keeps it, and it comes back there")
    func olderBuildRemovesAMeal() async throws {
        let cloud = Cloud()
        let newer = try await Phone(cloud, newer: true)
        var older = try await Phone(cloud, newer: false)
        let entryId = try newer.logMealWithDish()
        try await newer.engine.sendChanges()
        try await older.engine.fetchChanges()

        // The older build deletes the meal but not its dish lines, which it doesn't know.
        // iCloud refuses to delete a record other records name as their parent.
        try older.write("DELETE FROM journalEntry WHERE id = ?", entryId)
        try await older.engine.sendChanges()
        #expect(cloud.record(entryId, type: "journalEntry") != nil, "iCloud keeps the meal")
        #expect(cloud.records(type: "mealDish").count == 2)
        try await older.engine.fetchChanges()
        #expect(try older.count("SELECT COUNT(*) FROM journalEntry WHERE id = ?", entryId) == 1, "and it comes back on the older device")

        try await newer.engine.fetchChanges()
        #expect(try newer.count("SELECT COUNT(*) FROM journalEntry WHERE id = ?", entryId) == 1, "nothing is lost on the newer one")
        #expect(try newer.count("SELECT COUNT(*) FROM mealDish WHERE entryId = ?", entryId) == 2)

        // Updated, the same device removes it, with its dish lines, everywhere.
        older = try await older.updated()
        try older.write("DELETE FROM journalEntry WHERE id = ?", entryId)
        try await older.engine.sendChanges()
        #expect(cloud.record(entryId, type: "journalEntry") == nil)
        #expect(cloud.records(type: "mealDish").isEmpty)
        try await newer.engine.fetchChanges()
        #expect(try newer.count("SELECT COUNT(*) FROM journalEntry WHERE id = ?", entryId) == 0)
        #expect(try newer.count("SELECT COUNT(*) FROM mealDish") == 0)
        // The dishes belong to the household and stay.
        #expect(try newer.count("SELECT COUNT(*) FROM dish") == 2)
    }
}

// MARK: - Devices

/// One stand-in for iCloud, shared by every device of a test.
private final class Cloud {
    let container: MockCloudContainer

    init() {
        container = MockCloudContainer(
            containerIdentifier: SyncController.containerIdentifier,
            privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
            sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
        )
        container.privateCloudDatabase.set(container: container)
        container.sharedCloudDatabase.set(container: container)
    }

    func records(type: String) -> [CKRecord] {
        container.privateCloudDatabase.state.withValue { state in
            state.storage.values.flatMap { $0.records.values }.filter { $0.recordType == type }
        }
    }

    func record(_ id: some CustomStringConvertible, type: String) -> CKRecord? {
        records(type: type).first { $0.recordID.recordName.hasPrefix(id.description.lowercased()) }
    }
}

/// A device: its own database on disk and its own sync metadata, on today's schema or the
/// newer one.
@MainActor
private final class Phone {
    let cloud: Cloud
    let folder: URL
    let database: AppDatabase
    let engine: SyncEngine
    let newer: Bool

    init(_ cloud: Cloud, newer: Bool, folder: URL? = nil) async throws {
        self.cloud = cloud
        self.newer = newer
        self.folder = folder ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("older-build-\(UUID().uuidString)", isDirectory: true)
        database = try AppDatabase.openOnDisk(folder: self.folder)
        try await database.writer.write { db in
            if newer {
                // A field the newer build adds to a record the older one knows.
                if try !db.columns(in: "journalEntry").contains(where: { $0.name == "otherSources" }) {
                    try db.execute(sql: #"ALTER TABLE "journalEntry" ADD COLUMN "otherSources" TEXT"#)
                }
            } else {
                // Today's schema, from before dishes.
                try db.execute(sql: """
                    DROP TABLE "mealDishRating"; DROP TABLE "mealDish"; DROP TABLE "dish";
                    DELETE FROM grdb_migrations WHERE identifier = ?;
                    """, arguments: [AppDatabase.dishMigration])
            }
        }
        let container = cloud.container
        engine = try SyncEngine(
            container: container,
            defaultZone: SyncMirror.householdZone,
            defaultSyncEngines: { _, engine in
                (
                    private: MockSyncEngine(database: container.privateCloudDatabase, parentSyncEngine: engine, state: MockSyncEngineState()),
                    shared: MockSyncEngine(database: container.sharedCloudDatabase, parentSyncEngine: engine, state: MockSyncEngineState())
                )
            },
            userDatabase: UserDatabase(database: database.writer),
            logger: Logger(.disabled),
            delegate: nil,
            tables: newer ? Self.newerTables : Self.olderTables
        )
        try engine.setUpSyncEngine()
        try await engine.start()
    }

    /// The same device after updating to the newer build: its database and metadata, the
    /// newer schema, a new engine.
    func updated() async throws -> Phone {
        engine.stop()
        try database.writer.close()
        return try await Phone(cloud, newer: true, folder: folder)
    }

    static var olderTables: [any SynchronizableTable] {
        [
            SynchronizedTable(for: SyncMirror.Household.self), SynchronizedTable(for: SyncMirror.Person.self),
            SynchronizedTable(for: SyncMirror.Journal.self), SynchronizedTable(for: SyncMirror.FoodPlace.self),
            SynchronizedTable(for: SyncMirror.JournalEntry.self), SynchronizedTable(for: SyncMirror.JournalEntryEater.self),
        ]
    }

    static var newerTables: [any SynchronizableTable] {
        [
            SynchronizedTable(for: SyncMirror.Household.self), SynchronizedTable(for: SyncMirror.Person.self),
            SynchronizedTable(for: SyncMirror.Journal.self), SynchronizedTable(for: SyncMirror.FoodPlace.self),
            SynchronizedTable(for: NewerMirror.JournalEntry.self), SynchronizedTable(for: SyncMirror.JournalEntryEater.self),
            SynchronizedTable(for: SyncMirror.Dish.self), SynchronizedTable(for: SyncMirror.MealDish.self),
            SynchronizedTable(for: SyncMirror.MealDishRating.self),
        ]
    }

    /// A household, a dinner out with two dishes, and a field the older build lacks.
    func logMealWithDish() throws -> JournalEntry.ID {
        let household = try database.createHousehold(name: "The Lake House", people: [PersonDraft(name: "James", color: .blue)])
        try database.markSetupCompleted(householdId: household.id)
        let people = try database.snapshot().people.map(\.id)
        let journal = try database.ensureFoodJournal(householdId: household.id)
        var draft = MealDraft(
            day: DayKey(.now, calendar: household.calendar), slot: "Dinner", sources: MealSources(.dineOut),
            eaterIds: people, eatenAt: .now, place: PlaceDraft(name: "Pho Saigon House")
        )
        draft.dishes = [DishLineDraft(name: "Pho tai", rating: .favorite), DishLineDraft(name: "Spring rolls", rating: .again)]
        let meal = try database.addMeal(draft, journalId: journal.id)
        try write("UPDATE journalEntry SET otherSources = 'dineOut,delivery' WHERE id = ?", meal.id)
        return meal.id
    }

    func write(_ sql: String, _ arguments: any DatabaseValueConvertible...) throws {
        try database.writer.write { try $0.execute(sql: sql, arguments: StatementArguments(arguments)) }
    }

    func count(_ sql: String, _ arguments: any DatabaseValueConvertible...) throws -> Int {
        try database.writer.read { try Int.fetchOne($0, sql: sql, arguments: StatementArguments(arguments)) ?? 0 }
    }

    func string(_ sql: String, _ arguments: any DatabaseValueConvertible...) throws -> String? {
        try database.writer.read { try String.fetchOne($0, sql: sql, arguments: StatementArguments(arguments)) }
    }

    func title(of id: JournalEntry.ID) throws -> String? {
        try string("SELECT title FROM journalEntry WHERE id = ?", id)
    }

    func hasTable(_ name: String) throws -> Bool {
        try database.writer.read { try $0.tableExists(name) }
    }

    /// Records of a type the engine holds without a table to put them in.
    func waiting(recordType: String) throws -> Int {
        try count("""
            SELECT COUNT(*) FROM sqlitedata_icloud_metadata
            WHERE recordType = ? AND lastKnownServerRecord IS NOT NULL
            """, recordType)
    }
}

/// The newer build's meal: one more column than today's.
private enum NewerMirror {
    @Table("journalEntry") struct JournalEntry {
        let id: UUID
        var journalId: UUID
        var day: String
        var slot: String
        var source: String
        var title: String
        var emoji: String?
        var tint: Int?
        var rating: Int?
        var eatenAt: Date
        var createdAt: Date
        var placeId: UUID?
        var deviceId: UUID?
        var otherSources: String?
    }
}
