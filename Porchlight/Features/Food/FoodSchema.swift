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

/// Where a meal came from. Eating out is deliberately left for later.
enum MealSource: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case home
    case delivery

    var label: String {
        switch self {
        case .home: "Home-cooked"
        case .delivery: "Delivery"
        }
    }

    var emoji: String {
        switch self {
        case .home: "🏠"
        case .delivery: "🛵"
        }
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
    /// File names inside the photo folder (see `FoodPhotoStore`).
    var photoFile: String?
    var thumbnailFile: String?
    /// The ruled line (0-based) of the day's page that holds this entry's note, if any.
    var noteLine: Int?
    /// When the meal was eaten; places it in the Today timeline.
    var eatenAt: Date
    var createdAt: Date
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
    }
}
