import Foundation
import GRDB
import Testing
@testable import Porchlight

@Suite("Sync v1 migration")
struct SyncMigrationTests {
    @Test("Every row survives with the same values, and every reference points at the same row")
    func rowByRow() throws {
        let queue = try SyncFixture.oldDatabase()
        try queue.write(SyncFixture.fill)
        let columns = try queue.read(SyncFixture.columns)
        let before = try queue.read { try SyncFixture.contents($0, columns: columns) }
        #expect(before.values.allSatisfy { !$0.isEmpty }, "the fixture fills every table")

        try SyncFixture.migrateToSyncV1(queue)
        let after = try queue.read { try SyncFixture.contents($0, columns: columns) }
        for table in SyncSchema.tables.map(\.name) {
            #expect(after[table] == before[table], "\(table)")
        }
    }

    @Test("Ids become lowercase UUID text, unique across tables, with derived ids where rows merge")
    func ids() throws {
        let queue = try SyncFixture.oldDatabase()
        try queue.write(SyncFixture.fill)
        try SyncFixture.migrateToSyncV1(queue)
        try queue.read { db in
            var seen = Set<String>()
            for table in SyncSchema.tables.map(\.name) {
                for row in try Row.fetchAll(db, sql: "SELECT typeof(id) AS type, id FROM \"\(table)\"") {
                    let id: String = row["id"]
                    #expect(row["type"] as String == "text")
                    #expect(id == id.lowercased() && UUID(uuidString: id) != nil, "\(table): \(id)")
                    #expect(seen.insert(id).inserted, "\(table): \(id) is unique")
                }
            }
            for completion in try ChoreCompletion.fetchAll(db) {
                #expect(completion.id == ChoreCompletion.id(choreId: completion.choreId, day: completion.dayKey))
            }
            for page in try JournalPage.fetchAll(db) {
                #expect(page.id == JournalPage.id(journalId: page.journalId, day: page.dayKey))
            }
            for meal in try MealPlan.fetchAll(db) {
                #expect(meal.id == MealPlan.id(householdId: meal.householdId, day: meal.dayKey))
            }
            for link in try CareLogPerson.fetchAll(db) {
                #expect(link.id == CareLogPerson.id(careLogId: link.careLogId, personId: link.personId))
            }
            for eater in try JournalEntryEater.fetchAll(db) {
                #expect(eater.id == JournalEntryEater.id(entryId: eater.entryId, personId: eater.personId))
            }
            // Cash-ins chain from the one before, in the order they happened.
            let coffee = try #require(try Reward.filter(Column("title") == "Coffee run").fetchOne(db))
            let cashIns = try RewardRedemption.filter(Column("rewardId") == coffee.id).order(Column("redeemedAt")).fetchAll(db)
            #expect(cashIns.map(\.stars) == [20, 21])
            #expect(cashIns[0].id == RewardRedemption.id(rewardId: coffee.id, after: nil))
            #expect(cashIns[1].id == RewardRedemption.id(rewardId: coffee.id, after: cashIns[0].id))
        }
    }

    @Test("Ids are fresh random UUIDs: migrating the same data twice gives different ids")
    func randomIds() throws {
        func householdId() throws -> String {
            let queue = try SyncFixture.oldDatabase()
            try queue.write(SyncFixture.fill)
            try SyncFixture.migrateToSyncV1(queue)
            return try queue.read { try String.fetchOne($0, sql: "SELECT id FROM household WHERE name = 'Lake House'") } ?? ""
        }
        #expect(try householdId() != householdId())
    }

    @Test("The upgraded database reads and writes like a new one")
    func upgradedDatabaseWorks() throws {
        let queue = try SyncFixture.oldDatabase()
        try queue.write(SyncFixture.fill)
        let db = try AppDatabase(queue)
        let snapshot = try db.snapshot()
        #expect(snapshot.household?.name == "Lake House")
        #expect(snapshot.people.map(\.name) == ["James", "Mia"])
        let james = try #require(snapshot.people.first)
        let home = try db.homeSnapshot(since: DayKey(rawValue: "2026-01-01"))
        #expect(home.chores.map(\.title) == ["Dishes", "Fix faucet"])
        #expect(home.chores.first?.ownerId == james.id)
        #expect(home.redemptions.map(\.stars) == [21, 20, 250])
        let dishes = try #require(home.chores.first)
        try db.toggleChore(id: dishes.id, day: DayKey(rawValue: "2026-01-09"), personId: nil)
        let food = try db.foodSnapshot()
        #expect(food.entries.map(\.title) == ["Pho", "Leftovers"])
        #expect(food.places.count == 2)
        let companions = try db.writer.read(CompanionSnapshot.fetch)
        #expect(companions.companions.map(\.name) == ["Yo-Yo", "Fern"])
        #expect(companions.entries.first?.people == snapshot.people.map(\.id))
    }

