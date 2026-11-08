import Foundation
import GRDB

extension AppDatabase {
    /// Companion tables. Append new migrations; never edit a shipped one.
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
    }
}

// MARK: - Records

/// Someone (or something) the household looks after.
struct Companion: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var householdId: Int64
    var name: String
    var species: Species
    var coat: CoatPreset
    var photoFile: String?
    /// Free text under the name, e.g. "Toy poodle".
    var about: String
    var birthDate: Date?
    var captionTone: CompanionTone
    var sortOrder: Int
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Something done for a companion on a cadence: walks, meals, watering.
struct CareRoutine: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var companionId: Int64
    var kind: CareKind
    var title: String
    var emoji: String
    /// 1 for daily routines; N for "every N days".
    var everyDays: Int
    /// Ordered daily windows; one slot each. Routines every N days have one window.
    var windows: [CareWindow]
    /// Person ids taking turns, in order. Empty means anyone, no turns.
    var rotation: [Int64]
    var trackedFields: [CareField]
    var stars: Int
    /// Minutes after a window opens before a still-open slot is flagged as due.
    var nudgeAfterMinutes: Int?
    var sortOrder: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func tracks(_ field: CareField) -> Bool { trackedFields.contains(field) }

    var isDaily: Bool { everyDays <= 1 }

    /// Slots per due day.
    var slotsPerDay: Int { isDaily ? max(windows.count, 1) : 1 }

    /// The routine's windows, never empty.
    var effectiveWindows: [CareWindow] {
        let windows = isDaily ? windows : Array(windows.prefix(1))
        return windows.isEmpty ? [.anyTime] : windows
    }

    /// Walk-like routines get a paw lane on the calendar.
    var isWalkLike: Bool { kind == .walk }

    /// "Walk · 2× a day", "Water · every 3 days".
    var cadenceText: String {
        if !isDaily { return "every \(everyDays) days" }
        return slotsPerDay == 1 ? "once a day" : "\(slotsPerDay)× a day"
    }
}

/// One time someone did a routine.
struct CareLog: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var careRoutineId: Int64
    var occurredAt: Date
    var durationMinutes: Int?
    var pee: Bool?
    var poo: Bool?
    var vibe: CareVibe?
    var note: String?
    var stars: Int
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct CareLogPerson: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    var careLogId: Int64
    var personId: Int64
}
