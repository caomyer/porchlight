import Foundation
import GRDB

extension AppDatabase {
    static let syncMigration = "sync v1: sync-ready ids"

    /// Moves every table to the shape iCloud sync needs (docs/design/sync-foundation.md):
    /// text UUID ids, one parent foreign key per synced table, and no unique constraints
    /// on them. Like every migration from here on, it uses raw SQL and rows only.
    static func registerSyncMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(syncMigration) { db in
            try SyncV1(db: db).run()
        }
    }
}

/// The "sync v1" rebuild. Integer ids map to fresh random UUIDs (never derived from the
/// integer, so two households migrated from old installs can't share an id), then each
/// table is rebuilt, parents first, with its ids and references translated.
///
/// GRDB runs it in one transaction with foreign keys off until the end, so dropping and
/// renaming tables cascades nothing, and any failure leaves the database as it was.
private struct SyncV1 {
    let db: Database

    /// How one table's rows are copied: the old columns to keep, which of them hold an
    /// integer id to translate (and through which table's map), and, for tables whose
    /// id is now derived, how to compute it from the translated row.
    private struct Copy {
        var columns: [String]
        var ids: [String: String]
        var order = "t.rowid"
        var derive: ((Row) throws -> String)?
    }

    /// Tables whose integer ids become random UUIDs, each with a map from old to new.
    private static let mapped = [
        "household", "person", "calendarSource", "companion", "careRoutine", "careLog",
        "journal", "foodPlace", "journalEntry", "journalEntryPhoto",
        "chore", "reward", "homeList", "listItem", "ambientPhoto",
    ]

    func run() throws {
        // The id defaults and maps need `uuid()`; register it here too, so the migration
        // never depends on how the connection was opened.
        db.addUUIDFunction()
        for table in Self.mapped {
            try db.execute(sql: "CREATE TEMP TABLE \"map_\(table)\" (old INTEGER PRIMARY KEY, new TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO \"map_\(table)\" SELECT id, uuid() FROM \"\(table)\"")
        }
        for table in SyncSchema.tables {
            try db.execute(sql: "CREATE TABLE \"new_\(table.name)\" (\(table.columns)) STRICT")
            try copy(table.name, rule(for: table.name))
            try db.execute(sql: "DROP TABLE \"\(table.name)\"")
            try db.execute(sql: "ALTER TABLE \"new_\(table.name)\" RENAME TO \"\(table.name)\"")
        }
        for index in SyncSchema.indexes {
            try db.execute(sql: index)
        }
        for table in Self.mapped {
            try db.execute(sql: "DROP TABLE \"map_\(table)\"")
        }
        try db.checkForeignKeys()
    }

