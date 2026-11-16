import Foundation
import GRDB

/// The app's single SQLite database. Owns the schema and every write.
///
/// All reads and writes go through this type so the schema, validation and
/// transactions live in one place. It is `Sendable` and safe to share.
struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The on-device database in Application Support.
    static func openOnDisk(folder: URL = AppFiles.root, fileManager: FileManager = .default) throws -> AppDatabase {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("porchlight.sqlite")
        let exists = fileManager.fileExists(atPath: url.path)
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        if exists {
            try keepCopyBeforeSync(pool, at: url, fileManager: fileManager)
        }
        return try AppDatabase(pool)
    }

    /// An empty in-memory database, for tests and previews.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    /// The settings every connection opens with, on disk or in memory.
    static var configuration: Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in db.addUUIDFunction() }
        return config
    }

    /// The copy of the database kept from before "sync v1" rebuilt every table, in case
    /// it ever needs to be recovered. Removed once sync has proven itself (M1's gate).
    static func copyBeforeSyncURL(next database: URL) -> URL {
        database.deletingLastPathComponent().appendingPathComponent("porchlight-before-sync-v1.sqlite")
    }

    /// Copies an existing database that hasn't run "sync v1" yet, before it does.
    /// The WAL is checkpointed into the main file first, so the one file is complete.
    private static func keepCopyBeforeSync(_ pool: DatabasePool, at url: URL, fileManager: FileManager) throws {
        let applied = try pool.read { try migrator.appliedIdentifiers($0) }
        guard !applied.isEmpty, !applied.contains(syncMigration) else { return }
        try pool.writeWithoutTransaction { _ = try $0.checkpoint(.truncate) }
        let copy = copyBeforeSyncURL(next: url)
        // A copy left by a launch whose migration failed holds the same, unmigrated data.
        if fileManager.fileExists(atPath: copy.path) {
            try fileManager.removeItem(at: copy)
        }
        try fileManager.copyItem(at: url, to: copy)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1: household and people") { db in
            try db.create(table: "household") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("timeZoneIdentifier", .text).notNull()
                t.column("firstWeekday", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "person") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("household", onDelete: .cascade).notNull()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2: setup completion") { db in
            // Households created before this step had already finished setup.
            try db.alter(table: "household") { t in
                t.add(column: "setupCompleted", .boolean).notNull().defaults(to: true)
            }
        }

        // Feature schemas, always registered in this order.
        registerCalendarMigrations(&migrator)
        registerCompanionMigrations(&migrator)
        registerFoodMigrations(&migrator)
        registerHomeMigrations(&migrator)
        // Always last among the schemas above: it rebuilds every one of their tables.
        registerSyncMigrations(&migrator)
        return migrator
    }
}

// MARK: - Errors

enum ValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case nameTooLong(limit: Int)
    case noPeople

    var errorDescription: String? {
        switch self {
        case .emptyName: "Please enter a name."
        case let .nameTooLong(limit): "Names can be at most \(limit) characters."
        case .noPeople: "Add at least one person."
        }
    }
}

enum Names {
    static let limit = 40

    /// Trims whitespace and checks the length rules shared by every name in the app.
    static func validated(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.emptyName }
        guard name.count <= limit else { throw ValidationError.nameTooLong(limit: limit) }
        return name
    }
}

// MARK: - Household writes

struct PersonDraft: Equatable, Sendable {
    var name: String
    var color: PersonColor
}

extension AppDatabase {
    /// Creates the household and its first people in one transaction.
    @discardableResult
    func createHousehold(
        name: String,
        people drafts: [PersonDraft],
        timeZone: TimeZone = .current,
        calendar: Calendar = .current,
        now: Date = .now
    ) throws -> Household {
        let householdName = try Names.validated(name)
        let peopleNames = try drafts.map { try Names.validated($0.name) }
        guard !drafts.isEmpty else { throw ValidationError.noPeople }

        return try writer.write { db in
            let household = Household(
                name: householdName,
                timeZoneIdentifier: timeZone.identifier,
                firstWeekday: calendar.firstWeekday,
                setupCompleted: false,
                createdAt: now
            )
            try household.insert(db)
            for (index, draft) in drafts.enumerated() {
                let person = Person(
                    householdId: household.id,
                    name: peopleNames[index],
                    color: draft.color,
                    sortOrder: index,
                    createdAt: now
                )
                try person.insert(db)
            }
            return household
        }
    }

