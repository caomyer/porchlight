import Foundation
import GRDB

// Every Home write, with validation. Views go through `HomeStore`, which calls these.

enum HomeValidationError: Error, Equatable, LocalizedError {
    case emptyTitle
    case titleTooLong(limit: Int)
    case hintTooLong(limit: Int)
    case starsOutOfRange(ClosedRange<Int>)
    case targetOutOfRange(ClosedRange<Int>)
    case noWeekdays
    case intervalOutOfRange(ClosedRange<Int>)
    case invalidDay
    case unknownPerson
    case notFound
    case notDue
    case alreadyCashedIn

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Please enter a name."
        case let .titleTooLong(limit): "Keep it under \(limit) characters."
        case let .hintTooLong(limit): "Keep the time hint under \(limit) characters."
        case let .starsOutOfRange(range): "Stars must be between \(range.lowerBound) and \(range.upperBound)."
        case let .targetOutOfRange(range): "The goal must be between \(range.lowerBound) and \(range.upperBound) stars."
        case .noWeekdays: "Pick at least one day."
        case let .intervalOutOfRange(range): "Repeat every \(range.lowerBound) to \(range.upperBound) days."
        case .invalidDay: "That day isn't valid."
        case .unknownPerson: "That person isn't part of this household."
        case .notFound: "That item no longer exists."
        case .notDue: "That chore isn't due that day."
        case .alreadyCashedIn: "That reward was just cashed in."
        }
    }
}

enum HomeLimits {
    static let title = 60
    static let hint = 30
    static let stars = 0...20
    static let target = 1...10_000
    static let interval = 1...365
}

struct ChoreDraft: Equatable, Sendable {
    var title = ""
    var emoji: String?
    var ownerId: Int64?
    var recurrence: Recurrence = .daily
    /// First day for repeating chores; due day for one-off chores.
    var anchorDay: DayKey
    var timeHint: String?
    var stars = 1
}

struct RewardDraft: Equatable, Sendable {
    var title = ""
    var emoji: String?
    var targetStars = 30
    var ownerId: Int64?
}

extension AppDatabase {
    // MARK: Validation helpers

