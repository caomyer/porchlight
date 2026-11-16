import GRDB

extension AppDatabase {
    static let householdMigration = "households v1: devices and where rows came from"

    /// Adds the `device` table, the device-only `deviceState`, and a nullable `deviceId` on
    /// every row that says who wrote it (docs/design/households.md, "The model").
    ///
    /// Sync had never been on anywhere when this shipped, so it is a schema migration: the
    /// new table and columns are simply there when the engine first starts. It writes no rows.
    static func registerHouseholdMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(householdMigration) { db in
            for table in SyncSchema.householdTables {
                try db.execute(sql: "CREATE TABLE \"\(table.name)\" (\(table.columns)) STRICT")
            }
            try db.execute(sql: #"CREATE INDEX "device_on_householdId" ON "device"("householdId")"#)
            for table in SyncSchema.stampedTables {
                try db.execute(sql: "ALTER TABLE \"\(table)\" ADD COLUMN \"deviceId\" TEXT")
            }
        }
    }
}
