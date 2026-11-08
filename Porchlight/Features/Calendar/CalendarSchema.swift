import GRDB

extension AppDatabase {
    /// Calendar tables. Append new migrations; never edit a shipped one.
    static func registerCalendarMigrations(_ migrator: inout DatabaseMigrator) {
    }
}