    static func validatedTitle(_ raw: String) throws -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw HomeValidationError.emptyTitle }
        guard title.count <= HomeLimits.title else { throw HomeValidationError.titleTooLong(limit: HomeLimits.title) }
        return title
    }

    private static func validatedDay(_ day: DayKey) throws -> DayKey {
        let parts = day.rawValue.split(separator: "-")
        guard parts.count == 3, parts.allSatisfy({ Int($0) != nil }) else { throw HomeValidationError.invalidDay }
        return day
    }

    private static func requirePerson(_ id: Int64?, in householdId: Int64, _ db: Database) throws {
        guard let id else { return }
        let exists = try Person.filter(Column("id") == id && Column("householdId") == householdId).fetchCount(db) > 0
        guard exists else { throw HomeValidationError.unknownPerson }
    }

    private static func nextOrder(_ db: Database, table: String, where column: String, _ value: Int64) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sortOrder) + 1, 0) FROM \(table) WHERE \(column) = ?", arguments: [value]) ?? 0
    }

    // MARK: Chores

    /// Creates a chore, or updates it when `id` is given.
    @discardableResult
    func saveChore(_ draft: ChoreDraft, id: Int64? = nil, householdId: Int64, now: Date = .now) throws -> Chore {
        let title = try Self.validatedTitle(draft.title)
        let hint = draft.timeHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hint, hint.count > HomeLimits.hint { throw HomeValidationError.hintTooLong(limit: HomeLimits.hint) }
        guard HomeLimits.stars.contains(draft.stars) else { throw HomeValidationError.starsOutOfRange(HomeLimits.stars) }
        switch draft.recurrence {
        case let .weekdays(days) where days.filter({ (1...7).contains($0) }).isEmpty:
            throw HomeValidationError.noWeekdays
        case let .everyNDays(n) where !HomeLimits.interval.contains(n):
            throw HomeValidationError.intervalOutOfRange(HomeLimits.interval)
        default: break
        }
        let anchor = try Self.validatedDay(draft.anchorDay)

        return try writer.write { db in
            try Self.requirePerson(draft.ownerId, in: householdId, db)
            var chore: Chore
            if let id {
                guard let existing = try Chore.fetchOne(db, id: id), existing.householdId == householdId else {
                    throw HomeValidationError.notFound
                }
                chore = existing
            } else {
                chore = Chore(
                    householdId: householdId, title: title, ownerId: nil, repeatKind: "daily", weekdayMask: 0,
                    intervalDays: 1, anchorDay: anchor.rawValue, stars: 1, archived: false,
                    sortOrder: try Self.nextOrder(db, table: "chore", where: "householdId", householdId), createdAt: now
                )
            }
            chore.title = title
            chore.emoji = HomeText.emoji(draft.emoji)
            chore.ownerId = draft.ownerId
            chore.recurrence = draft.recurrence
            chore.anchorDay = anchor.rawValue
            chore.timeHint = (hint?.isEmpty ?? true) ? nil : hint
            chore.stars = draft.stars
            try chore.save(db)
            return chore
        }
    }

    func setChoreArchived(id: Int64, archived: Bool) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE chore SET archived = ? WHERE id = ?", arguments: [archived, id])
        }
    }

    /// Removes a chore and its history for good. Prefer archiving, which keeps earned stars.
    func deleteChore(id: Int64) throws {
        try writer.write { db in _ = try Chore.deleteOne(db, id: id) }
    }

    /// Marks a chore done on `day` by `personId`, or undoes it when already done.
    /// Returns whether the chore is done afterwards.
    @discardableResult
    func toggleChore(id: Int64, day: DayKey, personId: Int64?, now: Date = .now) throws -> Bool {
        let day = try Self.validatedDay(day)
        return try writer.write { db in
            guard let chore = try Chore.fetchOne(db, id: id) else { throw HomeValidationError.notFound }
            let existing = try ChoreCompletion
                .filter(Column("choreId") == id && Column("day") == day.rawValue)
                .fetchOne(db)
            if let existing {
                _ = try existing.delete(db)
                return false
            }
            // Credit goes to the owner, or to whoever was picked for an "Anyone" chore.
            let person = chore.ownerId ?? personId
            guard let person else { throw HomeValidationError.unknownPerson }
            try Self.requirePerson(person, in: chore.householdId, db)
            if chore.recurrence.isOnce {
                // A one-off chore can only be done once.
                try ChoreCompletion.filter(Column("choreId") == id).deleteAll(db)
            }
            var completion = ChoreCompletion(choreId: id, day: day.rawValue, personId: person, stars: chore.stars, completedAt: now)
            try completion.insert(db)
            return true
        }
    }

    /// Says who did a chore on a day: changes the credit of an existing completion, or
    /// checks it off for that person. Anyone can pitch in on someone else's chore.
    func creditChore(id: Int64, day: DayKey, personId: Int64, now: Date = .now) throws {
        let day = try Self.validatedDay(day)
        try writer.write { db in
            guard let chore = try Chore.fetchOne(db, id: id) else { throw HomeValidationError.notFound }
            try Self.requirePerson(personId, in: chore.householdId, db)
            // A one-off is done once, whichever day: re-credit it where it is.
            let existing = chore.recurrence.isOnce
                ? try ChoreCompletion.filter(Column("choreId") == id).fetchOne(db)
                : try ChoreCompletion.filter(Column("choreId") == id && Column("day") == day.rawValue).fetchOne(db)
            if var existing {
                existing.personId = personId
                try existing.update(db)
                return
            }
            let calendar = try Household.fetchOne(db, id: chore.householdId)?.calendar ?? .current
            guard chore.recurrence.isOnce || ChoreSchedule.occurs(chore, on: day, calendar: calendar) else {
                throw HomeValidationError.notDue
            }
            var completion = ChoreCompletion(choreId: id, day: day.rawValue, personId: personId, stars: chore.stars, completedAt: now)
            try completion.insert(db)
        }
    }

    // MARK: Rewards

    @discardableResult
    func saveReward(_ draft: RewardDraft, id: Int64? = nil, householdId: Int64, today: DayKey, now: Date = .now) throws -> Reward {
        let title = try Self.validatedTitle(draft.title)
        guard HomeLimits.target.contains(draft.targetStars) else {
            throw HomeValidationError.targetOutOfRange(HomeLimits.target)
        }
        return try writer.write { db in
            try Self.requirePerson(draft.ownerId, in: householdId, db)
            var reward: Reward
            if let id {
                guard let existing = try Reward.fetchOne(db, id: id), existing.householdId == householdId else {
                    throw HomeValidationError.notFound
                }
                reward = existing
            } else {
                reward = Reward(
                    householdId: householdId, title: title, targetStars: draft.targetStars, ownerId: nil,
                    startDay: today.rawValue, archived: false,
                    sortOrder: try Self.nextOrder(db, table: "reward", where: "householdId", householdId), createdAt: now
                )
            }
            reward.title = title
            reward.emoji = HomeText.emoji(draft.emoji)
            reward.targetStars = draft.targetStars
            reward.ownerId = draft.ownerId
            try reward.save(db)
            return reward
        }
    }

    /// Starts counting a reward from zero again, from `day` on (after it was enjoyed).
    func restartReward(id: Int64, from day: DayKey) throws {
        let day = try Self.validatedDay(day)
        try writer.write { db in
            try db.execute(sql: "UPDATE reward SET startDay = ? WHERE id = ?", arguments: [day.rawValue, id])
        }
    }

    /// Cashes a reward in: records the stars spent on it and starts it over from `day`.
    /// Stars earned later that same day count toward the next round.
    /// `after` is the latest cash-in the caller knew of, so a second tap (or another
    /// screen) can't cash the same round in twice.
    @discardableResult
    func cashInReward(id: Int64, stars: Int, day: DayKey, after known: Int64? = nil, now: Date = .now) throws -> RewardRedemption {
        let day = try Self.validatedDay(day)
        return try writer.write { db in
            guard let reward = try Reward.fetchOne(db, id: id) else { throw HomeValidationError.notFound }
            let latest = try Int64.fetchOne(db, sql: "SELECT MAX(id) FROM rewardRedemption WHERE rewardId = ?", arguments: [id])
            guard latest == known, stars > 0 else { throw HomeValidationError.alreadyCashedIn }
            var redemption = RewardRedemption(
                rewardId: id, personId: reward.ownerId, stars: max(stars, 0), day: day.rawValue, redeemedAt: now
            )
            try redemption.insert(db)
            try db.execute(sql: "UPDATE reward SET startDay = ? WHERE id = ?", arguments: [day.rawValue, id])
            return redemption
        }
    }

    func setRewardArchived(id: Int64, archived: Bool) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE reward SET archived = ? WHERE id = ?", arguments: [archived, id])
        }
    }

    func deleteReward(id: Int64) throws {
        try writer.write { db in _ = try Reward.deleteOne(db, id: id) }
    }

    // MARK: Lists

    /// Gives a household its starting lists (Groceries and To-do) if it has none yet.
    func ensureDefaultLists(householdId: Int64, now: Date = .now) throws {
        try writer.write { db in
            guard try HomeList.filter(Column("householdId") == householdId).fetchCount(db) == 0 else { return }
            for (index, kind) in ListKind.allCases.enumerated() {
                var list = HomeList(householdId: householdId, title: kind.label, kind: kind, sortOrder: index, createdAt: now)
                try list.insert(db)
            }
        }
    }

    @discardableResult
    func createList(title: String, kind: ListKind, householdId: Int64, now: Date = .now) throws -> HomeList {
        let title = try Self.validatedTitle(title)
        return try writer.write { db in
            var list = HomeList(
                householdId: householdId, title: title, kind: kind,
                sortOrder: try Self.nextOrder(db, table: "homeList", where: "householdId", householdId), createdAt: now
            )
            try list.insert(db)
            return list
        }
    }

    func renameList(id: Int64, to newTitle: String) throws {
        let title = try Self.validatedTitle(newTitle)
        try writer.write { db in
            try db.execute(sql: "UPDATE homeList SET title = ? WHERE id = ?", arguments: [title, id])
        }
    }

    func deleteList(id: Int64) throws {
        try writer.write { db in _ = try HomeList.deleteOne(db, id: id) }
    }

    /// Adds an item. Grocery items without a section get a guessed one.
    @discardableResult
    func addListItem(title: String, to listId: Int64, section: String? = nil, addedBy: Int64?, now: Date = .now) throws -> ListItem {
        let title = try Self.validatedTitle(title)
        return try writer.write { db in
            guard let list = try HomeList.fetchOne(db, id: listId) else { throw HomeValidationError.notFound }
            try Self.requirePerson(addedBy, in: list.householdId, db)
            var item = ListItem(
                listId: listId,
                title: title,
                section: list.kind == .grocery ? Self.section(section, guessingFrom: title) : nil,
                addedById: addedBy,
                checked: false,
                sortOrder: try Self.nextOrder(db, table: "listItem", where: "listId", listId),
                createdAt: now
            )
            try item.insert(db)
            return item
        }
    }

    private static func section(_ raw: String?, guessingFrom title: String) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? GrocerySections.guess(title) : String(trimmed.prefix(HomeLimits.title))
    }

    func updateListItem(id: Int64, title newTitle: String, section: String?) throws {
        let title = try Self.validatedTitle(newTitle)
        try writer.write { db in
            guard var item = try ListItem.fetchOne(db, id: id),
                  let list = try HomeList.fetchOne(db, id: item.listId) else { throw HomeValidationError.notFound }
            item.title = title
            if list.kind == .grocery { item.section = Self.section(section, guessingFrom: title) }
            try item.update(db)
        }
    }

    func setListItemChecked(id: Int64, checked: Bool) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE listItem SET checked = ? WHERE id = ?", arguments: [checked, id])
        }
    }

    func deleteListItem(id: Int64) throws {
        try writer.write { db in _ = try ListItem.deleteOne(db, id: id) }
    }

    /// Removes every checked item from a list. Returns how many were removed.
    @discardableResult
    func clearCheckedItems(listId: Int64) throws -> Int {
        try writer.write { db in
            try ListItem.filter(Column("listId") == listId && Column("checked") == true).deleteAll(db)
        }
    }

    // MARK: Meals

    /// Plans dinner for a day; an empty title clears it.
    func setMeal(day: DayKey, title rawTitle: String, emoji: String?, householdId: Int64) throws {
        let day = try Self.validatedDay(day)
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        try writer.write { db in
            if trimmed.isEmpty {
                _ = try MealPlan.deleteOne(db, key: ["householdId": householdId, "day": day.rawValue])
                return
            }
            let meal = MealPlan(
                householdId: householdId,
                day: day.rawValue,
                title: try Self.validatedTitle(trimmed),
                emoji: HomeText.emoji(emoji) ?? MealEmoji.guess(trimmed)
            )
            try meal.save(db)
        }
    }

    // MARK: Ambient photos

    @discardableResult
    func addAmbientPhoto(fileName: String, caption: String?, householdId: Int64, now: Date = .now) throws -> AmbientPhoto {
        try writer.write { db in
            var photo = AmbientPhoto(householdId: householdId, fileName: fileName, caption: caption, createdAt: now)
            try photo.insert(db)
            return photo
        }
    }

    /// Removes the photo row; returns its file name so the caller can delete the image.
    @discardableResult
    func removeAmbientPhoto(id: Int64) throws -> String? {
        try writer.write { db in
            guard let photo = try AmbientPhoto.fetchOne(db, id: id) else { return nil }
            _ = try photo.delete(db)
            return photo.fileName
        }
    }

    /// Removes several photos in one transaction. Returns the file names of those that existed.
    func removeAmbientPhotos(ids: [Int64]) throws -> [String] {
        try writer.write { db in
            let photos = try AmbientPhoto.fetchAll(db, keys: ids)
            for photo in photos { _ = try photo.delete(db) }
            return photos.map(\.fileName)
        }
    }

    /// Every photo file name still referenced, for cleaning up orphaned images.
    func ambientPhotoFileNames() throws -> Set<String> {
        try writer.read { db in Set(try String.fetchAll(db, sql: "SELECT fileName FROM ambientPhoto")) }
    }
}