    @Test("Fresh installs get the same schema as upgraded ones")
    func freshMatchesUpgraded() throws {
        func schema(_ queue: DatabaseQueue) throws -> [String] {
            try queue.read { db in
                try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name")
            }
        }
        let fresh = try DatabaseQueue(configuration: AppDatabase.configuration)
        _ = try AppDatabase(fresh)
        let upgraded = try SyncFixture.oldDatabase()
        try upgraded.write(SyncFixture.fill)
        _ = try AppDatabase(upgraded)
        #expect(try schema(fresh) == schema(upgraded))
        let leftovers = try upgraded.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_temp_master WHERE type = 'table'")
        }
        #expect(leftovers.isEmpty, "the id maps are dropped")
    }

    /// Runs only with `PORCHLIGHT_REAL_DB` set to a copy of the wall's database, e.g. from
    /// scripts/backup-ipad.sh (pass it to the simulator with `TEST_RUNNER_PORCHLIGHT_REAL_DB=<path>`).
    /// It migrates a further copy of that file, never the file itself.
    @Test("A copy of the wall's real data migrates without losing anything",
          .enabled(if: ProcessInfo.processInfo.environment["PORCHLIGHT_REAL_DB"] != nil))
    func realData() throws {
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PORCHLIGHT_REAL_DB"]))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("real-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("porchlight.sqlite")
        for suffix in ["", "-wal"] {
            let file = URL(fileURLWithPath: source.path + suffix)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.copyItem(at: file, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        let queue = try DatabaseQueue(path: copy.path, configuration: AppDatabase.configuration)
        let applied = try queue.read { try AppDatabase.migrator(files: nil).appliedIdentifiers($0) }
        #expect(!applied.contains(AppDatabase.syncMigration), "the copy is from before sync v1")
        // Bring an older copy up to the last old migration first, so both sides have every table.
        try AppDatabase.migrator(files: nil).migrate(queue, upTo: SyncFixture.lastOldMigration)
        let columns = try queue.read(SyncFixture.columns)
        let before = try queue.read { SyncFixture.checksums(try SyncFixture.contents($0, columns: columns)) }

        try SyncFixture.migrateToSyncV1(queue)
        let after = try queue.read { SyncFixture.checksums(try SyncFixture.contents($0, columns: columns)) }
        for table in SyncSchema.tables.map(\.name) {
            #expect(after[table] == before[table], "\(table)")
        }
        _ = try AppDatabase(queue)
        let household = try queue.read { try Household.current($0) }
        #expect(household != nil)
    }
}

@Suite("Sync schema rules")
struct SyncSchemaRulesTests {
    /// The tree from docs/design/sync-foundation.md, with the photo tables from
    /// docs/design/sync-icloud.md: each synced table and its one parent.
    private static let tree: [String: String?] = [
        "household": nil,
        "person": "household",
        "companion": "household", "careRoutine": "companion", "careLog": "careRoutine", "careLogPerson": "careLog",
        "journal": "household", "journalEntry": "journal", "journalEntryEater": "journalEntry",
        "journalEntryPhoto": "journalEntry", "journalPage": "journal",
        "foodPlace": "household",
        "chore": "household", "choreCompletion": "chore",
        "reward": "household", "rewardRedemption": "reward",
        "homeList": "household", "listItem": "homeList",
        "mealPlan": "household",
        "companionPhoto": "companion",
        "journalEntryPhotoThumb": "journalEntryPhoto", "journalEntryPhotoImage": "journalEntryPhoto",
    ]

    /// Tables keyed by their parent's id, one row per parent, instead of an id of their own.
    private static let keyedByParent = [
        "companionPhoto": "companionId", "journalEntryPhotoThumb": "photoId", "journalEntryPhotoImage": "photoId",
    ]

    /// Tables that stay on the device and never sync.
    private static let deviceLocal: Set<String> = ["calendarSource", "ambientPhoto"]

    @Test("Every synced table has a text UUID key, no unique index and one cascading parent in the tree")
    func rules() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                """)
            #expect(Set(tables) == Set(Self.tree.keys).union(Self.deviceLocal), "every table is in the tree or device-local")
            for table in tables {
                let sql = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = ?", arguments: [table]) ?? ""
                #expect(sql.hasSuffix("STRICT"), "\(table) is STRICT")
                let key = Self.keyedByParent[table] ?? "id"
                let primaryKey = try db.primaryKey(table)
                #expect(primaryKey.columns == [key], "\(table) has one primary key, \(key)")
                let column = try #require(try db.columns(in: table).first { $0.name == key })
                #expect(column.type == "TEXT", "\(table).\(key) is text, not an integer")
                if key == "id" {
                    #expect(column.defaultValueSQL == "uuid()", "\(table).id defaults to uuid()")
                }
                guard !Self.deviceLocal.contains(table) else { continue }

                let unique = try Row.fetchAll(db, sql: "SELECT name, origin FROM pragma_index_list(?) WHERE \"unique\" = 1", arguments: [table])
                #expect(unique.allSatisfy { $0["origin"] as String == "pk" }, "\(table) has no unique constraint but its id")
                let keys = try Row.fetchAll(db, sql: "SELECT \"table\", \"from\", on_delete FROM pragma_foreign_key_list(?)", arguments: [table])
                let parent = Self.tree[table] ?? nil
                #expect(keys.count == (parent == nil ? 0 : 1), "\(table) has exactly one foreign key, to its parent")
                for foreignKey in keys {
                    #expect(foreignKey["table"] as String == parent, "\(table) hangs off \(parent ?? "nothing")")
                    #expect(foreignKey["on_delete"] as String == "CASCADE", "\(table)'s parent key cascades")
                    if key != "id" {
                        #expect(foreignKey["from"] as String == key, "\(table)'s key is its parent's id")
                    }
                }
            }
        }
    }

    @Test("The migration's table list matches the tree")
    func schemaListMatchesTree() {
        #expect(Set(SyncSchema.synced.map(\.name)) == Set(Self.tree.keys))
        for table in SyncSchema.synced {
            #expect(Self.tree[table.name] == .some(table.parent), "\(table.name)")
        }
        #expect(Set(SyncSchema.tables.filter { !$0.synced }.map(\.name)) == Self.deviceLocal)
    }
}

@Suite("Ids")
struct IDTests {
    @Test("Derived ids are stable, lowercase and depend on every part")
    func derived() {
        let one = ID<Chore>.derived("3f2b8c1e-0000-4000-8000-000000000000", "2026-11-07")
        #expect(one == ID<Chore>.derived("3f2b8c1e-0000-4000-8000-000000000000", "2026-11-07"))
        #expect(one != ID<Chore>.derived("3f2b8c1e-0000-4000-8000-000000000000", "2026-11-08"))
        #expect(one.description == one.description.lowercased())
        #expect(Array(one.description)[14] == "8", "marked as a version 8 (custom) UUID")
        // A fixed input gives a fixed id on every device and every release.
        #expect(ID<Chore>.derived("a", "b").description == ID<Chore>.derived("a", "b").description)
    }

    @Test("Ids are stored as lowercase text and only decode from text")
    func storage() throws {
        let database = try AppDatabase.inMemory()
        let household = try database.createHousehold(name: "Home", people: [PersonDraft(name: "J", color: .blue)])
        let stored = try database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT typeof(id) AS type, id FROM household")
        }
        #expect(stored?["type"] == "text")
        #expect(stored?["id"] == household.id.description)
        #expect(household.id.description == household.id.description.lowercased())
        #expect(ID<Person>.fromDatabaseValue(1.databaseValue) == nil)
        #expect(ID<Person>.fromDatabaseValue(household.id.description.uppercased().databaseValue)?.description == household.id.description)
        let decoded = try JSONDecoder().decode(ID<Person>.self, from: Data("\"\(household.id.description)\"".utf8))
        #expect(decoded.description == household.id.description)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ID<Person>.self, from: Data("1".utf8)) }
    }

    @Test("uuid() is registered on every connection, so id columns default to one")
    func uuidFunction() throws {
        let database = try AppDatabase.inMemory()
        let id = try database.writer.write { db in
            try db.execute(sql: "INSERT INTO household (name, timeZoneIdentifier, firstWeekday, createdAt) VALUES ('H', 'UTC', 1, '2026-01-01 00:00:00.000')")
            return try String.fetchOne(db, sql: "SELECT id FROM household")
        }
        let text = try #require(id)
        #expect(UUID(uuidString: text) != nil && text == text.lowercased())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uuid-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let onDisk = try AppDatabase.openOnDisk(folder: folder)
        let generated = try onDisk.writer.read { try String.fetchOne($0, sql: "SELECT uuid()") }
        #expect(generated.flatMap(UUID.init(uuidString:)) != nil)
    }
}

@Suite("Rows that merge")
struct DerivedRowTests {
    private let db: AppDatabase
    private let household: Household
    private let people: [Person]
    private let day = DayKey(rawValue: "2026-11-07")

    init() throws {
        db = try AppDatabase.inMemory()
        household = try db.createHousehold(
            name: "Home", people: [PersonDraft(name: "A", color: .blue), PersonDraft(name: "B", color: .coral)],
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        people = try db.snapshot().people
    }

    @Test("Writing the same completion twice leaves one row, with the later credit")
    func completion() throws {
        let chore = try db.saveChore(
            ChoreDraft(title: "Dishes", ownerId: nil, anchorDay: DayKey(rawValue: "2026-11-01")), householdId: household.id
        )
        // Two devices check the same chore off offline, then sync: the second write lands on the first row.
        try db.writer.write { db in
            try ChoreCompletion(choreId: chore.id, day: day, personId: people[0].id, stars: 1, completedAt: .now).upsert(db)
            try ChoreCompletion(choreId: chore.id, day: day, personId: people[1].id, stars: 1, completedAt: .now).upsert(db)
        }
        try db.creditChore(id: chore.id, day: day, personId: people[1].id)
        let completions = try db.writer.read { try ChoreCompletion.fetchAll($0) }
        #expect(completions.count == 1)
        #expect(completions.first?.personId == people[1].id)
        #expect(completions.first?.id == ChoreCompletion.id(choreId: chore.id, day: day))
    }

    @Test("A day's page and dinner are one row each, however often they are written")
    func pageAndDinner() throws {
        let journal = try db.ensureFoodJournal(householdId: household.id)
        try db.writer.write { db in
            try JournalPage(journalId: journal.id, day: day, drawing: Data([1]), updatedAt: .now).upsert(db)
            try JournalPage(journalId: journal.id, day: day, drawing: Data([2]), updatedAt: .now).upsert(db)
        }
        #expect(try db.writer.read { try JournalPage.fetchAll($0) }.map(\.drawing) == [Data([2])])
        try db.setMeal(day: day, title: "Tacos", emoji: nil, householdId: household.id)
        try db.setMeal(day: day, title: "Soup", emoji: nil, householdId: household.id)
        let meals = try db.writer.read { try MealPlan.fetchAll($0) }
        #expect(meals.map(\.title) == ["Soup"])
        #expect(meals.first?.id == MealPlan.id(householdId: household.id, day: day))
    }

    @Test("The same person credited twice on a walk or a meal is one row")
    func joinRows() throws {
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        let companion = try db.saveCompanion(draft, householdId: household.id)
        let routine = try #require(try db.writer.read(CompanionSnapshot.fetch).routines(of: companion).first)
        let log = try db.logCare(routineId: routine.id, CareLogDraft(people: [people[0].id], occurredAt: .now.addingTimeInterval(-60)))
        try db.writer.write { db in try CareLogPerson(careLogId: log.id, personId: people[0].id).upsert(db) }
        #expect(try db.writer.read { try CareLogPerson.fetchCount($0) } == 1)

        let journal = try db.ensureFoodJournal(householdId: household.id)
        let meal = try db.addMeal(
            MealDraft(day: day, slot: "Lunch", title: "Pho", eaterIds: [people[0].id], eatenAt: .now), journalId: journal.id
        )
        try db.writer.write { db in try JournalEntryEater(entryId: meal.id, personId: people[0].id).upsert(db) }
        #expect(try db.writer.read { try JournalEntryEater.fetchCount($0) } == 1)
    }

    @Test("Cashing in the same round on two devices writes the same row")
    func cashIn() throws {
        let reward = try db.saveReward(
            RewardDraft(title: "Treat", targetStars: 1, ownerId: people[0].id), householdId: household.id, today: day
        )
        let first = try db.cashInReward(id: reward.id, stars: 3, day: day)
        // The other device hadn't seen this cash-in, so it cashed in the same round: same id.
        #expect(first.id == RewardRedemption.id(rewardId: reward.id, after: nil))
        #expect(throws: HomeValidationError.alreadyCashedIn) { try db.cashInReward(id: reward.id, stars: 3, day: day) }
        // The next round, even on the same day, is a new row.
        let second = try db.cashInReward(id: reward.id, stars: 2, day: day, after: first.id)
        #expect(second.id == RewardRedemption.id(rewardId: reward.id, after: first.id))
        #expect(second.id != first.id)
        #expect(try db.writer.read { try RewardRedemption.fetchCount($0) } == 2)
    }
}

@Suite("Dangling references")
struct DanglingReferenceTests {
    @Test("Ids that point at nobody read fine and show no one")
    func dangling() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "A", color: .blue)])
        let nobody = Person.ID.new()
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        let companion = try db.saveCompanion(draft, householdId: household.id)
        let routine = try #require(try db.writer.read(CompanionSnapshot.fetch).routines(of: companion).first)
        let log = try db.logCare(routineId: routine.id, CareLogDraft(people: [try db.snapshot().people[0].id], occurredAt: .now.addingTimeInterval(-60)))
        let journal = try db.ensureFoodJournal(householdId: household.id)
        let meal = try db.addMeal(
            MealDraft(day: DayKey(.now, calendar: household.calendar), slot: "Lunch", title: "Pho", eaterIds: [try db.snapshot().people[0].id], eatenAt: .now),
            journalId: journal.id
        )
        // A sync can deliver rows before the person or place they name.
        try db.writer.write { db in
            try CareLogPerson(careLogId: log.id, personId: nobody).insert(db)
            try JournalEntryEater(entryId: meal.id, personId: nobody).insert(db)
            try db.execute(sql: "UPDATE journalEntry SET placeId = ?", arguments: [FoodPlace.ID.new()])
            try db.execute(sql: """
                INSERT INTO chore (id, householdId, title, ownerId, repeatKind, anchorDay, stars, sortOrder, createdAt)
                VALUES (?, ?, 'Dishes', ?, 'daily', '2026-01-01', 1, 0, '2026-01-01 00:00:00.000')
                """, arguments: [Chore.ID.new(), household.id, nobody])
        }

        let companions = try db.writer.read(CompanionSnapshot.fetch)
        #expect(companions.person(nobody) == nil)
        #expect(companions.entries.first?.people.contains(nobody) == true)
        let report = try #require(CompanionReport.make(snapshot: companions, companionId: companion, now: .now))
        #expect(!report.diary.isEmpty)
        #expect(CaptionEngine.whoText([nobody], names: companions.names) == "Someone")

        let food = try db.foodSnapshot()
        #expect(food.everyone.person(nobody) == nil)
        #expect(food.entries.first?.placeId != nil)

        let home = try db.homeSnapshot(since: DayKey(rawValue: "2026-01-01"))
        let board = ChoreBoard(
            people: home.people, chores: home.chores, completions: home.completions, earnings: home.earnings,
            rewards: home.rewards, today: DayKey(rawValue: "2026-01-02"), calendar: household.calendar
        )
        #expect(board.columns.count == 1)
        #expect(home.lifetimeStars[nobody] == 2)
    }
}

@Suite("Safety copy before sync v1")
struct SafetyCopyTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("An existing database is copied, as it was, before it migrates; once only")
    func copiesOldDatabase() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("porchlight.sqlite")
        do {
            let pool = try DatabasePool(path: url.path, configuration: AppDatabase.configuration)
            try AppDatabase.migrator(files: nil).migrate(pool, upTo: SyncFixture.lastOldMigration)
            try pool.write(SyncFixture.fill)
        }

        let database = try AppDatabase.openOnDisk(folder: folder)
        let copy = AppDatabase.copyBeforeSyncURL(next: url)
        let saved = try DatabaseQueue(path: copy.path)
        let (applied, householdId) = try saved.read { db in
            (try AppDatabase.migrator(files: nil).appliedIdentifiers(db), try Int.fetchOne(db, sql: "SELECT id FROM household WHERE name = 'Lake House'"))
        }
        #expect(!applied.contains(AppDatabase.syncMigration))
        #expect(householdId == 7, "the copy holds the old integer ids")
        #expect(try database.snapshot().household?.name == "Lake House")

        // Later launches leave the copy alone: the database has already migrated.
        try FileManager.default.removeItem(at: copy)
        _ = try AppDatabase.openOnDisk(folder: folder)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    @Test("A fresh install makes no copy")
    func freshInstall() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try AppDatabase.openOnDisk(folder: folder)
        let copy = AppDatabase.copyBeforeSyncURL(next: folder.appendingPathComponent("porchlight.sqlite"))
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }
}
