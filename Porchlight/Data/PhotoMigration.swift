import CryptoKit
import Foundation
import GRDB

extension AppDatabase {
    static let photoMigration = "sync v2: photos become rows"

    /// Moves every meal and companion photo from its file into a synced row
    /// (docs/design/sync-icloud.md, "Photos"). Like every migration since "sync v1", it
    /// uses raw SQL and rows only.
    ///
    /// - Parameter files: The data folder whose `Photos` and `CompanionPhotos` folders hold
    ///   the files; nil for a database that never had any (in memory).
    static func registerPhotoMigrations(_ migrator: inout DatabaseMigrator, files: URL?) {
        migrator.registerMigration(photoMigration) { db in
            try PhotoImport(db: db, files: files).run()
        }
    }
}

/// The "sync v2" import. Each photo's files become rows, then the file-name columns go.
///
/// Sync has never been turned on anywhere yet, so `companion` and `journalEntryPhoto` may
/// still lose columns. This is the last time: from now on synced tables only gain columns
/// (docs/design/sync-foundation.md, rule 5).
///
/// Nothing is deleted here. Every file that went into a row is listed in `photoFileImport`,
/// in the same transaction, and `PhotoFileCleanup` removes it only after the transaction has
/// committed and the row reads back with the same bytes. A crash in between leaves both.
///
/// Real walls have odd cases. A missing file never fails the migration; whatever exists is
/// kept. A missing (or shared) thumbnail is made again from the whole shot, and a missing
/// whole shot leaves the thumbnail as the photo's only picture. A file that isn't a readable
/// image is kept byte for byte. A photo with neither file keeps its row, without a picture.
private struct PhotoImport {
    let db: Database
    let files: URL?

    /// A file whose bytes went into a row, for the cleanup to check before removing it.
    private struct Imported {
        var file: String
        var table: String
        var key: String
        var bytes: Data
    }

    func run() throws {
        for table in SyncSchema.photoTables {
            try db.execute(sql: "CREATE TABLE \"\(table.name)\" (\(table.columns)) STRICT")
        }
        let imported = try importMealPhotos() + importCompanionPhotos()
        try db.alter(table: "journalEntryPhoto") { t in
            t.drop(column: "photoFile")
            t.drop(column: "thumbnailFile")
        }
        try db.alter(table: "companion") { t in
            t.drop(column: "photoFile")
        }
        try record(imported)
    }

