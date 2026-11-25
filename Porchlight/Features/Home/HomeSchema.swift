import GRDB

extension AppDatabase {
    /// Chores, rewards, lists and meal plan tables. Append new migrations; never edit a shipped one.
    static func registerHomeMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("home v1: chores, rewards, lists, meals, ambient photos") { db in
            try db.create(table: "chore") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("household", onDelete: .cascade).notNull()
                t.column("title", .text).notNull()
                t.column("emoji", .text)
                // NULL means "Anyone". A removed person's chores become shared.
                t.belongsTo("owner", inTable: "person", onDelete: .setNull)
                t.column("repeatKind", .text).notNull()
                t.column("weekdayMask", .integer).notNull().defaults(to: 0)
                t.column("intervalDays", .integer).notNull().defaults(to: 1)
                // First day for repeating chores, due day for one-off chores.
                t.column("anchorDay", .text).notNull()
                t.column("timeHint", .text)
                t.column("stars", .integer).notNull()
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "choreCompletion") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("chore", onDelete: .cascade).notNull()
                t.column("day", .text).notNull()
                // Who did it. Kept (as NULL) when that person is removed so shared goals keep their stars.
                t.belongsTo("person", onDelete: .setNull)
                // The chore's star value when it was done, so later edits don't rewrite history.
                t.column("stars", .integer).notNull()
                t.column("completedAt", .datetime).notNull()
                t.uniqueKey(["choreId", "day"])
            }
            try db.create(index: "choreCompletion_on_day", on: "choreCompletion", columns: ["day"])

            try db.create(table: "reward") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("household", onDelete: .cascade).notNull()
                t.column("title", .text).notNull()
                t.column("emoji", .text)
                t.column("targetStars", .integer).notNull()
                // NULL means a shared goal everyone earns toward together.
                t.belongsTo("owner", inTable: "person", onDelete: .cascade)
                // Stars count from this day on; "start over" moves it to today.
                t.column("startDay", .text).notNull()
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "homeList") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("household", onDelete: .cascade).notNull()
                t.column("title", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "listItem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("list", inTable: "homeList", onDelete: .cascade).notNull()
                t.column("title", .text).notNull()
                // Grocery aisle ("Produce"); NULL for to-dos.
                t.column("section", .text)
                t.belongsTo("addedBy", inTable: "person", onDelete: .setNull)
                t.column("checked", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "mealPlan") { t in
                t.belongsTo("household", onDelete: .cascade).notNull()
                t.column("day", .text).notNull()
                t.column("title", .text).notNull()
                t.column("emoji", .text)
                t.primaryKey(["householdId", "day"])
            }

            try db.create(table: "ambientPhoto") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("household", onDelete: .cascade).notNull()
                // File name inside Application Support/Porchlight/Ambient.
                t.column("fileName", .text).notNull().unique()
                t.column("caption", .text)
                t.column("createdAt", .datetime).notNull()
            }
        }
        // Rewards are cashed in, not just restarted, so the family can look back on them.
        migrator.registerMigration("home v2: reward cash-ins") { db in
            try db.create(table: "rewardRedemption") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("reward", onDelete: .cascade).notNull()
                t.belongsTo("person", onDelete: .setNull)
                t.column("stars", .integer).notNull()
                t.column("day", .text).notNull()
                t.column("redeemedAt", .datetime).notNull()
            }
            try db.create(index: "rewardRedemption_on_day", on: "rewardRedemption", columns: ["day"])
        }
    }

    /// Changes to the home tables after they were rebuilt for sync.
    static let choreTimeMigration = "home v3: a chore's time"

    static func registerHomeMigrationsAfterSync(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(choreTimeMigration) { db in
            // Minutes from midnight, or nil for any time. Nil for every chore so far, so it
            // writes no rows. Once a chore is given a time, its iCloud record carries the
            // field (and its modification time), so Production must know `timeOfDay` before
            // a build that sets one ships (docs/design/sync-icloud.md, "Fields waiting for
            // Production").
            try db.execute(sql: #"ALTER TABLE "chore" ADD COLUMN "timeOfDay" INTEGER"#)
        }
    }
}
