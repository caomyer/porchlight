import Foundation
import GRDB

// MARK: - Records

/// A household journal: a diary with slots per day (the food diary is one
/// journal of kind "food" with meal slots). Each day has entries and one
/// handwritten page.
struct Journal: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<Journal>

    var id: ID = .new()
    var householdId: Household.ID
    /// What the journal is about, e.g. "food". Screens pick their wording from it.
    var kind: String
    var title: String
    var enabled: Bool
    /// The slot names shown per day, in order (stored as a JSON array).
    var slots: [String]
    var createdAt: Date

    static let foodKind = "food"
}

extension Journal: FetchableRecord, PersistableRecord {
    static let entries = hasMany(JournalEntry.self)

    enum Columns {
        static let householdId = Column(CodingKeys.householdId)
        static let kind = Column(CodingKeys.kind)
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
    typealias ID = Porchlight.ID<FoodPlace>

    var id: ID = .new()
    var householdId: Household.ID
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

extension FoodPlace: FetchableRecord, PersistableRecord {
    enum Columns {
        static let householdId = Column(CodingKeys.householdId)
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
    typealias ID = Porchlight.ID<JournalEntry>

    var id: ID = .new()
    var journalId: Journal.ID
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
    /// The restaurant, for delivery or dining out. A plain id, not a foreign key:
    /// after a sync it may point at a place that has not arrived yet.
    var placeId: FoodPlace.ID?
}

extension JournalEntry: FetchableRecord, PersistableRecord {
    static let eaters = hasMany(JournalEntryEater.self)

    enum Columns {
        static let journalId = Column(CodingKeys.journalId)
        static let day = Column(CodingKeys.day)
        static let eatenAt = Column(CodingKeys.eatenAt)
    }
}

/// One photo of a meal. A meal has up to `AppDatabase.photoLimit`; the first in
/// `sortOrder` is its cover, the picture shown wherever many meals appear at once.
struct MealPhoto: Codable, Equatable, Hashable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<MealPhoto>

    var id: ID = .new()
    var entryId: JournalEntry.ID
    /// File names inside the photo folder (see `FoodPhotoStore`). The photo is the whole
    /// shot; the thumbnail is the square the wall shows.
    var photoFile: String
    var thumbnailFile: String
    var sortOrder: Int
    var createdAt: Date
    /// The square shown on the wall, as fractions of the photo's width and height.
    /// All nil means the center square.
    var cropX: Double?
    var cropY: Double?
    var cropWidth: Double?
    var cropHeight: Double?

    var crop: PhotoCrop? {
        get {
            guard let cropX, let cropY, let cropWidth, let cropHeight else { return nil }
            return PhotoCrop(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        }
        set {
            cropX = newValue?.x
            cropY = newValue?.y
            cropWidth = newValue?.width
            cropHeight = newValue?.height
        }
    }
}

/// Which part of a photo the wall shows, as fractions of the photo's width and height.
/// Meal photos use squares: the polaroid's shape.
struct PhotoCrop: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// The largest square, centered: what the camera's square viewfinder shows.
    static func centeredSquare(in size: CGSize) -> PhotoCrop {
        square(in: size, position: 0.5)
    }

    /// The largest square, slid along the photo's long side: 0 is the top (or left),
    /// 1 the bottom (or right).
    static func square(in size: CGSize, position: Double) -> PhotoCrop {
        guard size.width > 0, size.height > 0 else { return PhotoCrop(x: 0, y: 0, width: 1, height: 1) }
        let position = min(max(position, 0), 1)
        if size.width >= size.height {
            let width = size.height / size.width
            return PhotoCrop(x: (1 - width) * position, y: 0, width: width, height: 1)
        }
        let height = size.width / size.height
        return PhotoCrop(x: 0, y: (1 - height) * position, width: 1, height: height)
    }

    /// A square zoomed in `zoom` times (1 is the largest square that fits) around
    /// `center`, given as fractions of the photo's width and height. The square is moved
    /// back inside the photo when the center is too close to an edge.
    static func square(in size: CGSize, zoom: Double, center: CGPoint) -> PhotoCrop {
        guard size.width > 0, size.height > 0 else { return PhotoCrop(x: 0, y: 0, width: 1, height: 1) }
        let side = min(size.width, size.height) / max(zoom, 1)
        let width = side / size.width, height = side / size.height
        let x = min(max(center.x - width / 2, 0), 1 - width)
        let y = min(max(center.y - height / 2, 0), 1 - height)
        return PhotoCrop(x: x, y: y, width: width, height: height)
    }

    /// How far the square is zoomed in on a photo of `size`; 1 is the largest square.
    func zoom(in size: CGSize) -> Double {
        guard size.width > 0, width > 0 else { return 1 }
        return min(size.width, size.height) / (width * size.width)
    }

    /// The square's center, as fractions of the photo's width and height.
    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }

    /// Where the square sits along the photo's long side, from 0 to 1.
    var position: Double {
        if width < 1 { return x / (1 - width) }
        if height < 1 { return y / (1 - height) }
        return 0.5
    }

    /// The crop in pixels of an image of `size`, kept inside the image.
    func rect(in size: CGSize) -> CGRect {
        let rect = CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height).integral
        return rect.intersection(CGRect(origin: .zero, size: size))
    }
}

extension MealPhoto: FetchableRecord, PersistableRecord {
    static let databaseTableName = "journalEntryPhoto"
}

/// "Who ate": a person credited with an entry.
struct JournalEntryEater: Codable, Equatable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<JournalEntryEater>

    /// Derived from the entry and the person, so crediting someone twice is one row.
    var id: ID
    var entryId: JournalEntry.ID
    /// A plain id, not a foreign key: it may point at nobody yet after a sync.
    var personId: Person.ID

    init(entryId: JournalEntry.ID, personId: Person.ID) {
        id = Self.id(entryId: entryId, personId: personId)
        self.entryId = entryId
        self.personId = personId
    }

    static func id(entryId: JournalEntry.ID, personId: Person.ID) -> ID {
        .derived(entryId.description, personId.description)
    }
}

/// The handwritten page of one day: a PencilKit drawing in canonical page coordinates
/// (see `PageGeometry`).
struct JournalPage: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<JournalPage>

    /// Derived from the journal and the day: a day has one page, on every device.
    var id: ID
    var journalId: Journal.ID
    /// `DayKey.rawValue`.
    var day: String
    /// `PKDrawing.dataRepresentation()`.
    var drawing: Data
    var updatedAt: Date

    init(journalId: Journal.ID, day: DayKey, drawing: Data, updatedAt: Date) {
        id = Self.id(journalId: journalId, day: day)
        self.journalId = journalId
        self.day = day.rawValue
        self.drawing = drawing
        self.updatedAt = updatedAt
    }

    static func id(journalId: Journal.ID, day: DayKey) -> ID {
        .derived(journalId.description, day.rawValue)
    }
}

extension JournalPage: FetchableRecord, PersistableRecord {
    enum Columns {
        static let journalId = Column(CodingKeys.journalId)
        static let day = Column(CodingKeys.day)
        static let drawing = Column(CodingKeys.drawing)
        static let updatedAt = Column(CodingKeys.updatedAt)
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
        migrator.registerMigration("food v5: which square of a photo the wall shows") { db in
            // No crop (all nil) is the center square, which every photo so far shows.
            try db.alter(table: "journalEntryPhoto") { t in
                t.add(column: "cropX", .double)
                t.add(column: "cropY", .double)
                t.add(column: "cropWidth", .double)
                t.add(column: "cropHeight", .double)
            }
        }
    }
}
