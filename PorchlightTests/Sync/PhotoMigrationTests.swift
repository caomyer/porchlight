import Foundation
import GRDB
import Testing
import UIKit
@testable import Porchlight

@Suite("Sync v2 migration: photos become rows")
struct PhotoMigrationTests {
    /// A data folder with an old database, filled like a wall that has used photos, and the
    /// photo files its rows name.
    private struct OldWall {
        let folder: URL
        var photos: URL { folder.appendingPathComponent("Photos", isDirectory: true) }
        var companionPhotos: URL { folder.appendingPathComponent("CompanionPhotos", isDirectory: true) }
        var database: URL { folder.appendingPathComponent("porchlight.sqlite") }
        /// The bytes written for each file, by its name.
        var files: [String: Data] = [:]

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("photo-migration-\(UUID().uuidString)", isDirectory: true)
            for url in [photos, companionPhotos] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            let queue = try SyncFixture.oldDatabase(path: database.path)
            try queue.write(SyncFixture.fill)
            // Beside the fixture's two photos: one larger than a stored photo may be, one whose
            // thumbnail "food v4" made its whole shot, and one whose files are both gone.
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO journalEntryPhoto (id, entryId, photoFile, thumbnailFile, sortOrder, createdAt) VALUES
                      (43, 32, 'big.jpg', 'big-thumb.jpg', 0, '2026-01-07 19:05:00.000'),
                      (44, 33, 'single.jpg', 'single.jpg', 0, '2026-02-02 19:05:00.000'),
                      (45, 32, 'gone.jpg', 'gone-thumb.jpg', 1, '2026-01-07 19:06:00.000')
                    """)
            }
            try queue.close()
            // Pho has both files; Pho's second photo only its thumbnail; the big one only its
            // whole shot; Yo-Yo has a photo; and one file belongs to no row.
            try write("pho.jpg", Self.jpeg(width: 400, height: 300, color: .orange), in: photos)
            try write("pho-thumb.jpg", Self.jpeg(width: 360, height: 360, color: .orange), in: photos)
            try write("pho-2-thumb.jpg", Self.jpeg(width: 360, height: 360, color: .red), in: photos)
            try write("big.jpg", Self.jpeg(width: 3000, height: 1000, color: .green), in: photos)
            try write("single.jpg", Self.jpeg(width: 600, height: 400, color: .blue), in: photos)
            try write("orphan.jpg", Self.jpeg(width: 10, height: 10, color: .gray), in: photos)
            try write("yoyo.jpg", Self.jpeg(width: 800, height: 600, color: .brown), in: companionPhotos)
        }

        private mutating func write(_ name: String, _ data: Data, in folder: URL) throws {
            try data.write(to: folder.appendingPathComponent(name))
            files[name] = data
        }

        func exists(_ name: String, in folder: URL) -> Bool {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
        }

        static func jpeg(width: CGFloat, height: CGFloat, color: UIColor) -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                UIColor.white.setFill()
                context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
            }.jpegData(compressionQuality: 0.8)!
        }
    }

    /// Each photo's pictures after the migration, by the photo's old title.
    private struct Pictures {
        var image: Data?
        var thumbnail: Data?
    }

    private func pictures(_ db: Database, sortOrder: Int, entry title: String) throws -> Pictures {
        let row = try #require(try Row.fetchOne(db, sql: """
            SELECT i.image AS image, t.image AS thumbnail FROM journalEntryPhoto p
            JOIN journalEntry e ON e.id = p.entryId
            LEFT JOIN journalEntryPhotoImage i ON i.photoId = p.id
            LEFT JOIN journalEntryPhotoThumb t ON t.photoId = p.id
            WHERE e.title = ? AND p.sortOrder = ?
            """, arguments: [title, sortOrder]))
        return Pictures(image: row["image"], thumbnail: row["thumbnail"])
    }

    private func schema(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name")
    }

    @Test("Every file becomes a row with its bytes, the odd cases keep what exists, and only then do the files go")
    func importsEveryFile() throws {
        let wall = try OldWall()
        defer { try? FileManager.default.removeItem(at: wall.folder) }
        let database = try AppDatabase.openOnDisk(folder: wall.folder)

        try database.writer.read { db throws in
            let pho = try pictures(db, sortOrder: 0, entry: "Pho")
            #expect(pho.image == wall.files["pho.jpg"], "a stored-size photo is kept byte for byte")
            #expect(pho.thumbnail == wall.files["pho-thumb.jpg"])

            let second = try pictures(db, sortOrder: 1, entry: "Pho")
            #expect(second.image == nil, "a lost whole shot leaves the thumbnail as the only picture")
            #expect(second.thumbnail == wall.files["pho-2-thumb.jpg"])

            let big = try pictures(db, sortOrder: 0, entry: "Leftovers")
            let bigImage = try #require(big.image.flatMap(UIImage.init(data:)))
            #expect(bigImage.size == CGSize(width: 2048, height: 683), "a larger photo is stored at 2048 pixels")
            let made = try #require(big.thumbnail.flatMap(UIImage.init(data:)))
            #expect(made.size == CGSize(width: 360, height: 360), "a lost thumbnail is made again from the whole shot")

            let single = try pictures(db, sortOrder: 0, entry: "Curry")
            #expect(single.image == wall.files["single.jpg"])
            #expect(single.thumbnail.flatMap(UIImage.init(data:))?.size == CGSize(width: 360, height: 360),
                    "a whole shot that stood in for its thumbnail gets a real one")

            let gone = try pictures(db, sortOrder: 1, entry: "Leftovers")
            #expect(gone.image == nil && gone.thumbnail == nil, "a photo whose files are both gone keeps its row")

            let yoyo = try Data.fetchOne(db, sql: """
                SELECT p.image FROM companionPhoto p JOIN companion c ON c.id = p.companionId WHERE c.name = 'Yo-Yo'
                """)
            #expect(yoyo == wall.files["yoyo.jpg"])
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM companionPhoto") == 1, "Fern never had a photo")
            for (table, key) in PhotoFileCleanup.keyColumns {
                let mismatched = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE byteCount != length(image)") ?? -1
                #expect(mismatched == 0, "\(table) counts its bytes (\(key))")
            }
            #expect(try !db.tableExists(PhotoFileCleanup.table), "the list of files to remove goes once they are")
        }

        for name in ["pho.jpg", "pho-thumb.jpg", "pho-2-thumb.jpg", "big.jpg", "single.jpg"] {
            #expect(!wall.exists(name, in: wall.photos), "\(name) is removed once its row holds it")
        }
        #expect(wall.exists("orphan.jpg", in: wall.photos), "a file no row named stays where it was")
        #expect(!FileManager.default.fileExists(atPath: wall.companionPhotos.path), "an emptied folder goes")

        // The upgraded wall ends with the schema of a new one.
        let fresh = try AppDatabase.inMemory()
        #expect(try database.writer.read(schema) == fresh.writer.read(schema))
    }

    @Test("Until the cleanup runs, a wall has both the files and the rows; a row that doesn't match keeps its file")
    func filesGoOnlyAfterCommit() throws {
        let wall = try OldWall()
        defer { try? FileManager.default.removeItem(at: wall.folder) }
        // As if the app stopped right after the migration committed.
        let queue = try DatabaseQueue(path: wall.database.path, configuration: AppDatabase.configuration)
        try AppDatabase.migrator(files: wall.folder).migrate(queue)
        for name in ["pho.jpg", "pho-thumb.jpg", "pho-2-thumb.jpg", "big.jpg", "single.jpg"] {
            #expect(wall.exists(name, in: wall.photos), "\(name) waits for the cleanup")
        }
        #expect(wall.exists("yoyo.jpg", in: wall.companionPhotos))
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM journalEntryPhotoImage") } == 3)

        // A row that no longer holds what came from its file keeps the file.
        try queue.write { db in try db.execute(sql: "UPDATE companionPhoto SET image = X'00', byteCount = 1") }
        try PhotoFileCleanup.run(queue, files: wall.folder)
        #expect(wall.exists("yoyo.jpg", in: wall.companionPhotos))
        #expect(!wall.exists("pho.jpg", in: wall.photos))
        #expect(try queue.read { try !$0.tableExists(PhotoFileCleanup.table) })

        // Later launches have nothing left to do.
        try PhotoFileCleanup.run(queue, files: wall.folder)
        #expect(wall.exists("yoyo.jpg", in: wall.companionPhotos))
    }

    @Test("A database without files imports nothing and keeps every photo row")
    func noFiles() throws {
        let queue = try SyncFixture.oldDatabase()
        try queue.write(SyncFixture.fill)
        _ = try AppDatabase(queue)
        try queue.read { db throws in
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM journalEntryPhoto") == 2)
            for table in PhotoFileCleanup.keyColumns.keys {
                #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") == 0, "\(table)")
            }
            #expect(try !db.columns(in: "journalEntryPhoto").contains { $0.name == "photoFile" || $0.name == "thumbnailFile" })
            #expect(try !db.columns(in: "companion").contains { $0.name == "photoFile" })
            #expect(try !db.tableExists(PhotoFileCleanup.table))
        }
    }

    /// Runs only with `PORCHLIGHT_REAL_DATA_DIR` set to a copy of the wall's data folder (the
    /// database and its `Photos` folder, e.g. from scripts/backup-ipad.sh; pass it to the
    /// simulator with `TEST_RUNNER_PORCHLIGHT_REAL_DATA_DIR=<path>`). It migrates a further
    /// copy, never the folder itself.
    @Test("A copy of the wall's real data keeps every photo file's bytes in a row",
          .enabled(if: ProcessInfo.processInfo.environment["PORCHLIGHT_REAL_DATA_DIR"] != nil))
    func realData() throws {
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PORCHLIGHT_REAL_DATA_DIR"]), isDirectory: true)
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("real-data-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: source, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }

        // The files the rows name, read before anything changes.
        let database = copy.appendingPathComponent("porchlight.sqlite")
        let queue = try DatabaseQueue(path: database.path, configuration: AppDatabase.configuration)
        let migrator = AppDatabase.migrator(files: nil)
        let applied = try queue.read { try migrator.appliedIdentifiers($0) }
        try #require(!applied.contains("sync v2: photos become rows"), "the copy is from before the photo import")
        // A copy from before "sync v1" is brought up to the last old migration, so the photo
        // tables exist. A copy from after it (the wall since M0) already has them.
        if !applied.contains(AppDatabase.syncMigration) {
            try migrator.migrate(queue, upTo: SyncFixture.lastOldMigration)
        }
        let named = try queue.read { db -> [String] in
            let meals = try Row.fetchAll(db, sql: "SELECT photoFile, thumbnailFile FROM journalEntryPhoto").flatMap { row -> [String] in
                let photo: String = row["photoFile"]
                let thumbnail: String = row["thumbnailFile"]
                return ["Photos/" + photo, "Photos/" + thumbnail]
            }
            let companions = try String.fetchAll(db, sql: "SELECT photoFile FROM companion WHERE photoFile IS NOT NULL")
            return meals + companions.map { "CompanionPhotos/" + $0 }
        }
        try queue.close()
        var files: [String: Data] = [:]
        for name in Set(named) {
            files[name] = try? Data(contentsOf: copy.appendingPathComponent(name))
        }
        #expect(!files.isEmpty, "the copy has photo files")

        let migrated = try AppDatabase.openOnDisk(folder: copy)
        let stored = try migrated.writer.read { db in
            try Set(PhotoFileCleanup.keyColumns.keys.flatMap { try Data.fetchAll(db, sql: "SELECT image FROM \($0)") })
        }
        for (name, data) in files {
            let expected = MealPhotoImaging.fitted(data) ?? data
            #expect(stored.contains(expected), "\(name) is in a row")
        }
        let (photos, thumbnails) = try migrated.writer.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM journalEntryPhoto") ?? 0,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM journalEntryPhotoThumb") ?? 0)
        }
        #expect(thumbnails == photos, "every photo has a thumbnail")
        print("Real data: \(files.count) photo files in \(photos) photos, \(Set(named).count - files.count) named but missing")
    }
}
