import Foundation
import GRDB

// MARK: - Records

/// A household journal: a diary with slots per day (the food diary is one
/// journal of kind "food" with meal slots). Each day has entries and one
/// handwritten page.
struct Journal: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var householdId: Int64
    /// What the journal is about, e.g. "food". Screens pick their wording from it.
    var kind: String
    var title: String
    var enabled: Bool
    /// The slot names shown per day, in order (stored as a JSON array).
    var slots: [String]
    var createdAt: Date

    static let foodKind = "food"
}

extension Journal: FetchableRecord, MutablePersistableRecord {
    static let entries = hasMany(JournalEntry.self)

    enum Columns {
        static let householdId = Column(CodingKeys.householdId)
        static let kind = Column(CodingKeys.kind)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Where a meal came from.
enum MealSource: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case home
    case delivery
    case dineOut
    /// Food from work, like the office cafeteria or a catered lunch.
    case company

    var label: String {
        switch self {
        case .home: "Home-cooked"
        case .delivery: "Delivery"
        case .dineOut: "Dine out"
        case .company: "Company"
        }
    }

    var emoji: String {
        switch self {
        case .home: "🏠"
        case .delivery: "🛵"
        case .dineOut: "🍽️"
        case .company: "🏢"
        }
    }

    /// Whether the meal came from a restaurant, so it can name one.
    var hasPlace: Bool { self == .delivery || self == .dineOut }
}

/// A restaurant the household ate at or ordered from. Picked from a live map search
/// (with address and location) or just typed in (name only). Shared by every entry
/// that names it, so a favorite spot is one row.
struct FoodPlace: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: Int64?
    var householdId: Int64
    var name: String
    /// One-line street address, when known.
    var address: String?
    var latitude: Double?
    var longitude: Double?
    /// e.g. "Restaurant", "Cafe", "Bakery".
    var category: String?
    var phone: String?
    var url: String?
    /// Apple Maps place id, when the map search provides one; the best key for de-duplication.
    var mapsId: String?
    var createdAt: Date
}

extension FoodPlace: FetchableRecord, MutablePersistableRecord {
    enum Columns {
        static let householdId = Column(CodingKeys.householdId)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// "Would eat again?" on a 1-4 scale.
enum MealRating: Int, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case meh = 1, fine, again, favorite

    var emoji: String {
        switch self {
        case .meh: "😐"
        case .fine: "🙂"
        case .again: "😋"
        case .favorite: "🤩"
        }
    }

    /// Short phrase used after the emoji, e.g. "😋 would eat again".
    var phrase: String {
        switch self {
        case .meh: "meh"
        case .fine: "pretty good"
        case .again: "would eat again"
        case .favorite: "new favorite"
        }
    }
}

/// One logged meal (or, generically, one journal entry in a slot of a day).
struct JournalEntry: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var journalId: Int64
    /// `DayKey.rawValue` ("yyyy-MM-dd"); see `dayKey`.
    var day: String
    var slot: String
    var source: MealSource
    var title: String
    /// Illustration used when there is no photo.
    var emoji: String?
    /// Background of the illustration, as 0xRRGGBB.
    var tint: Int?
    var rating: MealRating?
    /// When the meal was eaten; places it in the Today timeline.
    var eatenAt: Date
    var createdAt: Date
    /// The restaurant, for delivery or dining out.
    var placeId: Int64?
}

extension JournalEntry: FetchableRecord, MutablePersistableRecord {
    static let eaters = hasMany(JournalEntryEater.self)

    enum Columns {
        static let journalId = Column(CodingKeys.journalId)
        static let day = Column(CodingKeys.day)
        static let eatenAt = Column(CodingKeys.eatenAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// One photo of a meal. A meal has up to `AppDatabase.photoLimit`; the first in
/// `sortOrder` is its cover, the picture shown wherever many meals appear at once.
struct MealPhoto: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: Int64?
    var entryId: Int64
    /// File names inside the photo folder (see `FoodPhotoStore`).
    var photoFile: String
    var thumbnailFile: String
    var sortOrder: Int
    var createdAt: Date
}

extension MealPhoto: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "journalEntryPhoto"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// "Who ate": a person credited with an entry.
struct JournalEntryEater: Codable, Equatable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var entryId: Int64
    var personId: Int64
}

/// The handwritten page of one day: a PencilKit drawing in canonical page coordinates
/// (see `PageGeometry`).
struct JournalPage: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var journalId: Int64
    /// `DayKey.rawValue`.
    var day: String
    /// `PKDrawing.dataRepresentation()`.
    var drawing: Data
    var updatedAt: Date
}

