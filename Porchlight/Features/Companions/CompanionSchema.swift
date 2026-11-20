import Foundation
import GRDB

extension AppDatabase {
    /// Companion tables. Append new migrations; never edit a shipped one.
    /// Changes to the companion tables after they were rebuilt for sync.
    static func registerCompanionMigrationsAfterSync(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("companions v4: the slot a log was made for") { db in
            // Nil for every log so far, so it writes no rows: they stay placed by their time.
            // Once a log is saved with it, its iCloud record carries the field (and its
            // modification time), so Production must know `slot` before this ships
            // (docs/design/sync-icloud.md, "A new column, and older builds").
            try db.execute(sql: #"ALTER TABLE "careLog" ADD COLUMN "slot" INTEGER"#)
        }
    }

    static func registerCompanionMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("companions v1: companions, routines and care logs") { db in
            try db.create(table: "companion") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("household", onDelete: .cascade).notNull()
                t.column("name", .text).notNull()
                t.column("species", .text).notNull()
                t.column("coat", .text).notNull()
                // File name inside the companion photo folder; nil uses the coat.
                t.column("photoFile", .text)
                t.column("about", .text).notNull().defaults(to: "")
                t.column("birthDate", .date)
                t.column("captionTone", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "careRoutine") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("companion", onDelete: .cascade).notNull()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("emoji", .text).notNull()
                // 1 = daily; N > 1 = once every N days.
                t.column("everyDays", .integer).notNull().defaults(to: 1)
                t.column("windows", .jsonText).notNull()
                t.column("rotation", .jsonText).notNull()
                t.column("trackedFields", .jsonText).notNull()
                t.column("stars", .integer).notNull().defaults(to: 0)
                t.column("nudgeAfterMinutes", .integer)
                t.column("sortOrder", .integer).notNull()
            }
            try db.create(table: "careLog") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("careRoutine", onDelete: .cascade).notNull()
                t.column("occurredAt", .datetime).notNull().indexed()
                t.column("durationMinutes", .integer)
                t.column("pee", .boolean)
                t.column("poo", .boolean)
                t.column("vibe", .text)
                t.column("note", .text)
                // Stars at the time of logging, so editing a routine never rewrites history.
                t.column("stars", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            // Several people can do one walk together.
            try db.create(table: "careLogPerson") { t in
                t.belongsTo("careLog", onDelete: .cascade).notNull()
                t.belongsTo("person", onDelete: .cascade).notNull()
                t.primaryKey(["careLogId", "personId"])
            }
        }
        // Whoever is free does the walk; the log sheet asks who did it.
        migrator.registerMigration("companions v2: no turn rotation") { db in
            try db.alter(table: "careRoutine") { t in t.drop(column: "rotation") }
        }
        // Routines repeat like chores (some weekdays, monthly...) and count from a start day.
        // Existing every-N-days routines keep their rhythm by starting on their last log's day.
        migrator.registerMigration("companions v3: routines share chores' repeat rules") { db in
            try db.alter(table: "careRoutine") { t in
                t.add(column: "repeatKind", .text).notNull().defaults(to: "daily")
                t.add(column: "weekdayMask", .integer).notNull().defaults(to: 0)
                t.add(column: "anchorDay", .text).notNull().defaults(to: "")
            }
            // Raw rows, not `Household`: record types follow the latest schema, which
            // this migration's database has not reached.
            let household = try Row.fetchOne(db, sql: "SELECT timeZoneIdentifier, firstWeekday FROM household ORDER BY id LIMIT 1")
            let calendar = household.map {
                Calendar.household(timeZoneIdentifier: $0["timeZoneIdentifier"], firstWeekday: $0["firstWeekday"])
            } ?? .current
            let today = DayKey(.now, calendar: calendar)
            let rows = try Row.fetchAll(db, sql: """
                SELECT r.id, r.everyDays, MIN(l.occurredAt) AS first, MAX(l.occurredAt) AS last
                FROM careRoutine r LEFT JOIN careLog l ON l.careRoutineId = r.id
                GROUP BY r.id
                """)
            for row in rows {
                let everyDays: Int = row["everyDays"]
                let first: Date? = row["first"]
                let last: Date? = row["last"]
                let kind = everyDays > 1 ? "interval" : "daily"
                var anchor = (everyDays > 1 ? last : first).map { DayKey($0, calendar: calendar) } ?? today
                // An every-N-days routine that was already due (or overdue) stays due today.
                if everyDays > 1, Recurrence.days(from: anchor, to: today, calendar: calendar) >= everyDays {
                    anchor = today
                }
                try db.execute(
                    sql: "UPDATE careRoutine SET repeatKind = ?, anchorDay = ? WHERE id = ?",
                    arguments: [kind, anchor.rawValue, row["id"] as Int64]
                )
            }
        }
    }
}

// MARK: - Records