    private func importMealPhotos() throws -> [Imported] {
        var imported: [Imported] = []
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, photoFile, thumbnailFile, cropX, cropY, cropWidth, cropHeight FROM journalEntryPhoto
            """)
        for row in rows {
            let id: String = row["id"]
            let photoFile: String = row["photoFile"]
            let thumbnailFile: String = row["thumbnailFile"]
            var image: Data?
            if let data = read("Photos", photoFile) {
                let stored = MealPhotoImaging.fitted(data) ?? data
                try insert("journalEntryPhotoImage", key: id, stored)
                imported.append(Imported(file: "Photos/\(photoFile)", table: "journalEntryPhotoImage", key: id, bytes: stored))
                image = stored
            }
            // "food v4" gave single photos without a thumbnail their whole shot as one.
            if thumbnailFile != photoFile, let data = read("Photos", thumbnailFile) {
                try insert("journalEntryPhotoThumb", key: id, data)
                imported.append(Imported(file: "Photos/\(thumbnailFile)", table: "journalEntryPhotoThumb", key: id, bytes: data))
            } else if let image, let made = try? MealPhotoImaging.thumbnail(ofImage: image, crop: crop(row)) {
                try insert("journalEntryPhotoThumb", key: id, made)
            }
        }
        return imported
    }

    private func importCompanionPhotos() throws -> [Imported] {
        var imported: [Imported] = []
        for row in try Row.fetchAll(db, sql: "SELECT id, photoFile FROM companion WHERE photoFile IS NOT NULL") {
            let id: String = row["id"]
            let file: String = row["photoFile"]
            guard let data = read("CompanionPhotos", file) else { continue }
            let stored = MealPhotoImaging.fitted(data) ?? data
            try insert("companionPhoto", key: id, stored)
            imported.append(Imported(file: "CompanionPhotos/\(file)", table: "companionPhoto", key: id, bytes: stored))
        }
        return imported
    }

    /// The file's bytes, or nil when it is missing. Only flat names inside the folder are
    /// read, so an odd row can never point the cleanup at anything else.
    private func read(_ folder: String, _ name: String) -> Data? {
        guard let files, PhotoFileCleanup.isFlatName(name) else { return nil }
        return try? Data(contentsOf: files.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name))
    }

    private func insert(_ table: String, key: String, _ image: Data) throws {
        let column = PhotoFileCleanup.keyColumns[table] ?? "photoId"
        try db.execute(
            sql: "INSERT INTO \"\(table)\" (\"\(column)\", byteCount, image) VALUES (?, ?, ?)",
            arguments: [key, image.count, image]
        )
    }

    private func crop(_ row: Row) -> PhotoCrop? {
        guard let x: Double = row["cropX"], let y: Double = row["cropY"],
              let width: Double = row["cropWidth"], let height: Double = row["cropHeight"] else { return nil }
        return PhotoCrop(x: x, y: y, width: width, height: height)
    }

    /// Lists the imported files. The table exists only while files wait to be removed, so a
    /// database that never had any ends with the same schema as one whose files are gone.
    private func record(_ imported: [Imported]) throws {
        guard !imported.isEmpty else { return }
        try db.execute(sql: """
            CREATE TABLE "\(PhotoFileCleanup.table)" (
              "file" TEXT PRIMARY KEY NOT NULL, "rowTable" TEXT NOT NULL, "rowKey" TEXT NOT NULL, "sha256" TEXT NOT NULL
            ) STRICT
            """)
        for item in imported {
            try db.execute(
                sql: "INSERT OR IGNORE INTO \"\(PhotoFileCleanup.table)\" (file, rowTable, rowKey, sha256) VALUES (?, ?, ?, ?)",
                arguments: [item.file, item.table, item.key, PhotoFileCleanup.digest(item.bytes)]
            )
        }
    }
}

/// Removes the photo files "sync v2" moved into rows, once that is safely committed.
///
/// It runs each time the database on disk opens, and does nothing once the list is gone.
/// A file is removed only when its row still holds exactly the bytes taken from it. A file
/// that can't be matched stays where it is: nothing reads it, and it is never removed
/// automatically, since a photo is worth more than the space.
enum PhotoFileCleanup {
    static let table = "photoFileImport"
    /// The folders the files lived in, removed once empty.
    static let folders = ["Photos", "CompanionPhotos"]
    /// The key column of each photo table.
    static let keyColumns = [
        "companionPhoto": "companionId", "journalEntryPhotoThumb": "photoId", "journalEntryPhotoImage": "photoId",
    ]

    static func run(_ writer: any DatabaseWriter, files: URL, fileManager: FileManager = .default) throws {
        guard try writer.read({ try $0.tableExists(table) }) else { return }
        let entries = try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT file, rowTable, rowKey, sha256 FROM \"\(table)\"")
        }
        for entry in entries {
            let file: String = entry["file"]
            let rowTable: String = entry["rowTable"]
            guard let column = keyColumns[rowTable] else { continue }
            let stored = try writer.read { db in
                try Data.fetchOne(db, sql: "SELECT image FROM \"\(rowTable)\" WHERE \"\(column)\" = ?", arguments: [entry["rowKey"] as String])
            }
            guard let stored, digest(stored) == entry["sha256"] else { continue }
            try? fileManager.removeItem(at: files.appendingPathComponent(file))
        }
        try writer.write { db in try db.drop(table: table) }
        for folder in folders {
            let url = files.appendingPathComponent(folder, isDirectory: true)
            if (try? fileManager.contentsOfDirectory(atPath: url.path))?.isEmpty == true {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// A file name with no path in it.
    static func isFlatName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("..")
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