    private func rule(for table: String) throws -> Copy {
        switch table {
        case "household":
            return Copy(columns: ["id", "name", "timeZoneIdentifier", "firstWeekday", "createdAt", "setupCompleted"], ids: ["id": table])
        case "person":
            return Copy(columns: ["id", "householdId", "name", "color", "sortOrder", "createdAt"], ids: ["id": table, "householdId": "household"])
        case "calendarSource":
            return Copy(
                columns: ["id", "householdId", "externalId", "title", "account", "colorHex", "ownerId", "visibility", "isShown", "createdAt"],
                ids: ["id": table, "householdId": "household", "ownerId": "person"]
            )
        case "companion":
            return Copy(
                columns: ["id", "householdId", "name", "species", "coat", "photoFile", "about", "birthDate", "captionTone", "sortOrder", "createdAt"],
                ids: ["id": table, "householdId": "household"]
            )
        case "careRoutine":
            return Copy(
                columns: [
                    "id", "companionId", "kind", "title", "emoji", "everyDays", "windows", "trackedFields", "stars",
                    "nudgeAfterMinutes", "sortOrder", "repeatKind", "weekdayMask", "anchorDay",
                ],
                ids: ["id": table, "companionId": "companion"]
            )
        case "careLog":
            return Copy(
                columns: ["id", "careRoutineId", "occurredAt", "durationMinutes", "pee", "poo", "vibe", "note", "stars", "createdAt"],
                ids: ["id": table, "careRoutineId": "careRoutine"]
            )
        case "careLogPerson":
            return Copy(columns: ["careLogId", "personId"], ids: ["careLogId": "careLog", "personId": "person"]) { row in
                CareLogPerson.id(careLogId: try id(row, "careLogId"), personId: try id(row, "personId")).description
            }
        case "journal":
            return Copy(columns: ["id", "householdId", "kind", "title", "enabled", "slots", "createdAt"], ids: ["id": table, "householdId": "household"])
        case "foodPlace":
            return Copy(
                columns: ["id", "householdId", "name", "address", "latitude", "longitude", "category", "phone", "url", "mapsId", "createdAt"],
                ids: ["id": table, "householdId": "household"]
            )
        case "journalEntry":
            return Copy(
                columns: ["id", "journalId", "day", "slot", "source", "title", "emoji", "tint", "rating", "eatenAt", "createdAt", "placeId"],
                ids: ["id": table, "journalId": "journal", "placeId": "foodPlace"]
            )
        case "journalEntryEater":
            return Copy(columns: ["entryId", "personId"], ids: ["entryId": "journalEntry", "personId": "person"]) { row in
                JournalEntryEater.id(entryId: try id(row, "entryId"), personId: try id(row, "personId")).description
            }
        case "journalEntryPhoto":
            return Copy(
                columns: ["id", "entryId", "photoFile", "thumbnailFile", "sortOrder", "createdAt", "cropX", "cropY", "cropWidth", "cropHeight"],
                ids: ["id": table, "entryId": "journalEntry"]
            )
        case "journalPage":
            return Copy(columns: ["journalId", "day", "drawing", "updatedAt"], ids: ["journalId": "journal"]) { row in
                JournalPage.id(journalId: try id(row, "journalId"), day: DayKey(rawValue: row["day"])).description
            }
        case "chore":
            return Copy(
                columns: [
                    "id", "householdId", "title", "emoji", "ownerId", "repeatKind", "weekdayMask", "intervalDays", "anchorDay",
                    "timeHint", "stars", "archived", "sortOrder", "createdAt",
                ],
                ids: ["id": table, "householdId": "household", "ownerId": "person"]
            )
        case "choreCompletion":
            return Copy(columns: ["choreId", "day", "personId", "stars", "completedAt"], ids: ["choreId": "chore", "personId": "person"]) { row in
                ChoreCompletion.id(choreId: try id(row, "choreId"), day: DayKey(rawValue: row["day"])).description
            }
        case "reward":
            return Copy(
                columns: ["id", "householdId", "title", "emoji", "targetStars", "ownerId", "startDay", "archived", "sortOrder", "createdAt"],
                ids: ["id": table, "householdId": "household", "ownerId": "person"]
            )
        case "rewardRedemption":
            // Each cash-in's id follows from the one before it, in the order they happened.
            var previous: [Reward.ID: RewardRedemption.ID] = [:]
            return Copy(
                columns: ["rewardId", "personId", "stars", "day", "redeemedAt"],
                ids: ["rewardId": "reward", "personId": "person"],
                order: "t.rewardId, t.id"
            ) { row in
                let rewardId: Reward.ID = try id(row, "rewardId")
                let redemption = RewardRedemption.id(rewardId: rewardId, after: previous[rewardId])
                previous[rewardId] = redemption
                return redemption.description
            }
        case "homeList":
            return Copy(columns: ["id", "householdId", "title", "kind", "sortOrder", "createdAt"], ids: ["id": table, "householdId": "household"])
        case "listItem":
            return Copy(
                columns: ["id", "listId", "title", "section", "addedById", "checked", "sortOrder", "createdAt"],
                ids: ["id": table, "listId": "homeList", "addedById": "person"]
            )
        case "mealPlan":
            return Copy(columns: ["householdId", "day", "title", "emoji"], ids: ["householdId": "household"]) { row in
                MealPlan.id(householdId: try id(row, "householdId"), day: DayKey(rawValue: row["day"])).description
            }
        case "ambientPhoto":
            return Copy(columns: ["id", "householdId", "fileName", "caption", "createdAt"], ids: ["id": table, "householdId": "household"])
        default:
            throw DatabaseError(message: "sync v1 has no copy rule for \(table)")
        }
    }

    // MARK: Copying

    private func copy(_ table: String, _ rule: Copy) throws {
        // A translated id comes from its map. NULL stays NULL; an id missing from the map
        // becomes NULL too, which a NOT NULL column then refuses, failing the migration.
        let values = rule.columns.map { column in
            rule.ids[column].map { "(SELECT new FROM \"map_\($0)\" WHERE old = t.\"\(column)\")" } ?? "t.\"\(column)\""
        }
        let columns = rule.columns.map { "\"\($0)\"" }
        guard let derive = rule.derive else {
            try db.execute(sql: """
                INSERT INTO "new_\(table)" (\(columns.joined(separator: ", ")))
                SELECT \(values.joined(separator: ", ")) FROM "\(table)" t
                """)
            return
        }
        let select = zip(values, columns).map { "\($0) AS \($1)" }.joined(separator: ", ")
        let rows = try Row.fetchAll(db, sql: "SELECT \(select) FROM \"\(table)\" t ORDER BY \(rule.order)")
        let placeholders = Array(repeating: "?", count: columns.count + 1).joined(separator: ", ")
        let insert = try db.makeStatement(sql: """
            INSERT INTO "new_\(table)" ("id", \(columns.joined(separator: ", "))) VALUES (\(placeholders))
            """)
        for row in rows {
            let values = [try derive(row).databaseValue] + rule.columns.map { row[$0] as DatabaseValue }
            try insert.execute(arguments: StatementArguments(values))
        }
    }
}

private func id<Entity>(_ row: Row, _ column: String) throws -> ID<Entity> {
    guard let text: String = row[column], let id = ID<Entity>(text) else {
        throw DatabaseError(message: "sync v1: \(column) has no translated id")
    }
    return id
}
