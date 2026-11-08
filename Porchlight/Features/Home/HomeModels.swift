import Foundation
import GRDB

// MARK: - Chores

/// How often a chore comes around.
enum ChoreRecurrence: Hashable, Sendable {
    case daily
    /// On these `Calendar` weekdays (1 = Sunday ... 7 = Saturday).
    case weekdays(Set<Int>)
    /// Every `n` days, counted from the chore's anchor day.
    case everyNDays(Int)
    /// One time, due on the chore's anchor day. Stays on the board until done.
    case once

    var isOnce: Bool { self == .once }
}

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

    var recurrence: ChoreRecurrence {
        get {
            switch repeatKind {
            case "weekdays": .weekdays(Self.weekdays(fromMask: weekdayMask))
            case "interval": .everyNDays(max(intervalDays, 1))
            case "once": .once
            default: .daily
            }
        }
        set {
            switch newValue {
            case .daily:
                repeatKind = "daily"; weekdayMask = 0; intervalDays = 1
            case let .weekdays(days):
                repeatKind = "weekdays"; weekdayMask = Self.mask(for: days); intervalDays = 1
            case let .everyNDays(n):
                repeatKind = "interval"; weekdayMask = 0; intervalDays = n
            case .once:
                repeatKind = "once"; weekdayMask = 0; intervalDays = 1
            }
        }
    }

    static func mask(for weekdays: Set<Int>) -> Int {
        weekdays.filter { (1...7).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    static func weekdays(fromMask mask: Int) -> Set<Int> {
        Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
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
