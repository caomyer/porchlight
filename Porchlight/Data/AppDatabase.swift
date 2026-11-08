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
    static func openOnDisk(fileManager: FileManager = .default) throws -> AppDatabase {
        let folder = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Porchlight", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("porchlight.sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabasePool(path: url.path, configuration: config))
    }

    /// An empty in-memory database, for tests and previews.
    static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabaseQueue(configuration: config))
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
            var household = Household(
                name: householdName,
                timeZoneIdentifier: timeZone.identifier,
                firstWeekday: calendar.firstWeekday,
                createdAt: now
            )
            try household.insert(db)
            for (index, draft) in drafts.enumerated() {
                var person = Person(
                    householdId: household.id!,
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

    func renameHousehold(id: Int64, to newName: String) throws {
        let name = try Names.validated(newName)
        try writer.write { db in
            guard var household = try Household.fetchOne(db, id: id) else { return }
            household.name = name
            try household.update(db)
        }
    }

    @discardableResult
    func addPerson(_ draft: PersonDraft, to householdId: Int64, now: Date = .now) throws -> Person {
        let name = try Names.validated(draft.name)
        return try writer.write { db in
            let nextOrder = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sortOrder) + 1, 0) FROM person WHERE householdId = ?",
                arguments: [householdId]
            ) ?? 0
            var person = Person(householdId: householdId, name: name, color: draft.color, sortOrder: nextOrder, createdAt: now)
            try person.insert(db)
            return person
        }
    }

    func updatePerson(id: Int64, name newName: String, color: PersonColor) throws {
        let name = try Names.validated(newName)
        try writer.write { db in
            guard var person = try Person.fetchOne(db, id: id) else { return }
            person.name = name
            person.color = color
            try person.update(db)
        }
    }

    /// Removes a person. The last remaining person cannot be removed, so the
    /// household always has someone to credit.
    func deletePerson(id: Int64) throws {
        try writer.write { db in
            guard let person = try Person.fetchOne(db, id: id) else { return }
            let count = try Person.filter(Column("householdId") == person.householdId).fetchCount(db)
            guard count > 1 else { throw ValidationError.noPeople }
            _ = try Person.deleteOne(db, id: id)
            try Self.renumber(db, householdId: person.householdId)
        }
    }

    /// Persists a new order, given the person ids in display order.
    func reorderPeople(householdId: Int64, ids: [Int64]) throws {
        try writer.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE person SET sortOrder = ? WHERE id = ? AND householdId = ?",
                    arguments: [index, id, householdId]
                )
            }
        }
    }

    private static func renumber(_ db: Database, householdId: Int64) throws {
        let people = try Person
            .filter(Column("householdId") == householdId)
            .order(Column("sortOrder"), Column("id"))
            .fetchAll(db)
        for (index, var person) in people.enumerated() where person.sortOrder != index {
            person.sortOrder = index
            try person.update(db)
        }
    }
}

// MARK: - Reads

/// Everything the wall needs about who lives here, read in one consistent snapshot.
struct HouseholdSnapshot: Equatable, Sendable {
    var household: Household?
    var people: [Person]

    static let empty = HouseholdSnapshot(household: nil, people: [])

    static func fetch(_ db: Database) throws -> HouseholdSnapshot {
        guard let household = try Household.order(Column("id")).fetchOne(db) else { return .empty }
        let people = try Person
            .filter(Column("householdId") == household.id)
            .order(Column("sortOrder"), Column("id"))
            .fetchAll(db)
        return HouseholdSnapshot(household: household, people: people)
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
