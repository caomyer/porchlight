import Foundation
import GRDB

/// What a household takes up, summed from its own rows on this device (journey E4): photos
/// are their rows' byte counts, Pencil pages their drawings, and everything else what the
/// database holds besides. Every device has every row, so every device sees the same sums.
struct HouseholdStorage: Equatable, Sendable {
    /// Meal photos (whole shots and thumbnails) and companion photos.
    var photos: Int
    /// The food diary's handwritten pages.
    var pages: Int
    /// Everything else this device stores: the household's other rows, and their indexes.
    var other: Int
    /// The meal photos added from `mine`'s devices.
    var mine: Int
    /// Photos added in the last 30 days, the pace it grows at.
    var lastMonth: Int

    var total: Int { photos + pages + other }

    static let zero = HouseholdStorage(photos: 0, pages: 0, other: 0, mine: 0, lastMonth: 0)
}

extension AppDatabase {
    /// - Parameter mine: The devices whose meal photos count as "yours".
    func storage(of householdId: Household.ID, mine: [Device.ID], now: Date = .now) throws -> HouseholdStorage {
        try writer.read { db in
            let mealPhotos = """
                FROM journalEntryPhoto p
                JOIN journalEntry e ON e.id = p.entryId
                JOIN journal j ON j.id = e.journalId
                LEFT JOIN journalEntryPhotoImage i ON i.photoId = p.id
                LEFT JOIN journalEntryPhotoThumb t ON t.photoId = p.id
                WHERE j.householdId = ?
                """
            let pictureBytes = "COALESCE(SUM(COALESCE(i.byteCount, 0) + COALESCE(t.byteCount, 0)), 0)"
            let meals = try Int.fetchOne(db, sql: "SELECT \(pictureBytes) \(mealPhotos)", arguments: [householdId]) ?? 0
            let companions = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(cp.byteCount), 0) FROM companionPhoto cp
                JOIN companion c ON c.id = cp.companionId WHERE c.householdId = ?
                """, arguments: [householdId]) ?? 0
            let pages = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(LENGTH(pg.drawing)), 0) FROM journalPage pg
                JOIN journal j ON j.id = pg.journalId WHERE j.householdId = ?
                """, arguments: [householdId]) ?? 0
            var mineBytes = 0
            if !mine.isEmpty {
                let marks = mine.map { _ in "?" }.joined(separator: ",")
                mineBytes = try Int.fetchOne(
                    db,
                    sql: "SELECT \(pictureBytes) \(mealPhotos) AND e.deviceId IN (\(marks))",
                    arguments: StatementArguments([householdId] + mine.map { $0 as (any DatabaseValueConvertible) })
                ) ?? 0
            }
            let monthAgo = now.addingTimeInterval(-30 * 24 * 60 * 60)
            let lastMonth = try Int.fetchOne(
                db, sql: "SELECT \(pictureBytes) \(mealPhotos) AND p.createdAt >= ?", arguments: [householdId, monthAgo]
            ) ?? 0
            // What the database file holds in use, less the pictures counted above.
            let pageSize = try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0
            let used = (try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0) - (try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0)
            let photos = meals + companions
            return HouseholdStorage(
                photos: photos, pages: pages, other: max(used * pageSize - photos - pages, 0),
                mine: mineBytes, lastMonth: lastMonth
            )
        }
    }
}

/// "412 MB", "3.4 GB", "Zero KB" said as a person would.
enum StorageWords {
    static func size(_ bytes: Int) -> String {
        guard bytes > 0 else { return "nothing yet" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// The meter's line: "412 MB · Photos 322 MB · Pencil pages 61 MB · Everything else 29 MB".
    static func breakdown(_ storage: HouseholdStorage) -> String {
        var parts = [size(storage.total)]
        if storage.photos > 0 { parts.append("Photos \(size(storage.photos))") }
        if storage.pages > 0 { parts.append("Pencil pages \(size(storage.pages))") }
        parts.append("Everything else \(size(storage.other))")
        return parts.joined(separator: " · ")
    }
}