// MARK: - Reads

/// Everything the Home screens show, read in one consistent snapshot.
struct HomeSnapshot: Equatable, Sendable {
    var household: Household?
    var people: [Person] = []
    /// All chores, archived ones included (Settings shows them).
    var chores: [Chore] = []
    /// Completions from `since` on, plus every completion of a one-off chore.
    var completions: [ChoreCompletion] = []
    var rewards: [Reward] = []
    /// Stars earned from chores and care, from the same window as `completions`.
    var earnings: [StarEarning] = []
    /// Every star each person has ever earned.
    var lifetimeStars: [Int64: Int] = [:]
    /// Rewards cashed in, newest first.
    var redemptions: [RewardRedemption] = []
    var lists: [HomeList] = []
    var items: [ListItem] = []
    var meals: [MealPlan] = []
    var photos: [AmbientPhoto] = []

    static let empty = HomeSnapshot()

    /// Reads the household's Home data. Completions and meals are limited to what the screens
    /// can show: the window from `since` and every active reward's start day.
    static func fetch(_ db: Database, since: DayKey) throws -> HomeSnapshot {
        guard let household = try Household.order(Column("id")).fetchOne(db), let householdId = household.id else {
            return .empty
        }
        let people = try Person.filter(Column("householdId") == householdId).order(Column("sortOrder"), Column("id")).fetchAll(db)
        let chores = try Chore.filter(Column("householdId") == householdId).order(Column("sortOrder"), Column("id")).fetchAll(db)
        let rewards = try Reward.filter(Column("householdId") == householdId).order(Column("sortOrder"), Column("id")).fetchAll(db)
        let rewardStart = rewards.filter { !$0.archived }.map(\.startDay).min() ?? since.rawValue
        let from = min(rewardStart, since.rawValue)
        let completions = try ChoreCompletion.fetchAll(db, sql: """
            SELECT cc.* FROM choreCompletion cc JOIN chore c ON c.id = cc.choreId
            WHERE c.householdId = ? AND (cc.day >= ? OR c.repeatKind = 'once')
            ORDER BY cc.day, cc.id
            """, arguments: [householdId, from])
        let earnings = try StarLedger.earnings(db, householdId: householdId, from: DayKey(rawValue: from), calendar: household.calendar)
        let lifetimeStars = try StarLedger.lifetimeStars(db, householdId: householdId)
        let redemptions = try RewardRedemption.fetchAll(db, sql: """
            SELECT rr.* FROM rewardRedemption rr JOIN reward r ON r.id = rr.rewardId
            WHERE r.householdId = ? ORDER BY rr.redeemedAt DESC, rr.id DESC
            """, arguments: [householdId])
        let lists = try HomeList.filter(Column("householdId") == householdId).order(Column("sortOrder"), Column("id")).fetchAll(db)
        let items = try ListItem.fetchAll(db, sql: """
            SELECT i.* FROM listItem i JOIN homeList l ON l.id = i.listId
            WHERE l.householdId = ? ORDER BY l.sortOrder, i.listId, i.sortOrder, i.id
            """, arguments: [householdId])
        let meals = try MealPlan
            .filter(Column("householdId") == householdId && Column("day") >= since.rawValue)
            .order(Column("day"))
            .fetchAll(db)
        let photos = try AmbientPhoto.filter(Column("householdId") == householdId).order(Column("createdAt"), Column("id")).fetchAll(db)
        return HomeSnapshot(
            household: household, people: people, chores: chores, completions: completions, rewards: rewards,
            earnings: earnings, lifetimeStars: lifetimeStars, redemptions: redemptions, lists: lists, items: items, meals: meals, photos: photos
        )
    }
}

