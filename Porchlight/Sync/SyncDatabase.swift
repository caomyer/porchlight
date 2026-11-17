import SQLiteData

extension Database {
    /// Attaches the sync engine's own database, where it keeps what it knows about every
    /// row (`SyncMetadata`), to this connection.
    ///
    /// Every connection to the database on disk attaches it, readers included, so any of
    /// them can read sync state. The container is named here rather than read from the
    /// entitlements, which builds without iCloud don't have.
    func attachSyncMetadata() throws {
        try attachMetadatabase(containerIdentifier: SyncController.containerIdentifier)
    }
}

/// Rows iCloud has never taken: written here, but with no record of them on the server.
///
/// Right after a write that is normal, until the engine sends it. When it stays that way
/// after the engine has sent, iCloud turned the record down (Production without the
/// schema answers "Cannot create new type"), and SQLiteData drops it from what it sends
/// until the row changes again. `SyncController` notices and asks for them again
/// (docs/design/sync-icloud.md, "When iCloud turns changes down").
enum SyncUnsent {
    static func count(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM "sqlitedata_icloud_metadata"
            WHERE NOT "hasLastKnownServerRecord" AND NOT "_isDeleted"
            """) ?? 0
    }

    /// Puts every such row back in line to send. The engine's own trigger on its metadata
    /// queues a row whenever the row is touched outside of sync; this touches without
    /// changing anything, the way SQLiteData itself does after signing in.
    static func requeue(_ db: Database) throws {
        try db.execute(sql: """
            UPDATE "sqlitedata_icloud_metadata" SET "recordPrimaryKey" = "recordPrimaryKey"
            WHERE NOT "hasLastKnownServerRecord" AND NOT "_isDeleted"
            """)
    }
}
