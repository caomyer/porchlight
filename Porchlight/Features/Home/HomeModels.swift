import Foundation
import GRDB

// MARK: - Chores

/// A household chore. Repeating chores start on `anchorDay`; one-off chores are due on it.
struct Chore: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var householdId: Int64
    var title: String
    var emoji: String?
    /// The person it belongs to; nil means "Anyone".
    var ownerId: Int64?
    var repeatKind: String
    var weekdayMask: Int
    var intervalDays: Int
    var anchorDay: String
    /// A loose window like "7-9am" or "before noon".
    var timeHint: String?
    var stars: Int
    var archived: Bool
    var sortOrder: Int
    var createdAt: Date

    var owner: Owner { ownerId.map(Owner.person) ?? .everyone }
    var anchor: DayKey { DayKey(rawValue: anchorDay) }

    var recurrence: Recurrence {
        get { Recurrence(kind: repeatKind, weekdayMask: weekdayMask, intervalDays: intervalDays) }
        set {
            repeatKind = newValue.kind
            weekdayMask = newValue.weekdayMask
            intervalDays = newValue.intervalDays
        }
    }
}

extension Chore: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// A chore done on a day, and who did it.
struct ChoreCompletion: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var choreId: Int64
    var day: String
    /// Nil only when the person who did it has since been removed.
    var personId: Int64?
    var stars: Int
    var completedAt: Date

    var dayKey: DayKey { DayKey(rawValue: day) }
}

extension ChoreCompletion: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Something to earn stars toward: a personal treat, or a shared goal when `ownerId` is nil.
struct Reward: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var householdId: Int64
    var title: String
    var emoji: String?
    var targetStars: Int
    var ownerId: Int64?
    var startDay: String
    var archived: Bool
    var sortOrder: Int
    var createdAt: Date

    var owner: Owner { ownerId.map(Owner.person) ?? .everyone }
    var isShared: Bool { ownerId == nil }
}

extension Reward: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// A reward cashed in: its stars were spent and it starts over.
struct RewardRedemption: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var rewardId: Int64
    /// Whose treat it was; nil for a shared goal (or a removed person).
    var personId: Int64?
    var stars: Int
    var day: String
    var redeemedAt: Date

    var dayKey: DayKey { DayKey(rawValue: day) }
}

extension RewardRedemption: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// One time someone earned stars: a chore done, or care given to a companion.
/// Every star total in the app (the board, rewards, Glow) adds these up, so a star
/// means the same thing wherever it shows.
struct StarEarning: Equatable, Identifiable, Sendable {
    enum Source: Equatable, Hashable, Sendable {
        case chore(choreId: Int64, completionId: Int64)
        case care(routineId: Int64, logId: Int64)
    }

    var source: Source
    /// Who earned them; nil only when that person was removed.
    var personId: Int64?
    var stars: Int
    var day: DayKey
    /// When it happened (a walk's start time), as shown.
    var at: Date
    /// When it was written down. Unlike `at`, nobody can edit it, so reward rounds split on it.
    var recordedAt: Date
    var title: String
    var emoji: String

    var id: String {
        switch source {
        case let .chore(_, completionId): "chore-\(completionId)-\(personId ?? 0)"
        case let .care(_, logId): "care-\(logId)-\(personId ?? 0)"
        }
    }

    var isCare: Bool {
        if case .care = source { return true }
        return false
    }

    /// Identifies what was done, regardless of who helped.
    var deed: Source { source }
}

extension Array where Element == StarEarning {
    /// One earning per thing done: care done together credits each helper, but counts once
    /// toward household totals (shared goals, the Anyone column, the porch light).
    var counted: [StarEarning] {
        var seen = Set<StarEarning.Source>()
        return filter { seen.insert($0.deed).inserted }
    }
}

// MARK: - Lists and meals

enum ListKind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case grocery
    case todo

    var label: String {
        switch self {
        case .grocery: "Groceries"
        case .todo: "To-do"
        }
    }
}

/// A shared list: groceries (grouped by section) or to-dos.
struct HomeList: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var householdId: Int64
    var title: String
    var kind: ListKind
    var sortOrder: Int
    var createdAt: Date

    static let databaseTableName = "homeList"
}

extension HomeList: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct ListItem: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var listId: Int64
    var title: String
    var section: String?
    var addedById: Int64?
    var checked: Bool
    var sortOrder: Int
    var createdAt: Date
}

extension ListItem: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// The dinner planned for a day.
struct MealPlan: Codable, Equatable, Sendable {
    var householdId: Int64
    var day: String
    var title: String
    var emoji: String?

    var dayKey: DayKey { DayKey(rawValue: day) }
}

extension MealPlan: FetchableRecord, PersistableRecord {}

// MARK: - Ambient

/// A photo imported for Ambient mode. The image lives in `AmbientPhotoLibrary`.
struct AmbientPhoto: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var householdId: Int64
    var fileName: String
    var caption: String?
    var createdAt: Date
}

extension AmbientPhoto: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
