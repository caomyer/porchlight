import GRDB

extension AppDatabase {
    /// Journal / food diary tables. Append new migrations; never edit a shipped one.
    static func registerFoodMigrations(_ migrator: inout DatabaseMigrator) {
    }
}