/// Where every star comes from: chore completions and care logs, read side by side.
enum StarLedger {
    /// Earnings on or after `from`, oldest first. Care given together credits everyone who helped.
    static func earnings(_ db: Database, householdId: Int64, from: DayKey, calendar: Calendar) throws -> [StarEarning] {
        let chores = try Row.fetchAll(db, sql: """
            SELECT cc.id, cc.choreId, cc.personId, cc.stars, cc.day, cc.completedAt, c.title, c.emoji
            FROM choreCompletion cc JOIN chore c ON c.id = cc.choreId
            WHERE c.householdId = ? AND cc.day >= ? AND cc.stars > 0
            """, arguments: [householdId, from.rawValue]).map { row in
            StarEarning(
                source: .chore(choreId: row["choreId"], completionId: row["id"]),
                personId: row["personId"], stars: row["stars"], day: DayKey(rawValue: row["day"]),
                at: row["completedAt"], recordedAt: row["completedAt"], title: row["title"], emoji: (row["emoji"] as String?) ?? "✅"
            )
        }
        // A day before `from` covers time zones; days are then computed in the household's calendar.
        let since = from.adding(days: -1, calendar: calendar).startDate(in: calendar)
        let care = try Row.fetchAll(db, sql: """
            SELECT l.id, l.careRoutineId, l.occurredAt, l.createdAt, l.stars, p.personId, r.title, r.emoji, c.name
            FROM careLog l
            JOIN careLogPerson p ON p.careLogId = l.id
            JOIN careRoutine r ON r.id = l.careRoutineId
            JOIN companion c ON c.id = r.companionId
            WHERE c.householdId = ? AND l.occurredAt >= ? AND l.stars > 0
            """, arguments: [householdId, since]).compactMap { row -> StarEarning? in
            let at: Date = row["occurredAt"]
            let day = DayKey(at, calendar: calendar)
            guard day >= from else { return nil }
            let routine: String = row["title"]
            let name: String = row["name"]
            return StarEarning(
                source: .care(routineId: row["careRoutineId"], logId: row["id"]),
                personId: row["personId"], stars: row["stars"], day: day,
                at: at, recordedAt: row["createdAt"], title: "\(routine) \(name)", emoji: row["emoji"]
            )
        }
        return (chores + care).sorted { ($0.at, $0.id) < ($1.at, $1.id) }
    }

