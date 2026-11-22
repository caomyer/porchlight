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

    /// The update's catch-up puts the waiting records into the new tables; each engine went
    /// through them in its own dictionary order, so `mealDishRating` could come before its
    /// parent `mealDish`, fail its foreign key and stop the catch-up for every table after it.
    /// SQLiteData is patched to go parents first (project.yml, docs/design/dishes.md, "Why a
    /// card photo hangs off the dish"); twelve updates make an unlucky order near certain.
    @Test("Updating from before dishes brings in every dish, line and face on the first launch, every time")
    func updatingBringsInDishFacesParentsFirst() async throws {
        for attempt in 1...12 {
            let cloud = Cloud()
            let newer = try await Phone(cloud, build: .today)
            var older = try await Phone(cloud, build: .beforeDishes)
            let entryId = try newer.logMealWithDish()
            try newer.giveOwnFace(entryId)
            try await newer.engine.sendChanges()
            try await older.engine.fetchChanges()
            #expect(try older.waiting(recordType: "mealDishRating") == 1, "the face waits, update \(attempt)")

            older = try await older.updated()
            #expect(try older.count("SELECT COUNT(*) FROM dish") == 2, "the dishes, update \(attempt)")
            #expect(try older.count("SELECT COUNT(*) FROM mealDish WHERE entryId = ?", entryId) == 2, "the lines, update \(attempt)")
            #expect(try older.count("SELECT COUNT(*) FROM mealDishRating") == 1, "the face, update \(attempt)")
            #expect(try older.string("SELECT otherSources FROM journalEntry WHERE id = ?", entryId) == "dineOut,delivery", "update \(attempt)")
        }
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

    /// Each record's fields as text, by record name, to tell which changed.
    func fields(type: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: records(type: type).map { record in
            (record.recordID.recordName, record.allKeys().sorted().map { "\($0)=\(record.encryptedValues[$0] ?? record[$0] ?? "nil" as NSString)" }.joined(separator: ";"))
        })
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

    /// Which build a device runs: today's, the one from before the shared calendar, the one
    /// from before recipes (dishes, but no recipe tables and no planned dinner's dish), or
    /// the one from before dishes.
    enum Build { case today, beforeHomeCalendar, beforeCalendar, beforeRecipes, beforeDishes }

    /// Each device its own install, so each has its own row in the household.
    init(_ cloud: Cloud, build: Build, folder: URL? = nil, install: String = UUID().uuidString) async throws {
        self.cloud = cloud
        self.build = build
        self.folder = folder ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("older-build-\(UUID().uuidString)", isDirectory: true)
        let installFile = self.folder.appendingPathComponent("install")
        try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        let install = (try? String(contentsOf: installFile, encoding: .utf8)) ?? install
        try install.write(to: installFile, atomically: true, encoding: .utf8)
        database = try AppDatabase.openOnDisk(folder: self.folder, installId: install)
        if build != .today {
            // Before the home calendar: no home calendar, no "For", no device half of either.
            try await database.writer.write { db in
                try db.execute(sql: """
                    DROP TABLE "eventFor"; DROP TABLE "homeCalendar"; DROP TABLE "calendarItemFor";
                    ALTER TABLE "calendarSource" DROP COLUMN "isHome";
                    DELETE FROM grdb_migrations WHERE identifier = ?;
                    """, arguments: [AppDatabase.homeCalendarMigration])
            }
        }
        if build != .today && build != .beforeHomeCalendar {
            // Before the shared calendar: none of its tables, and no choice per calendar.
            try await database.writer.write { db in
                try db.execute(sql: """
                    DROP TABLE "sharedEvent"; DROP TABLE "sharedCalendar"; DROP TABLE "calendarFeed";
                    ALTER TABLE "calendarSource" DROP COLUMN "sharing";
                    DELETE FROM grdb_migrations WHERE identifier = ?;
                    """, arguments: [AppDatabase.sharedCalendarMigration])
            }
        }
        if build == .beforeRecipes || build == .beforeDishes {
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
                case .beforeHomeCalendar: Self.beforeHomeCalendarTables
                case .beforeCalendar: Self.beforeCalendarTables
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
        beforeHomeCalendarTables + [
            SynchronizedTable(for: SyncMirror.HomeCalendar.self), SynchronizedTable(for: SyncMirror.EventFor.self),
        ]
    }

    static var beforeHomeCalendarTables: [any SynchronizableTable] {
        beforeCalendarTables + [
            SynchronizedTable(for: SyncMirror.CalendarFeed.self), SynchronizedTable(for: SyncMirror.SharedCalendar.self),
            SynchronizedTable(for: SyncMirror.SharedEvent.self),
        ]
    }

    static var beforeCalendarTables: [any SynchronizableTable] {
        [
            SynchronizedTable(for: SyncMirror.Household.self), SynchronizedTable(for: SyncMirror.Person.self),
            SynchronizedTable(for: SyncMirror.Journal.self), SynchronizedTable(for: SyncMirror.FoodPlace.self),
            SynchronizedTable(for: SyncMirror.JournalEntry.self), SynchronizedTable(for: SyncMirror.JournalEntryEater.self),
            SynchronizedTable(for: SyncMirror.MealPlan.self),
            SynchronizedTable(for: SyncMirror.Dish.self), SynchronizedTable(for: SyncMirror.MealDish.self),
            SynchronizedTable(for: SyncMirror.MealDishRating.self),
            SynchronizedTable(for: SyncMirror.Recipe.self), SynchronizedTable(for: SyncMirror.RecipePhoto.self),
            SynchronizedTable(for: SyncMirror.Device.self),
        ]
    }

    /// A household with Mia, this device as her phone, and her calendars as the provider
    /// would give them, chosen as asked; then one pass, as the store makes it. Returns the
    /// household.
    @discardableResult
    func passOnMiasCalendars(_ choices: [String: CalendarChoice], household existing: Household? = nil, now: Date = SharedCalendarFixture.now) throws -> Household {
        let household = try existing ?? database.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "Mia", color: .coral), PersonDraft(name: "Sam", color: .blue)]
        )
        try database.markSetupCompleted(householdId: household.id)
        let mia = try #require(try database.snapshot().people.first { $0.name == "Mia" })
        try database.saveThisDevice(ThisDevice(name: "Mia's iPhone", role: .personal, model: "iPhone", personId: mia.id), in: household.id, now: now)
        try database.syncCalendarSources(householdId: household.id, calendars: SharedCalendarFixture.calendars, now: now)
        for source in try database.calendarSnapshot().sources {
            try database.setCalendarSourceOwner(id: source.id, owner: .person(mia.id))
            try database.setCalendarSourceSharing(id: source.id, sharing: choices[source.externalId] ?? .everything)
        }
        try database.markCalendarChoicesSeen(now: now)
        try pass(household, now: now)
        return household
    }

    /// One pass of this device's calendars, as `CalendarStore.passOn` makes it.
    @discardableResult
    func pass(_ household: Household, events: [ExternalEvent] = SharedCalendarFixture.events, now: Date = SharedCalendarFixture.now) throws -> CalendarPassResult? {
        let calendar = household.calendar
        let window = CalendarPassOn.window(today: DayKey(now, calendar: calendar), calendar: calendar)
        let plan = CalendarPassOn.plan(
            sources: try database.calendarSnapshot().sources, calendars: SharedCalendarFixture.calendars, events: events,
            deviceId: database.thisDeviceId(in: household.id), deviceCalendar: calendar, householdCalendar: calendar
        )
        var currentKeys: [String: String] = [:]
        for event in events {
            if let key = CalendarPassOn.matchKey(event.externalItemId) { currentKeys[EventForLogic.itemId(ofOccurrence: event.id)] = key }
        }
        return try database.passOnCalendars(plan, householdId: household.id, trigger: .open, window: window, now: now, currentKeys: currentKeys)
    }

    /// The events this device shows from the other devices, each with its "For".
    func shownFromOthers(_ household: Household) throws -> [CalendarEvent] {
        let snapshot = try database.calendarSnapshot()
        let events = SharedCalendarView.events(snapshot.shared, people: snapshot.people)
        return EventForLogic.apply(try database.eventFors(householdId: household.id), to: events, householdId: household.id)
    }


    /// A household, a home dinner of chicken curry, its recipe with a photo of the card,
    /// and Friday's dinner planned from it. Returns the dish.
    func cookCurryWithRecipe() throws -> Dish.ID {
        let household = try database.createHousehold(name: "The Lake House", people: [PersonDraft(name: "Mia", color: .coral)])
        try database.markSetupCompleted(householdId: household.id)
        let people = try database.snapshot().people.map(\.id)
        let journal = try database.ensureFoodJournal(householdId: household.id)
        var draft = MealDraft(day: DayKey(rawValue: "2026-11-02"), slot: "Dinner", eaterIds: people, eatenAt: CompanionClock.now())
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
            day: DayKey(CompanionClock.now(), calendar: household.calendar), slot: "Dinner", sources: MealSources(.dineOut),
            eaterIds: people, eatenAt: CompanionClock.now(), place: PlaceDraft(name: "Pho Saigon House")
        )
        draft.dishes = [DishLineDraft(name: "Pho tai", rating: .favorite), DishLineDraft(name: "Spring rolls", rating: .again)]
        let meal = try database.addMeal(draft, journalId: journal.id)
        try write("UPDATE journalEntry SET otherSources = 'dineOut,delivery' WHERE id = ?", meal.id)
        return meal.id
    }

    /// The first person's own face on the meal's first dish: a `mealDishRating` row, whose
    /// parent is the `mealDish` row.
    func giveOwnFace(_ entryId: JournalEntry.ID) throws {
        let line = try #require(try database.writer.read { try MealDish.filter(Column("entryId") == entryId).order(Column("sortOrder")).fetchOne($0) })
        let person = try #require(try database.snapshot().people.first)
        try database.setPersonFace(lineId: line.id, personId: person.id, .meh)
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

// MARK: - The shared calendar

/// Mia's calendars, as her phone's provider gives them: her own, her work, and a doctor's
/// calendar, each event's words marked so a test can tell whether they left the phone.
enum SharedCalendarFixture {
    static let now = Date(timeIntervalSince1970: 1_795_363_200) // Nov 22, 2026, 16:00 UTC, 08:00 in Los Angeles

    static let calendars = [
        ExternalCalendar(id: "mia-own", title: "Mia", account: "iCloud · mia@example.com", colorHex: 0xDD7558, accountKind: "iCloud"),
        ExternalCalendar(id: "mia-work", title: "Work", account: "Exchange · mia@work.example", colorHex: 0x7E8CA0, accountKind: "Exchange"),
        ExternalCalendar(id: "mia-doctor", title: "SECRET-CAL", account: "Google · mia@example.com", colorHex: 0x9AA0A6, accountKind: "Google"),
    ]

    static let events: [ExternalEvent] = [
        ExternalEvent(id: "own-1@1", calendarId: "mia-own", title: "Soccer practice", location: "Lincoln field", start: now.addingTimeInterval(7 * 3600), end: now.addingTimeInterval(9 * 3600), isAllDay: false, externalItemId: "soccer@icloud"),
        ExternalEvent(id: "work-1@1", calendarId: "mia-work", title: "Standup", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(2 * 3600), isAllDay: false, externalItemId: "standup@work"),
        ExternalEvent(id: "work-2@1", calendarId: "mia-work", title: "Planning", start: now.addingTimeInterval(5 * 3600), end: now.addingTimeInterval(6 * 3600), isAllDay: false),
        ExternalEvent(id: "doc-1@1", calendarId: "mia-doctor", title: "SECRET-TITLE", location: "SECRET-PLACE", notes: "SECRET-NOTE", start: now.addingTimeInterval(26 * 3600), end: now.addingTimeInterval(27 * 3600), isAllDay: false, externalItemId: "SECRET-UID"),
    ]

    static let secrets = ["SECRET-TITLE", "SECRET-PLACE", "SECRET-NOTE", "SECRET-CAL", "SECRET-UID", "mia@example.com", "mia@work.example"]

    /// Every string in every field of a record.
    static func strings(_ record: CKRecord) -> [String] {
        record.allKeys().compactMap { record.encryptedValues[$0] as? String ?? record[$0] as? String }
    }
}

@MainActor
@Suite("The shared calendar between two devices", .serialized)
struct SharedCalendarSyncTests {
    @Test("Mia's phone passes her calendars on, Sam's phone shows them, and Busy only and Just me keep their words on her phone")
    func passesOn() async throws {
        let cloud = Cloud()
        let mia = try await Phone(cloud, build: .today)
        let household = try mia.passOnMiasCalendars(["mia-own": .everything, "mia-work": .quiet, "mia-doctor": .busy])
        try await mia.engine.sendChanges()

        // Nothing of the doctor's calendar but its times reached iCloud, nor any account.
        for type in ["calendarFeed", "sharedCalendar", "sharedEvent"] {
            for record in cloud.records(type: type) {
                for text in SharedCalendarFixture.strings(record) {
                    for secret in SharedCalendarFixture.secrets { #expect(!text.contains(secret), "\(secret) reached iCloud in \(type)") }
                }
            }
        }
        #expect(cloud.records(type: "sharedEvent").count == 4)

        let sam = try await Phone(cloud, build: .today)
        try await sam.engine.fetchChanges()
        let samId = try #require(try sam.database.snapshot().people.first { $0.name == "Sam" }?.id)
        try sam.database.saveThisDevice(ThisDevice(name: "Sam's iPhone", role: .personal, model: "iPhone", personId: samId), in: household.id)
        let snapshot = try sam.database.calendarSnapshot()
        let shown = SharedCalendarView.events(snapshot.shared, people: snapshot.people)
        #expect(shown.map(\.title).sorted() == ["Busy", "Planning", "Soccer practice", "Standup"])
        #expect(shown.filter(\.isQuiet).map(\.title).sorted() == ["Planning", "Standup"])
        #expect(shown.first { $0.title == "Soccer practice" }?.location == "Lincoln field")
        let miaId = try #require(snapshot.people.first { $0.name == "Mia" }?.id)
        #expect(shown.allSatisfy { $0.owner == .person(miaId) })
        let blocks = SharedCalendarView.quietBlocks(shown, people: snapshot.people, calendar: household.calendar)
        let block = try #require(blocks.first { $0.isQuiet })
        #expect(block.title == "Mia at work" && block.quietEvents.count == 2)
        #expect(block.start == SharedCalendarFixture.now.addingTimeInterval(3600) && block.end == SharedCalendarFixture.now.addingTimeInterval(6 * 3600))

        // Mia's phone never shows its own passed-on copy.
        let own = try mia.database.calendarSnapshot()
        #expect(SharedCalendarView.events(own.shared, people: own.people).isEmpty)
    }

    @Test("A pass with nothing new sends nothing within the hour, then only the feed's stamp; a changed event sends only that event")
    func passesOnOnlyWhatChanged() async throws {
        let cloud = Cloud()
        let mia = try await Phone(cloud, build: .today)
        let household = try mia.passOnMiasCalendars([:])
        try await mia.engine.sendChanges()
        let first = cloud.fields(type: "sharedEvent")
        let feed = cloud.fields(type: "calendarFeed")
        #expect(first.count == 4)

        let same = try #require(try mia.pass(household, now: SharedCalendarFixture.now.addingTimeInterval(60)))
        // No row written is nothing sent: the engine sends only the rows a write touched.
        #expect(same.inserted == 0 && same.updated == 0 && same.deleted == 0)
        try await mia.engine.sendChanges()
        #expect(cloud.fields(type: "sharedEvent") == first)
        #expect(cloud.fields(type: "calendarFeed") == feed, "a minute on, not even the feed (CalendarPassOn.feedRefresh)")

        let later = try #require(try mia.pass(household, now: SharedCalendarFixture.now.addingTimeInterval(61 * 60)))
        #expect(later.inserted == 0 && later.updated == 0 && later.deleted == 0)
        try await mia.engine.sendChanges()
        #expect(cloud.fields(type: "sharedEvent") == first)
        #expect(cloud.fields(type: "calendarFeed") != feed, "an hour on, the feed says when")

        var events = SharedCalendarFixture.events
        events[0].title = "Soccer game"
        let result = try #require(try mia.pass(household, events: events, now: SharedCalendarFixture.now.addingTimeInterval(62 * 60)))
        #expect(result.updated == 1 && result.inserted == 0 && result.deleted == 0)
        try await mia.engine.sendChanges()
        let after = cloud.fields(type: "sharedEvent")
        #expect(after.filter { first[$0.key] != $0.value }.count == 1, "only the changed event changed")
    }

    @Test("Setting a calendar to Just me, then leaving, removes what the phone passed on, for everyone")
    func removing() async throws {
        let cloud = Cloud()
        let mia = try await Phone(cloud, build: .today)
        let household = try mia.passOnMiasCalendars([:])
        try await mia.engine.sendChanges()
        let sam = try await Phone(cloud, build: .today)
        try await sam.engine.fetchChanges()
        #expect(try sam.count("SELECT COUNT(*) FROM sharedEvent") == 4)

        let work = try #require(try mia.database.calendarSnapshot().sources.first { $0.externalId == "mia-work" })
        try mia.database.setCalendarSourceSharing(id: work.id, sharing: .justMe)
        try mia.pass(household)
        try await mia.engine.sendChanges()
        try await sam.engine.fetchChanges()
        #expect(try sam.count("SELECT COUNT(*) FROM sharedEvent") == 2)
        #expect(try sam.count("SELECT COUNT(*) FROM sharedCalendar") == 2)
        #expect(cloud.records(type: "sharedEvent").count == 2, "gone from iCloud too")

        try mia.database.withdrawCalendars(householdId: household.id)
        try await mia.engine.sendChanges()
        try await sam.engine.fetchChanges()
        #expect(try sam.count("SELECT COUNT(*) FROM calendarFeed") == 0)
        #expect(try sam.count("SELECT COUNT(*) FROM sharedEvent") == 0)
        #expect(cloud.records(type: "sharedEvent").isEmpty && cloud.records(type: "sharedCalendar").isEmpty)
    }

    @Test("Nothing is passed on before the choices have been seen on the device")
    func notBeforeChoicesSeen() async throws {
        let cloud = Cloud()
        let mia = try await Phone(cloud, build: .today)
        let household = try mia.database.createHousehold(name: "Home", people: [PersonDraft(name: "Mia", color: .coral)])
        try mia.database.saveThisDevice(ThisDevice(name: "Mia's iPhone", role: .personal, model: "iPhone"), in: household.id)
        try mia.database.syncCalendarSources(householdId: household.id, calendars: SharedCalendarFixture.calendars)
        let provider = FixedCalendarProvider(calendars: SharedCalendarFixture.calendars, events: SharedCalendarFixture.events)
        let store = CalendarStore(database: mia.database, provider: provider, now: { SharedCalendarFixture.now }, passesOn: false)
        #expect(store.passOn(.open) == nil)
        #expect(try mia.count("SELECT COUNT(*) FROM calendarFeed") == 0)
        store.choicesSeen()
        // The store hears that the choices were seen a moment later: ask until it has, for
        // ten seconds at the most, instead of trusting that a fifth of a second is enough on
        // a slow Mac.
        var result: CalendarPassResult?
        for _ in 0..<100 where result == nil {
            result = store.passOn(.open)
            if result == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(try #require(result).events == 4)
    }

    @Test("A build from before the shared calendar keeps syncing everything else, can't remove a device that passed calendars on, and gets them on updating")
    func olderBuild() async throws {
        let cloud = Cloud()
        let mia = try await Phone(cloud, build: .today)
        let household = try mia.passOnMiasCalendars([:])
        try await mia.engine.sendChanges()

        var older = try await Phone(cloud, build: .beforeCalendar)
        try await older.engine.fetchChanges()
        #expect(try older.hasTable("sharedEvent") == false)
        for type in ["calendarFeed", "sharedCalendar", "sharedEvent"] {
            #expect(try older.waiting(recordType: type) > 0, "\(type) waits in the engine's metadata")
        }
        // It still syncs the rest: a meal it logs reaches today's build.
        let journal = try older.database.ensureFoodJournal(householdId: household.id)
        let meal = MealDraft(day: DayKey(SharedCalendarFixture.now, calendar: household.calendar), slot: "Dinner", eaterIds: try older.database.snapshot().people.map(\.id), eatenAt: SharedCalendarFixture.now)
        _ = try older.database.addMeal(meal, journalId: journal.id)
        try await older.engine.sendChanges()
        try await mia.engine.fetchChanges()
        #expect(try mia.count("SELECT COUNT(*) FROM journalEntry") == 1)

        // Removing Mia's phone there: iCloud keeps a device that is still a parent.
        let deviceId = mia.database.thisDeviceId(in: household.id)
        try older.write("DELETE FROM device WHERE id = ?", deviceId)
        try await older.engine.sendChanges()
        #expect(cloud.record(deviceId, type: "device") != nil)
        #expect(cloud.records(type: "sharedEvent").count == 4)

        older = try await older.updated()
        try await older.engine.fetchChanges()
        #expect(try older.count("SELECT COUNT(*) FROM sharedEvent") == 4, "every event on the first launch, parents first")
        #expect(try older.count("SELECT COUNT(*) FROM calendarFeed") == 1)
    }
}

/// A provider with the calendars and events it is given, which it writes to in memory as
/// EventKit would, and which can change an event's shared id after it is saved.
@MainActor
final class FixedCalendarProvider: CalendarProvider {
    var store: InMemoryCalendarWrites
    var onChange: (@MainActor () -> Void)?
    var access: CalendarAccess = .granted

    init(calendars: [ExternalCalendar], events: [ExternalEvent]) {
        store = InMemoryCalendarWrites(calendars: calendars, events: events)
    }

    func requestAccess() async -> CalendarAccess { access }
    func calendars() -> [ExternalCalendar] { access == .granted ? store.calendars : [] }
    func events(in interval: DateInterval, calendarIds: Set<String>) -> [ExternalEvent] {
        store.events(in: interval, calendarIds: calendarIds)
    }

    func save(_ draft: EventDraft, span: EventSpan) throws -> (occurrenceId: String, externalItemId: String?) {
        guard access == .granted else { throw CalendarWriteError.noAccess }
        let saved = try store.save(draft, span: span)
        onChange?()
        return saved
    }

    func delete(occurrenceId: String, span: EventSpan) throws {
        try store.delete(occurrenceId: occurrenceId, span: span)
        onChange?()
    }

    func makeCalendar(title: String) throws -> ExternalCalendar {
        let made = store.makeCalendar(title: title)
        onChange?()
        return made
    }
}

// MARK: - Who an event is for, through a change of its shared id

@MainActor
@Suite("Who an event is for stays on it when the id iOS shares changes", .serialized)
struct EventForSyncTests {
    /// Mia's own soccer practice, as her phone's provider gives it, under `uid`.
    static func soccer(_ uid: String) -> [ExternalEvent] {
        var events = SharedCalendarFixture.events
        events[0].externalItemId = uid
        return events
    }

    @Test("Set on the phone that made it, \"For Sam\" follows the event when its server hands back a new id")
    func setWhereMade() async throws {
        let cloud = Cloud()
        let mia = try await Phone(cloud, build: .today)
        let household = try mia.passOnMiasCalendars([:])
        let sam = try #require(try mia.database.snapshot().people.first { $0.name == "Sam" })
        let first = try #require(CalendarPassOn.matchKey("soccer@icloud"))
        try mia.database.setEventFor(
            matchKey: first, title: "Soccer practice", start: SharedCalendarFixture.events[0].start, itemId: "own-1",
            people: [sam.id], householdId: household.id
        )
        try await mia.engine.sendChanges()

        let other = try await Phone(cloud, build: .today)
        try await other.engine.fetchChanges()
        #expect(try other.shownFromOthers(household).first { $0.title == "Soccer practice" }?.owner == .person(sam.id))

        // The server settles on another id; Mia's next pass re-keys the record.
        let settled = try #require(CalendarPassOn.matchKey("soccer@server"))
        try mia.pass(household, events: Self.soccer("soccer@server"), now: SharedCalendarFixture.now.addingTimeInterval(600))
        try await mia.engine.sendChanges()
        try await other.engine.fetchChanges()
        let records = try other.database.eventFors(householdId: household.id)
        #expect(records.map(\.matchKey) == [settled], "one record, under the new key")
        let shown = try other.shownFromOthers(household).first { $0.title == "Soccer practice" }
        #expect(shown?.matchKey == settled)
        #expect(shown?.owner == .person(sam.id), "still for Sam")
    }

    @Test("Set on another phone, \"For Sam\" follows the event when the phone that has it passes on its new id")
    func setElsewhere() async throws {
        let cloud = Cloud()
        let mia = try await Phone(cloud, build: .today)
        let household = try mia.passOnMiasCalendars([:])
        try await mia.engine.sendChanges()
        let other = try await Phone(cloud, build: .today)
        try await other.engine.fetchChanges()
        let sam = try #require(try other.database.snapshot().people.first { $0.name == "Sam" })
        let event = try #require(try other.shownFromOthers(household).first { $0.title == "Soccer practice" })
        try other.database.setEventFor(
            matchKey: try #require(event.matchKey), title: event.title, start: event.start, itemId: nil, people: [sam.id], householdId: household.id
        )
        try await other.engine.sendChanges()
        try await mia.engine.fetchChanges()

        try mia.pass(household, events: Self.soccer("soccer@server"), now: SharedCalendarFixture.now.addingTimeInterval(600))
        try await mia.engine.sendChanges()
        try await other.engine.fetchChanges()
        #expect(try other.shownFromOthers(household).first { $0.title == "Soccer practice" }?.owner == .person(sam.id))
        #expect(try other.database.eventFors(householdId: household.id).count == 1)
    }

    @Test("Before the re-key, a device that already has the new id finds the record by its title and start; a Busy only one can't, and shows its calendar's owner")
    func fallback() throws {
        let household = Household.ID.derived("h")
        let sam = Person.ID.derived("sam")
        let start = SharedCalendarFixture.events[0].start
        let record = EventFor(
            id: EventFor.id(householdId: household, matchKey: "old"), householdId: household, matchKey: "old",
            titleKey: EventFor.titleKey("Soccer practice", householdId: household), occurrenceStart: start,
            personIds: sam.description, setById: nil, setAt: .distantPast
        )
        func event(_ title: String, busy: Bool = false, start: Date = start) -> CalendarEvent {
            var event = CalendarEvent.resolve(
                ExternalEvent(id: "x", calendarId: "c", title: title, start: start, end: start.addingTimeInterval(3600), isAllDay: false),
                owner: .person(.derived("mia")), isBusy: busy, calendarTitle: "Mia"
            )
            event.matchKey = "new"
            return event
        }
        #expect(EventForLogic.apply([record], to: [event(" soccer  PRACTICE ")], householdId: household)[0].owner == .person(sam))
        #expect(EventForLogic.apply([record], to: [event("Soccer practice", start: start.addingTimeInterval(3600))], householdId: household)[0].owner == .person(.derived("mia")), "another occurrence waits for the re-key")
        var busy = record
        busy.titleKey = nil
        #expect(EventForLogic.apply([busy], to: [event("", busy: true)], householdId: household)[0].owner == .person(.derived("mia")))
        // The key is of no use outside the household.
        #expect(EventFor.titleKey("Soccer practice", householdId: household) != EventFor.titleKey("Soccer practice", householdId: .derived("other")))
    }

    @Test("A build from before the home calendar keeps syncing everything else, and gets the home calendar and every \"For\" on updating")
    func olderBuild() async throws {
        let cloud = Cloud()
        let mia = try await Phone(cloud, build: .today)
        let household = try mia.passOnMiasCalendars([:])
        let sam = try #require(try mia.database.snapshot().people.first { $0.name == "Sam" })
        try mia.database.setEventFor(
            matchKey: try #require(CalendarPassOn.matchKey("soccer@icloud")), title: "Soccer practice",
            start: SharedCalendarFixture.events[0].start, itemId: "own-1", people: [sam.id], householdId: household.id
        )
        try await mia.database.writer.write { db in
            try HomeCalendar(id: HomeCalendar.id(householdId: household.id), householdId: household.id, title: "Family",
                             accountKind: "Google", chosenById: nil, chosenAt: SharedCalendarFixture.now).insert(db)
        }
        try await mia.engine.sendChanges()

        var older = try await Phone(cloud, build: .beforeHomeCalendar)
        try await older.engine.fetchChanges()
        #expect(try older.hasTable("eventFor") == false)
        for type in ["eventFor", "homeCalendar"] {
            #expect(try older.waiting(recordType: type) == 1, "\(type) waits in the engine's metadata")
        }
        #expect(try older.count("SELECT COUNT(*) FROM sharedEvent") == 4, "and step 1 syncs as before")

        older = try await older.updated()
        try await older.engine.fetchChanges()
        #expect(try older.count("SELECT COUNT(*) FROM eventFor") == 1)
        #expect(try older.count("SELECT COUNT(*) FROM homeCalendar") == 1)
    }

    @Test("A Busy only event's record re-keys without a title, and nothing unmatched is deleted")
    func busyRekeys() async throws {
        let cloud = Cloud()
        let mia = try await Phone(cloud, build: .today)
        let household = try mia.passOnMiasCalendars(["mia-doctor": .busy])
        let sam = try #require(try mia.database.snapshot().people.first { $0.name == "Sam" })
        let doctor = SharedCalendarFixture.events[3]
        try mia.database.setEventFor(
            matchKey: try #require(CalendarPassOn.matchKey(doctor.externalItemId)), title: nil, start: doctor.start,
            itemId: "doc-1", people: [sam.id], householdId: household.id
        )
        var events = SharedCalendarFixture.events
        events[3].externalItemId = "SECRET-UID-2"
        try mia.pass(household, events: events, now: SharedCalendarFixture.now.addingTimeInterval(600))
        let records = try mia.database.eventFors(householdId: household.id)
        #expect(records.map(\.matchKey) == [CalendarPassOn.matchKey("SECRET-UID-2")])
        #expect(records.first?.titleKey == nil)
        // An event that has gone from the window keeps its record.
        try mia.pass(household, events: Array(events.prefix(3)), now: SharedCalendarFixture.now.addingTimeInterval(1200))
        #expect(try mia.database.eventFors(householdId: household.id).count == 1)
    }
}
