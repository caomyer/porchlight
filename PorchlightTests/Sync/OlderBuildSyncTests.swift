import CloudKit
import Dependencies
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
/// Two devices share one stand-in for iCloud: the newer one is today's app; the older one
/// is the build from before dishes (no dish tables, no `otherSources` on the meal), or the
/// one from before recipes (no recipe tables, no `dishId` on a planned dinner).
@MainActor
@Suite("Older builds", .serialized)
struct OlderBuildSyncTests {
    @Test("An older build keeps records it doesn't know, and a meal it edits keeps the newer fields")
    func olderBuildEditsAMeal() async throws {
        let cloud = Cloud()
        let newer = try await Phone(cloud, build: .today)
        let older = try await Phone(cloud, build: .beforeDishes)
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
        let newer = try await Phone(cloud, build: .today)
        var older = try await Phone(cloud, build: .beforeDishes)
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
        let newer = try await Phone(cloud, build: .today)
        var older = try await Phone(cloud, build: .beforeDishes)
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

// MARK: - Recipes

extension OlderBuildSyncTests {
    @Test("A build before recipes keeps them waiting, and a planned dinner it edits keeps its dish")
    func olderBuildKeepsRecipes() async throws {
        let cloud = Cloud()
        let newer = try await Phone(cloud, build: .today)
        let older = try await Phone(cloud, build: .beforeRecipes)
        let dishId = try newer.cookCurryWithRecipe()
        try await newer.engine.sendChanges()

        try await older.engine.fetchChanges()
        #expect(try older.count("SELECT COUNT(*) FROM dish WHERE id = ?", dishId) == 1)
        #expect(try older.hasTable("recipe") == false)
        for type in ["recipe", "recipePhoto"] {
            #expect(try older.waiting(recordType: type) == 1, "\(type) waits in the engine's metadata")
        }

        // Friday's dinner gets a new emoji on the older build: it sends what it changed.
        try older.write("UPDATE mealPlan SET emoji = '🍲'")
        try await older.engine.sendChanges()
        let plan = try #require(cloud.records(type: "mealPlan").first)
        #expect(plan.encryptedValues["dishId"] as? String == dishId.description, "iCloud keeps the dish")
        #expect(plan.encryptedValues["emoji"] as? String == "🍲")

        try await newer.engine.fetchChanges()
        #expect(try newer.string("SELECT dishId FROM mealPlan") == dishId.description)
        #expect(try newer.string("SELECT emoji FROM mealPlan") == "🍲")
        #expect(try newer.count("SELECT COUNT(*) FROM recipe WHERE dishId = ?", dishId) == 1)
    }

    @Test("A build before recipes can't remove a dish that has one: iCloud keeps it, and the recipe is never lost")
    func olderBuildRemovesADishWithARecipe() async throws {
        let cloud = Cloud()
        let newer = try await Phone(cloud, build: .today)
        let older = try await Phone(cloud, build: .beforeRecipes)
        let dishId = try newer.cookCurryWithRecipe()
        try await newer.engine.sendChanges()
        try await older.engine.fetchChanges()

        // What its "Remove dish" does: the lines and the dish, not the recipe it doesn't know.
        try older.write("DELETE FROM mealDish WHERE dishId = ?", dishId)
        try older.write("DELETE FROM dish WHERE id = ?", dishId)
        try await older.engine.sendChanges()
        #expect(cloud.record(dishId, type: "dish") != nil, "iCloud keeps the dish its recipe hangs off")
        #expect(cloud.records(type: "recipe").count == 1)
        #expect(cloud.records(type: "recipePhoto").count == 1)
        try await older.engine.fetchChanges()
        #expect(try older.count("SELECT COUNT(*) FROM dish WHERE id = ?", dishId) == 1, "and it comes back on the older device")

        try await newer.engine.fetchChanges()
        #expect(try newer.count("SELECT COUNT(*) FROM dish WHERE id = ?", dishId) == 1)
        #expect(try newer.count("SELECT COUNT(*) FROM recipe WHERE dishId = ?", dishId) == 1, "the recipe is never lost")
        #expect(try newer.count("SELECT COUNT(*) FROM recipePhoto") == 1)
    }

    @Test("Updating to today's build brings in the waiting recipe and the planned dinner's dish")
    func updatingBringsInRecipes() async throws {
        // A new engine on the same device files the waiting card photo as an asset, which
        // the stand-in for iCloud names with a fresh id.
        try await withDependencies { $0.uuid = .incrementing } operation: {
            try await bringsInRecipes()
        }
    }

    private func bringsInRecipes() async throws {
        let cloud = Cloud()
        let newer = try await Phone(cloud, build: .today)
        var older = try await Phone(cloud, build: .beforeRecipes)
        let dishId = try newer.cookCurryWithRecipe()
        try await newer.engine.sendChanges()
        try await older.engine.fetchChanges()

        older = try await older.updated()
        #expect(try older.count("SELECT COUNT(*) FROM recipe WHERE dishId = ?", dishId) == 1)
        #expect(try older.string("SELECT CAST(image AS TEXT) FROM recipePhoto") == "card", "the card photo, with its picture")
        #expect(try older.string("SELECT CAST(thumbnail AS TEXT) FROM recipePhoto") == "small")
        #expect(try older.string("SELECT dishId FROM mealPlan") == dishId.description)
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
    let build: Build

    /// Which build a device runs: today's, the one from before recipes (dishes, but no
    /// recipe tables and no planned dinner's dish), or the one from before dishes.
    enum Build { case today, beforeRecipes, beforeDishes }

    init(_ cloud: Cloud, build: Build, folder: URL? = nil) async throws {
        self.cloud = cloud
        self.build = build
        self.folder = folder ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("older-build-\(UUID().uuidString)", isDirectory: true)
        database = try AppDatabase.openOnDisk(folder: self.folder)
        if build != .today {
            // Before recipes: no recipe tables and no `dishId` on a planned dinner. Updating
            // runs that migration again.
            try await database.writer.write { db in
                try db.execute(sql: """
                    DROP TABLE "recipePhoto"; DROP TABLE "recipe";
                    ALTER TABLE "mealPlan" DROP COLUMN "dishId";
                    DELETE FROM grdb_migrations WHERE identifier = ?;
                    """, arguments: [AppDatabase.recipeMigration])
            }
        }
        if build == .beforeDishes {
            // The schema from before dishes and before a meal could come from several places:
            // no dish tables, and no `otherSources` on the meal. Updating runs both again.
            try await database.writer.write { db in
                try db.execute(sql: """
                    DROP TABLE "mealDishRating"; DROP TABLE "mealDish"; DROP TABLE "dish";
                    ALTER TABLE "journalEntry" DROP COLUMN "otherSources";
                    DELETE FROM grdb_migrations WHERE identifier IN (?, ?);
                    """, arguments: [AppDatabase.dishMigration, AppDatabase.severalPlacesMigration])
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
            tables: {
                switch build {
                case .today: Self.newerTables
                case .beforeRecipes: Self.beforeRecipesTables
                case .beforeDishes: Self.olderTables
                }
            }()
        )
        try engine.setUpSyncEngine()
        try await engine.start()
    }

    /// The same device after updating to the newer build: its database and metadata, the
    /// newer schema, a new engine.
    func updated() async throws -> Phone {
        engine.stop()
        try database.writer.close()
        return try await Phone(cloud, build: .today, folder: folder)
    }

    static var olderTables: [any SynchronizableTable] {
        [
            SynchronizedTable(for: SyncMirror.Household.self), SynchronizedTable(for: SyncMirror.Person.self),
            SynchronizedTable(for: SyncMirror.Journal.self), SynchronizedTable(for: SyncMirror.FoodPlace.self),
            SynchronizedTable(for: OlderMirror.JournalEntry.self), SynchronizedTable(for: SyncMirror.JournalEntryEater.self),
        ]
    }

    static var beforeRecipesTables: [any SynchronizableTable] {
        [
            SynchronizedTable(for: SyncMirror.Household.self), SynchronizedTable(for: SyncMirror.Person.self),
            SynchronizedTable(for: SyncMirror.Journal.self), SynchronizedTable(for: SyncMirror.FoodPlace.self),
            SynchronizedTable(for: SyncMirror.JournalEntry.self), SynchronizedTable(for: SyncMirror.JournalEntryEater.self),
            SynchronizedTable(for: OlderMirror.MealPlan.self),
            SynchronizedTable(for: SyncMirror.Dish.self), SynchronizedTable(for: SyncMirror.MealDish.self),
            SynchronizedTable(for: SyncMirror.MealDishRating.self),
        ]
    }

    static var newerTables: [any SynchronizableTable] {
        [
            SynchronizedTable(for: SyncMirror.Household.self), SynchronizedTable(for: SyncMirror.Person.self),
            SynchronizedTable(for: SyncMirror.Journal.self), SynchronizedTable(for: SyncMirror.FoodPlace.self),
            SynchronizedTable(for: SyncMirror.JournalEntry.self), SynchronizedTable(for: SyncMirror.JournalEntryEater.self),
            SynchronizedTable(for: SyncMirror.MealPlan.self),
            SynchronizedTable(for: SyncMirror.Dish.self), SynchronizedTable(for: SyncMirror.MealDish.self),
            SynchronizedTable(for: SyncMirror.MealDishRating.self),
            SynchronizedTable(for: SyncMirror.Recipe.self), SynchronizedTable(for: SyncMirror.RecipePhoto.self),
        ]
    }

    /// A household, a home dinner of chicken curry, its recipe with a photo of the card,
    /// and Friday's dinner planned from it. Returns the dish.
    func cookCurryWithRecipe() throws -> Dish.ID {
        let household = try database.createHousehold(name: "The Lake House", people: [PersonDraft(name: "Mia", color: .coral)])
        try database.markSetupCompleted(householdId: household.id)
        let people = try database.snapshot().people.map(\.id)
        let journal = try database.ensureFoodJournal(householdId: household.id)
        var draft = MealDraft(day: DayKey(rawValue: "2026-11-02"), slot: "Dinner", eaterIds: people, eatenAt: .now)
        draft.dishes = [DishLineDraft(name: "Chicken curry", rating: .again)]
        _ = try database.addMeal(draft, journalId: journal.id)
        let saved = try database.saveRecipe(
            RecipeDraft(
                name: "Chicken curry", serves: 4, ingredients: ["2 lb chicken thighs", "1 can coconut milk"], steps: ["Brown the chicken."],
                photos: [.added(NewRecipePhoto(image: Data("card".utf8), thumbnail: Data("small".utf8)))]
            ),
            householdId: household.id, addedBy: people[0]
        )
        try database.setMeal(day: DayKey(rawValue: "2026-11-27"), title: "Chicken curry", emoji: "🍛", householdId: household.id, dishId: saved.dish.id)
        return saved.dish.id
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

/// The older builds' rows: a meal without `otherSources`, and a planned dinner without its dish.
private enum OlderMirror {
    @Table("mealPlan") struct MealPlan {
        let id: UUID
        var householdId: UUID
        var day: String
        var title: String
        var emoji: String?
    }

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
    }
}
