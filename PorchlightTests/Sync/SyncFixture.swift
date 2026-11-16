import CryptoKit
import Foundation
import GRDB
@testable import Porchlight

/// Helpers for the "sync v1" tests: an old-schema database, and a way to compare a
/// database's contents before and after its ids change.
enum SyncFixture {
    /// The last migration before "sync v1".
    static let lastOldMigration = "home v2: reward cash-ins"

    /// A database migrated only up to the old schema, opened like the app opens one.
    static func oldDatabase(path: String? = nil) throws -> DatabaseQueue {
        let queue = try path.map { try DatabaseQueue(path: $0, configuration: AppDatabase.configuration) }
            ?? DatabaseQueue(configuration: AppDatabase.configuration)
        try AppDatabase.migrator.migrate(queue, upTo: lastOldMigration)
        return queue
    }

    /// Which table each reference column points at, in the old schema and the new.
    static let references: [String: String] = [
        "householdId": "household", "personId": "person", "ownerId": "person", "addedById": "person",
        "companionId": "companion", "careRoutineId": "careRoutine", "careLogId": "careLog",
        "journalId": "journal", "entryId": "journalEntry", "placeId": "foodPlace",
        "choreId": "chore", "rewardId": "reward", "listId": "homeList",
    ]

    /// The columns of every table except `id`, read from a database before it migrates,
    /// so the comparison after covers exactly what was there.
    static func columns(_ db: Database) throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        for table in SyncSchema.tables.map(\.name) {
            result[table] = try db.columns(in: table).map(\.name).filter { $0 != "id" }
        }
        return result
    }

    /// Every row of every table, as text: its values, with each reference replaced by
    /// the description of the row it points at. Ids themselves never appear, so the
    /// result is the same before and after ids change if and only if every row kept its
    /// values and every reference still points at the same row.
    static func contents(_ db: Database, columns: [String: [String]]) throws -> [String: [String]] {
        var rows: [String: [String: [String: String]]] = [:]
        var order: [String: [String]] = [:]
        for (table, names) in columns {
            let hasId = try db.columns(in: table).contains { $0.name == "id" }
            let selects = names.map { name in
                references[name] != nil ? "CAST(\"\(name)\" AS TEXT) AS \"\(name)\"" : "quote(\"\(name)\") AS \"\(name)\""
            }
            let key = hasId ? "CAST(id AS TEXT)" : "CAST(rowid AS TEXT)"
            let fetched = try Row.fetchAll(db, sql: "SELECT \(key) AS __key, \(selects.joined(separator: ", ")) FROM \"\(table)\"")
            for row in fetched {
                let key: String = row["__key"]
                rows[table, default: [:]][key] = Dictionary(uniqueKeysWithValues: names.map { ($0, (row[$0] as String?) ?? "NULL") })
                order[table, default: []].append(key)
            }
        }
        var memo: [String: String] = [:]
        func describe(_ table: String, _ key: String) -> String {
            let memoKey = table + "#" + key
            if let known = memo[memoKey] { return known }
            guard let row = rows[table]?[key] else { return "<missing \(table)>" }
            let text = columns[table, default: []].map { name -> String in
                let value = row[name] ?? "NULL"
                guard let target = references[name], value != "NULL" else { return "\(name)=\(value)" }
                return "\(name)->(\(describe(target, value)))"
            }.joined(separator: ", ")
            memo[memoKey] = text
            return text
        }
        return Dictionary(uniqueKeysWithValues: columns.keys.map { table in
            (table, (order[table] ?? []).map { describe(table, $0) }.sorted())
        })
    }

    /// Row counts and a checksum of each table's contents (see `contents`).
    static func checksums(_ contents: [String: [String]]) -> [String: String] {
        contents.mapValues { rows in
            let digest = SHA256.hash(data: Data(rows.joined(separator: "\n").utf8))
            return "\(rows.count) rows, " + digest.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Fills every old table: nulls, join rows, an archived chore, two households, two
    /// cash-ins of one reward on one day, the same day planned in both households.
    static func fill(_ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO household (id, name, timeZoneIdentifier, firstWeekday, createdAt, setupCompleted) VALUES
              (7, 'Lake House', 'America/Los_Angeles', 1, '2026-01-01 08:00:00.000', 1),
              (9, 'City Flat', 'Europe/Berlin', 2, '2026-02-01 08:00:00.000', 0);
            INSERT INTO person (id, householdId, name, color, sortOrder, createdAt) VALUES
              (3, 7, 'James', 'blue', 0, '2026-01-01 08:00:00.000'),
              (5, 7, 'Mia', 'coral', 1, '2026-01-01 08:00:00.000'),
              (8, 9, 'Zed', 'sage', 0, '2026-02-01 08:00:00.000');
            INSERT INTO calendarSource (id, householdId, externalId, title, account, colorHex, ownerId, visibility, isShown, createdAt) VALUES
              (1, 7, 'ext-mia', 'Mia', 'iCloud', 16711680, 5, 'busy', 0, '2026-01-02 08:00:00.000'),
              (2, 7, 'ext-home', 'Home', 'Google · a@b.c', 255, NULL, 'full', 1, '2026-01-02 08:00:00.000');
            INSERT INTO companion (id, householdId, name, species, coat, photoFile, about, birthDate, captionTone, sortOrder, createdAt) VALUES
              (4, 7, 'Yo-Yo', 'dog', 'honey', 'yoyo.jpg', 'Toy poodle', '2021-05-04 00:00:00.000', 'cheeky', 0, '2026-01-03 08:00:00.000'),
              (6, 7, 'Fern', 'plant', 'cocoa', NULL, '', NULL, 'off', 1, '2026-01-03 09:00:00.000');
            INSERT INTO careRoutine (id, companionId, kind, title, emoji, everyDays, windows, trackedFields, stars, nudgeAfterMinutes,
                                     sortOrder, repeatKind, weekdayMask, anchorDay) VALUES
              (11, 4, 'walk', 'Walk', '🦮', 1, '[{"label":"Morning","start":360,"end":600}]', '["duration","pee"]', 2, 60, 0, 'daily', 0, '2026-01-03'),
              (12, 6, 'water', 'Water', '💧', 3, '[]', '[]', 1, NULL, 0, 'interval', 0, '');
            INSERT INTO careLog (id, careRoutineId, occurredAt, durationMinutes, pee, poo, vibe, note, stars, createdAt) VALUES
              (21, 11, '2026-01-04 07:30:00.000', 25, 1, 0, 'squirrel', 'Muddy', 2, '2026-01-04 07:55:00.000'),
              (22, 11, '2026-01-05 07:30:00.000', NULL, NULL, NULL, NULL, NULL, 2, '2026-01-05 07:31:00.000'),
              (23, 12, '2026-01-06 09:00:00.000', NULL, NULL, NULL, NULL, NULL, 1, '2026-01-06 09:00:00.000');
            INSERT INTO careLogPerson (careLogId, personId) VALUES (21, 3), (21, 5), (22, 5), (23, 3);
            INSERT INTO journal (id, householdId, kind, title, enabled, slots, createdAt) VALUES
              (2, 7, 'food', 'Food diary', 1, '["Breakfast","Lunch","Dinner"]', '2026-01-01 08:00:00.000'),
              (3, 9, 'food', 'Food diary', 0, '["Dinner"]', '2026-02-01 08:00:00.000');
            INSERT INTO foodPlace (id, householdId, name, address, latitude, longitude, category, phone, url, mapsId, createdAt) VALUES
              (5, 7, 'Pho Hoa', '1 Main St', 47.61, -122.33, 'Restaurant', '555-0100', 'https://pho.example', 'maps-1', '2026-01-07 12:00:00.000'),
              (6, 7, 'Corner deli', NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-01-08 12:00:00.000');
            INSERT INTO journalEntry (id, journalId, day, slot, source, title, emoji, tint, rating, eatenAt, createdAt, placeId) VALUES
              (31, 2, '2026-01-07', 'Lunch', 'dineOut', 'Pho', '🍜', 16764057, 4, '2026-01-07 12:30:00.000', '2026-01-07 13:00:00.000', 5),
              (32, 2, '2026-01-07', 'Dinner', 'home', 'Leftovers', NULL, NULL, NULL, '2026-01-07 19:00:00.000', '2026-01-07 19:05:00.000', NULL),
              (33, 3, '2026-02-02', 'Dinner', 'delivery', 'Curry', '🍛', NULL, 2, '2026-02-02 19:00:00.000', '2026-02-02 19:05:00.000', NULL);
            INSERT INTO journalEntryEater (entryId, personId) VALUES (31, 3), (31, 5), (32, 3), (33, 8);
            INSERT INTO journalEntryPhoto (id, entryId, photoFile, thumbnailFile, sortOrder, createdAt, cropX, cropY, cropWidth, cropHeight) VALUES
              (41, 31, 'pho.jpg', 'pho-thumb.jpg', 0, '2026-01-07 13:00:00.000', 0.125, 0, 0.75, 1),
              (42, 31, 'pho-2.jpg', 'pho-2-thumb.jpg', 1, '2026-01-07 13:00:00.000', NULL, NULL, NULL, NULL);
            INSERT INTO journalPage (id, journalId, day, drawing, updatedAt) VALUES
              (51, 2, '2026-01-07', X'0102FF', '2026-01-07 21:00:00.000'),
              (52, 3, '2026-01-07', X'00', '2026-01-07 21:00:00.000');
            INSERT INTO chore (id, householdId, title, emoji, ownerId, repeatKind, weekdayMask, intervalDays, anchorDay, timeHint, stars,
                               archived, sortOrder, createdAt) VALUES
              (61, 7, 'Dishes', '🍽️', 3, 'daily', 0, 1, '2026-01-01', 'after dinner', 1, 0, 0, '2026-01-01 08:00:00.000'),
              (62, 7, 'Fix faucet', NULL, NULL, 'once', 0, 1, '2026-01-09', NULL, 3, 1, 1, '2026-01-01 09:00:00.000');
            INSERT INTO choreCompletion (id, choreId, day, personId, stars, completedAt) VALUES
              (71, 61, '2026-01-07', 3, 1, '2026-01-07 20:00:00.000'),
              (72, 61, '2026-01-08', NULL, 1, '2026-01-08 20:00:00.000'),
              (73, 62, '2026-01-07', 5, 3, '2026-01-07 10:00:00.000');
            INSERT INTO reward (id, householdId, title, emoji, targetStars, ownerId, startDay, archived, sortOrder, createdAt) VALUES
              (81, 7, 'Coffee run', '☕', 20, 3, '2026-01-08', 0, 0, '2026-01-01 08:00:00.000'),
              (82, 7, 'Date night', NULL, 250, NULL, '2026-01-01', 1, 1, '2026-01-01 08:00:00.000');
            INSERT INTO rewardRedemption (id, rewardId, personId, stars, day, redeemedAt) VALUES
              (91, 81, 3, 20, '2026-01-08', '2026-01-08 09:00:00.000'),
              (92, 81, 3, 21, '2026-01-08', '2026-01-08 18:00:00.000'),
              (93, 82, NULL, 250, '2026-01-06', '2026-01-06 20:00:00.000');
            INSERT INTO homeList (id, householdId, title, kind, sortOrder, createdAt) VALUES
              (1, 7, 'Groceries', 'grocery', 0, '2026-01-01 08:00:00.000'),
              (2, 7, 'To-do', 'todo', 1, '2026-01-01 08:00:00.000');
            INSERT INTO listItem (id, listId, title, section, addedById, checked, sortOrder, createdAt) VALUES
              (101, 1, 'Basil', 'Produce', 5, 0, 0, '2026-01-02 08:00:00.000'),
              (102, 2, 'Call plumber', NULL, NULL, 1, 0, '2026-01-02 09:00:00.000');
            INSERT INTO mealPlan (householdId, day, title, emoji) VALUES
              (7, '2026-01-07', 'Tacos', '🌮'), (7, '2026-01-08', 'Soup', NULL), (9, '2026-01-07', 'Pasta', '🍝');
            INSERT INTO ambientPhoto (id, householdId, fileName, caption, createdAt) VALUES
              (111, 7, 'beach.jpg', 'Summer', '2026-01-02 08:00:00.000'),
              (112, 9, 'snow.jpg', NULL, '2026-02-02 08:00:00.000');
            """)
    }
}
