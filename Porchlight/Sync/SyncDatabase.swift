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
