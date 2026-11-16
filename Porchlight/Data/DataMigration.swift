import GRDB

extension AppDatabase {
    /// Migrations that insert or rewrite rows of synced tables once sync has been on.
    ///
    /// The sync engine only records writes made while it exists on the connection, and it is
    /// created after the schema migrations. A row a schema migration writes on a device that
    /// has synced would never upload, so such changes go here instead: they run right after
    /// the engine is created (docs/design/sync-icloud.md, "Data changes after sync is on").
    /// They change rows only, never the schema, and use raw SQL and rows like every migration.
    /// They share `grdb_migrations` with the schema migrations, so identifiers stay unique.
    static func dataMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        registerDataMigrations(&migrator)
        return migrator
    }

    /// Append new data migrations here; never edit a shipped one. There are none yet: the
    /// photo import ("sync v2") ran before sync had been on anywhere, so every row it wrote
    /// uploads with the rest on the engine's first start.
    private static func registerDataMigrations(_ migrator: inout DatabaseMigrator) {}

    /// Runs the data migrations. Call it once the sync engine exists.
    func migrateData(_ migrator: DatabaseMigrator = AppDatabase.dataMigrator()) throws {
        try migrator.migrate(writer)
    }
}