    /// Every star each person has earned, ever.
    static func lifetimeStars(_ db: Database, householdId: Int64) throws -> [Int64: Int] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT personId, SUM(stars) AS stars FROM (
                SELECT cc.personId, cc.stars FROM choreCompletion cc JOIN chore c ON c.id = cc.choreId
                WHERE c.householdId = ? AND cc.personId IS NOT NULL
                UNION ALL
                SELECT p.personId, l.stars FROM careLog l
                JOIN careLogPerson p ON p.careLogId = l.id
                JOIN careRoutine r ON r.id = l.careRoutineId
                JOIN companion c ON c.id = r.companionId
                WHERE c.householdId = ?
            ) GROUP BY personId
            """, arguments: [householdId, householdId])
        return Dictionary(rows.map { ($0["personId"] as Int64, $0["stars"] as Int) }, uniquingKeysWith: +)
    }
}

extension AppDatabase {
    func homeSnapshot(since: DayKey) throws -> HomeSnapshot {
        try writer.read { try HomeSnapshot.fetch($0, since: since) }
    }

    func homeUpdates(since: DayKey) -> AsyncValueObservation<HomeSnapshot> {
        ValueObservation
            .tracking { try HomeSnapshot.fetch($0, since: since) }
            .removeDuplicates()
            .values(in: writer)
    }
}