    func markSetupCompleted(householdId: Household.ID) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE household SET setupCompleted = 1 WHERE id = ?", arguments: [householdId])
        }
    }

    func renameHousehold(id: Household.ID, to newName: String) throws {
        let name = try Names.validated(newName)
        try writer.write { db in
            guard var household = try Household.fetchOne(db, id: id) else { return }
            household.name = name
            try household.update(db)
        }
    }

    @discardableResult
    func addPerson(_ draft: PersonDraft, to householdId: Household.ID, now: Date = .now) throws -> Person {
        let name = try Names.validated(draft.name)
        return try writer.write { db in
            let nextOrder = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sortOrder) + 1, 0) FROM person WHERE householdId = ? AND archivedAt IS NULL",
                arguments: [householdId]
            ) ?? 0
            let person = Person(householdId: householdId, name: name, color: draft.color, sortOrder: nextOrder, createdAt: now)
            try person.insert(db)
            return person
        }
    }

    func updatePerson(id: Person.ID, name newName: String, color: PersonColor) throws {
        let name = try Names.validated(newName)
        try writer.write { db in
            guard var person = try Person.fetchOne(db, id: id) else { return }
            person.name = name
            person.color = color
            try person.update(db)
        }
    }

    /// Removes a person from the household by archiving them: people are never deleted,
    /// so past logs, meals, completions and cash-ins keep their name.
    ///
    /// Their chores become "Anyone", the rewards they owned are archived, and their
    /// calendars belong to everyone. The last active person cannot be removed, so the
    /// household always has someone to credit.
    func archivePerson(id: Person.ID, now: Date = .now) throws {
        try writer.write { db in
            guard var person = try Person.fetchOne(db, id: id), !person.isArchived else { return }
            let active = try Person.active(in: person.householdId).fetchCount(db)
            guard active > 1 else { throw ValidationError.noPeople }
            person.archivedAt = now
            try person.update(db)
            let arguments: StatementArguments = [id, person.householdId]
            try db.execute(sql: "UPDATE chore SET ownerId = NULL WHERE ownerId = ? AND householdId = ?", arguments: arguments)
            try db.execute(sql: "UPDATE reward SET archived = 1 WHERE ownerId = ? AND householdId = ?", arguments: arguments)
            try db.execute(sql: "UPDATE calendarSource SET ownerId = NULL WHERE ownerId = ? AND householdId = ?", arguments: arguments)
            try Self.renumber(db, householdId: person.householdId)
        }
    }

    /// Persists a new order, given the person ids in display order.
    func reorderPeople(householdId: Household.ID, ids: [Person.ID]) throws {
        try writer.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE person SET sortOrder = ? WHERE id = ? AND householdId = ?",
                    arguments: [index, id, householdId]
                )
            }
        }
    }

    private static func renumber(_ db: Database, householdId: Household.ID) throws {
        let people = try Person.active(in: householdId).fetchAll(db)
        for (index, var person) in people.enumerated() where person.sortOrder != index {
            person.sortOrder = index
            try person.update(db)
        }
    }
}

// MARK: - Reads

extension Household {
    /// The household this display belongs to: the only one, for now.
    static func current(_ db: Database) throws -> Household? {
        try Household.order(Column("createdAt"), Column("id")).fetchOne(db)
    }
}

extension Person {
    /// The household's people who haven't been removed, in display order.
    static func active(in householdId: Household.ID) -> QueryInterfaceRequest<Person> {
        everyone(in: householdId).filter(Column("archivedAt") == nil)
    }

    /// Everyone who ever lived here, removed people included, in display order.
    static func everyone(in householdId: Household.ID) -> QueryInterfaceRequest<Person> {
        Person
            .filter(Column("householdId") == householdId)
            .order(Column("sortOrder"), Column("createdAt"), Column("id"))
    }
}

extension Array where Element == Person {
    /// The person with this id, or nil when it points at nobody (yet): a sync can deliver
    /// a row before the person it names.
    func person(_ id: Person.ID?) -> Person? {
        guard let id else { return nil }
        return first { $0.id == id }
    }

    /// The people who haven't been removed.
    var active: [Person] { filter { !$0.isArchived } }
}

/// Everything the wall needs about who lives here, read in one consistent snapshot.
struct HouseholdSnapshot: Equatable, Sendable {
    var household: Household?
    /// The people who live here now, for pickers and lists.
    var people: [Person]
    /// Everyone, removed people included, for showing who did something in the past.
    var everyone: [Person]

    static let empty = HouseholdSnapshot(household: nil, people: [], everyone: [])

    static func fetch(_ db: Database) throws -> HouseholdSnapshot {
        guard let household = try Household.current(db) else { return .empty }
        let everyone = try Person.everyone(in: household.id).fetchAll(db)
        return HouseholdSnapshot(household: household, people: everyone.active, everyone: everyone)
    }
}

extension AppDatabase {
    func snapshot() throws -> HouseholdSnapshot {
        try writer.read(HouseholdSnapshot.fetch)
    }

    /// Emits a new snapshot every time the household or its people change.
    func householdUpdates() -> AsyncValueObservation<HouseholdSnapshot> {
        ValueObservation
            .tracking(HouseholdSnapshot.fetch)
            .removeDuplicates()
            .values(in: writer)
    }
}
