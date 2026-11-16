import Foundation
import GRDB

// MARK: - Chores

/// A household chore. Repeating chores start on `anchorDay`; one-off chores are due on it.
struct Chore: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<Chore>

    var id: ID = .new()
    var householdId: Household.ID
    var title: String
    var emoji: String?
    /// The person it belongs to; nil means "Anyone".
    var ownerId: Person.ID?
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

extension Chore: FetchableRecord, PersistableRecord {}

/// A chore done on a day, and who did it.
struct ChoreCompletion: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<ChoreCompletion>

    /// Derived from the chore and the day: a chore is done once a day, on every device.
    var id: ID
    var choreId: Chore.ID
    var day: String
    /// Who did it. Nil only in rows from before people were archived rather than deleted.
    var personId: Person.ID?
    var stars: Int
    var completedAt: Date
    /// The device that checked it off (a plain id); nil for rows from before devices were known.
    var deviceId: Device.ID?

    init(choreId: Chore.ID, day: DayKey, personId: Person.ID?, stars: Int, completedAt: Date, deviceId: Device.ID? = nil) {
        id = Self.id(choreId: choreId, day: day)
        self.choreId = choreId
        self.day = day.rawValue
        self.personId = personId
        self.stars = stars
        self.completedAt = completedAt
        self.deviceId = deviceId
    }

    static func id(choreId: Chore.ID, day: DayKey) -> ID {
        .derived(choreId.description, day.rawValue)
    }

    var dayKey: DayKey { DayKey(rawValue: day) }
}

extension ChoreCompletion: FetchableRecord, PersistableRecord {}

/// Something to earn stars toward: a personal treat, or a shared goal when `ownerId` is nil.
struct Reward: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<Reward>

    var id: ID = .new()
    var householdId: Household.ID
    var title: String
    var emoji: String?
    var targetStars: Int
    var ownerId: Person.ID?
    var startDay: String
    var archived: Bool
    var sortOrder: Int
    var createdAt: Date

    var owner: Owner { ownerId.map(Owner.person) ?? .everyone }
    var isShared: Bool { ownerId == nil }
}

extension Reward: FetchableRecord, PersistableRecord {}

/// A reward cashed in: its stars were spent and it starts over.
struct RewardRedemption: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<RewardRedemption>

    /// Derived from the reward and the cash-in before it (see `id(rewardId:after:)`).
    var id: ID
    var rewardId: Reward.ID
    /// Whose treat it was; nil for a shared goal.
    var personId: Person.ID?
    var stars: Int
    var day: String
    var redeemedAt: Date
    /// The device that cashed it in (a plain id); nil for rows from before devices were known.
    var deviceId: Device.ID? = nil

    /// One cash-in per round: a round is everything after the reward's previous cash-in,
    /// so two devices cashing in the same round offline write the same row.
    ///
    /// The reward's start day alone can't name a round, because a reward can be cashed
    /// in more than once on the same day.
    static func id(rewardId: Reward.ID, after previous: ID?) -> ID {
        .derived(rewardId.description, previous?.description ?? "first")
    }

    var dayKey: DayKey { DayKey(rawValue: day) }
}

extension RewardRedemption: FetchableRecord, PersistableRecord {}

/// One time someone earned stars: a chore done, or care given to a companion.
/// Every star total in the app (the board, rewards, Glow) adds these up, so a star
/// means the same thing wherever it shows.
struct StarEarning: Equatable, Identifiable, Sendable {
    enum Source: Equatable, Hashable, Sendable {
        case chore(choreId: Chore.ID, completionId: ChoreCompletion.ID)
        case care(routineId: CareRoutine.ID, logId: CareLog.ID)
    }

    var source: Source
    /// Who earned them; nil only in rows from before people were archived rather than deleted.
    var personId: Person.ID?
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
        case let .chore(_, completionId): "chore-\(completionId)-\(personId?.description ?? "nobody")"
        case let .care(_, logId): "care-\(logId)-\(personId?.description ?? "nobody")"
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
    typealias ID = Porchlight.ID<HomeList>

    var id: ID = .new()
    var householdId: Household.ID
    var title: String
    var kind: ListKind
    var sortOrder: Int
    var createdAt: Date

    static let databaseTableName = "homeList"
}

extension HomeList: FetchableRecord, PersistableRecord {}

struct ListItem: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<ListItem>

    var id: ID = .new()
    var listId: HomeList.ID
    var title: String
    var section: String?
    var addedById: Person.ID?
    var checked: Bool
    var sortOrder: Int
    var createdAt: Date
    /// The device that added it (a plain id); nil for items from before devices were known.
    var deviceId: Device.ID? = nil
}

extension ListItem: FetchableRecord, PersistableRecord {}

/// The dinner planned for a day.
struct MealPlan: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<MealPlan>

    /// Derived from the household and the day: a day has one dinner, on every device.
    var id: ID
    var householdId: Household.ID
    var day: String
    var title: String
    var emoji: String?

    init(householdId: Household.ID, day: DayKey, title: String, emoji: String?) {
        id = Self.id(householdId: householdId, day: day)
        self.householdId = householdId
        self.day = day.rawValue
        self.title = title
        self.emoji = emoji
    }

    static func id(householdId: Household.ID, day: DayKey) -> ID {
        .derived(householdId.description, day.rawValue)
    }

    var dayKey: DayKey { DayKey(rawValue: day) }
}

extension MealPlan: FetchableRecord, PersistableRecord {}

// MARK: - Ambient

/// A photo imported for Ambient mode. The image lives in `AmbientPhotoLibrary`.
struct AmbientPhoto: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<AmbientPhoto>

    var id: ID = .new()
    var householdId: Household.ID
    var fileName: String
    var caption: String?
    var createdAt: Date
}

extension AmbientPhoto: FetchableRecord, PersistableRecord {}