extension JournalPage: FetchableRecord, MutablePersistableRecord {
    enum Columns {
        static let journalId = Column(CodingKeys.journalId)
        static let day = Column(CodingKeys.day)
        static let drawing = Column(CodingKeys.drawing)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension JournalEntry {
    var dayKey: DayKey { DayKey(rawValue: day) }
}

extension JournalPage {
    var dayKey: DayKey { DayKey(rawValue: day) }
}

// MARK: - Migrations

extension AppDatabase {
    /// Journal / food diary tables. Append new migrations; never edit a shipped one.
    static func registerFoodMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("food v1: journals, entries and pages") { db in
            try db.create(table: "journal") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("household", onDelete: .cascade).notNull()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("slots", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "journalEntry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("journal", onDelete: .cascade).notNull()
                t.column("day", .text).notNull()
                t.column("slot", .text).notNull()
                t.column("source", .text).notNull()
                t.column("title", .text).notNull()
                t.column("emoji", .text)
                t.column("tint", .integer)
                t.column("rating", .integer).check { $0 == nil || ($0 >= 1 && $0 <= 4) }
                t.column("photoFile", .text)
                t.column("thumbnailFile", .text)
                t.column("noteLine", .integer)
                t.column("eatenAt", .datetime).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "journalEntry_on_journalId_day", on: "journalEntry", columns: ["journalId", "day"])
            try db.create(table: "journalEntryEater") { t in
                t.belongsTo("entry", inTable: "journalEntry", onDelete: .cascade).notNull()
                t.belongsTo("person", onDelete: .cascade).notNull()
                t.primaryKey(["entryId", "personId"])
            }
            try db.create(table: "journalPage") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("journal", onDelete: .cascade).notNull()
                t.column("day", .text).notNull()
                t.column("drawing", .blob).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.uniqueKey(["journalId", "day"])
            }
        }
        migrator.registerMigration("food v2: restaurants for dine-out and delivery") { db in
            try db.create(table: "foodPlace") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("household", onDelete: .cascade).notNull()
                t.column("name", .text).notNull()
                t.column("address", .text)
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("category", .text)
                t.column("phone", .text)
                t.column("url", .text)
                t.column("mapsId", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.alter(table: "journalEntry") { t in
                t.add(column: "placeId", .integer).references("foodPlace", onDelete: .setNull)
            }
            try db.create(index: "journalEntry_on_placeId", on: "journalEntry", columns: ["placeId"])
        }
        migrator.registerMigration("food v3: notes belong to the day's page, not a meal") { db in
            try db.alter(table: "journalEntry") { t in
                t.drop(column: "noteLine")
            }
        }
        migrator.registerMigration("food v4: several photos per meal") { db in
            try db.create(table: "journalEntryPhoto") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("entry", inTable: "journalEntry", onDelete: .cascade).notNull()
                t.column("photoFile", .text).notNull()
                t.column("thumbnailFile", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "journalEntryPhoto_on_entryId_sortOrder", on: "journalEntryPhoto", columns: ["entryId", "sortOrder"])
            // Each meal's one photo becomes its first, and so its cover.
            try db.execute(sql: """
                INSERT INTO journalEntryPhoto (entryId, photoFile, thumbnailFile, sortOrder, createdAt)
                SELECT id, photoFile, COALESCE(thumbnailFile, photoFile), 0, createdAt
                FROM journalEntry WHERE photoFile IS NOT NULL
                """)
            try db.alter(table: "journalEntry") { t in
                t.drop(column: "photoFile")
                t.drop(column: "thumbnailFile")
            }
        }
    }
}