/// Someone (or something) the household looks after.
struct Companion: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<Companion>

    var id: ID = .new()
    var householdId: Household.ID
    var name: String
    var species: Species
    var coat: CoatPreset
    /// Free text under the name, e.g. "Toy poodle".
    var about: String
    var birthDate: Date?
    var captionTone: CompanionTone
    var sortOrder: Int
    var createdAt: Date
}

/// A companion's photo, in its own row so lists of companions never load it
/// (docs/design/sync-icloud.md, "Photos").
struct CompanionPhoto: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    var companionId: Companion.ID
    /// The size of `image`, read without loading it (and summed by the storage meter).
    var byteCount: Int
    var image: Data

    init(companionId: Companion.ID, image: Data) {
        self.companionId = companionId
        byteCount = image.count
        self.image = image
    }
}

/// Something done for a companion on a cadence: walks, meals, watering.
struct CareRoutine: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<CareRoutine>

    var id: ID = .new()
    var companionId: Companion.ID
    var kind: CareKind
    var title: String
    var emoji: String
    /// The interval of "every N days" routines (see `recurrence`); 1 otherwise.
    var everyDays: Int
    /// Ordered daily windows; one slot each. Routines every N days have one window.
    var windows: [CareWindow]
    var trackedFields: [CareField]
    var stars: Int
    /// Minutes after a window opens before a still-open slot is flagged as due.
    var nudgeAfterMinutes: Int?
    var sortOrder: Int
    /// How it repeats, stored like a chore's (see `recurrence`).
    var repeatKind: String = "daily"
    var weekdayMask: Int = 0
    /// The first day it is expected (`DayKey.rawValue`); empty means "always has been".
    var anchorDay: String = ""

    func tracks(_ field: CareField) -> Bool { trackedFields.contains(field) }

    /// The same repeat rules chores use. Routines never repeat "just once".
    var recurrence: Recurrence {
        get { Recurrence(kind: everyDays > 1 && repeatKind == "daily" ? "interval" : repeatKind, weekdayMask: weekdayMask, intervalDays: everyDays) }
        set {
            repeatKind = newValue.kind
            weekdayMask = newValue.weekdayMask
            everyDays = newValue.intervalDays
        }
    }

    /// The day it starts counting from.
    var start: DayKey { DayKey(rawValue: anchorDay.isEmpty ? "0000-01-01" : anchorDay) }

    /// Whether care is expected on `day`.
    func occurs(on day: DayKey, calendar: Calendar) -> Bool {
        recurrence.occurs(on: day, start: start, calendar: calendar)
    }

    var isDaily: Bool { recurrence == .daily }

    /// Slots per day it is due.
    var slotsPerDay: Int { max(windows.count, 1) }

    /// The routine's windows, never empty.
    var effectiveWindows: [CareWindow] {
        windows.isEmpty ? [.anyTime] : windows
    }

    /// Walk-like routines get a paw lane on the calendar.
    var isWalkLike: Bool { kind == .walk }

    /// "2× a day", "every 3 days", "Mon, Thu", "2× on weekdays", "monthly on the 1st".
    func cadenceText(calendar: Calendar) -> String {
        let times = slotsPerDay == 1 ? nil : "\(slotsPerDay)×"
        switch recurrence {
        case .daily: return times.map { "\($0) a day" } ?? "once a day"
        default:
            let pattern = recurrence.describe(start: start, calendar: calendar)
            return times.map { "\($0) \(pattern)" } ?? pattern
        }
    }
}

/// One time someone did a routine.
struct CareLog: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<CareLog>

    var id: ID = .new()
    var careRoutineId: CareRoutine.ID
    var occurredAt: Date
    var durationMinutes: Int?
    var pee: Bool?
    var poo: Bool?
    var vibe: CareVibe?
    var note: String?
    var stars: Int
    var createdAt: Date
    /// The device that logged it (a plain id); nil for logs from before devices were known.
    var deviceId: Device.ID? = nil
    /// The slot it was logged for (an index into the routine's windows), when it was
    /// logged for one: a tap on a slot, catching up, a widget, Siri or a reminder. Nil for
    /// a log placed by its time (the care sheet, an older build). `CareLogic.assign` puts it
    /// in this slot whatever time of day it was written.
    var slot: Int? = nil
}

/// Someone who did a logged routine. Several people can do one walk together.
struct CareLogPerson: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<CareLogPerson>

    /// Derived from the log and the person, so crediting someone twice is one row.
    var id: ID
    var careLogId: CareLog.ID
    /// A plain id, not a foreign key: it may point at nobody yet after a sync.
    var personId: Person.ID

    init(careLogId: CareLog.ID, personId: Person.ID) {
        id = Self.id(careLogId: careLogId, personId: personId)
        self.careLogId = careLogId
        self.personId = personId
    }

    static func id(careLogId: CareLog.ID, personId: Person.ID) -> ID {
        .derived(careLogId.description, personId.description)
    }
}
