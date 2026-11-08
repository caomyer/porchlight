import GRDB

extension AppDatabase {
    /// Companion tables. Append new migrations; never edit a shipped one.
    static func registerCompanionMigrations(_ migrator: inout DatabaseMigrator) {
    }
}
