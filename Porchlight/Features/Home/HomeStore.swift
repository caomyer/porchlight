import Foundation
import Observation

/// Live chores, lists, meals and ambient photos. Mirrors the database and forwards edits to it.
@MainActor
@Observable
final class HomeStore: StoredFirstObservable {
    let database: AppDatabase
    let photoLibrary: AmbientPhotoLibrary

    /// What the database says now, stored before observers are told (see `AppModel.snapshot`).
    private(set) var snapshot: HomeSnapshot {
        get {
            access(keyPath: \.snapshot)
            return storedSnapshot
        }
        set {
            storedSnapshot = newValue
            withMutation(keyPath: \.snapshot) {}
        }
    }

    @ObservationIgnored private var storedSnapshot: HomeSnapshot = .empty
    /// Today in the household's time zone. Rolls over at midnight, from a timer, so it is
    /// stored before observers hear (`StoredFirst`).
    @ObservationIgnored @StoredFirst private(set) var today: DayKey
    /// The last failed edit, shown near the control that caused it.
    @ObservationIgnored @StoredFirst var lastError: String? = nil

    @ObservationIgnored private var observation: Task<Void, Never>?
    /// The earliest day a screen asked for (the calendar paging back), when before the usual window.
    @ObservationIgnored private var requestedStart: DayKey?
    @ObservationIgnored private var dayWatch: Task<Void, Never>?

    init(database: AppDatabase, photoLibrary: AmbientPhotoLibrary = .shared) {
        self.database = database
        self.photoLibrary = photoLibrary
        let household = try? database.snapshot().household
        today = DayKey(CompanionClock.now(), calendar: household?.calendar ?? .current)
        // Read synchronously once so the first frame has data, then keep listening.
        if let first = try? database.homeSnapshot(since: Self.windowStart(for: today, calendar: household?.calendar ?? .current)) {
            snapshot = first
        }
        observe()
        watchForNewDay()
        if let keep = try? database.ambientPhotoFileNames() {
            Task { [photoLibrary] in await photoLibrary.removeFiles(notIn: keep) }
        }
    }

    // MARK: Derived

    var calendar: Calendar { snapshot.household?.calendar ?? .current }
    var householdId: Household.ID? { snapshot.household?.id }
    var week: HomeWeek { HomeWeek(containing: today, calendar: calendar) }

    var activeChores: [Chore] { snapshot.chores.filter { !$0.archived } }

    func board(people: [Person], care: [CareTask] = []) -> ChoreBoard {
        ChoreBoard(
            people: people, chores: snapshot.chores, completions: snapshot.completions,
            earnings: snapshot.earnings, redemptions: snapshot.redemptions, care: care,
            rewards: snapshot.rewards, today: today, calendar: calendar
        )
    }

    /// Stars a reward has earned in its current round.
    func earned(toward reward: Reward) -> Int {
        RewardProgress.earned(for: reward, earnings: snapshot.earnings, redemptions: snapshot.redemptions)
    }

    /// "about 3 days away at this pace" for a reward still being saved for, when the last
    /// two weeks give enough to go on (`RewardPace`).
    func pace(of status: ChoreBoard.RewardStatus) -> String? {
        RewardPace.daysAway(status.reward, earned: status.earned, earnings: snapshot.earnings, today: today, calendar: calendar)
            .map(RewardPace.words)
    }

    /// The day to open a chore on from outside the board: today if it was done or is due
    /// today, a one-off's done day, or else the latest day this week it was due.
    func dayToOpen(_ chore: Chore) -> DayKey {
        if chore.recurrence.isOnce {
            return snapshot.completions.first { $0.choreId == chore.id }?.dayKey ?? today
        }
        if completion(of: chore, on: today) != nil || ChoreSchedule.occurs(chore, on: today, calendar: calendar) { return today }
        return week.days.filter { $0 <= today }.reversed().first {
            completion(of: chore, on: $0) != nil || ChoreSchedule.occurs(chore, on: $0, calendar: calendar)
        } ?? today
    }

    /// The completion of a chore on a day, if it was done.
    func completion(of chore: Chore, on day: DayKey) -> ChoreCompletion? {
        snapshot.completions.first { $0.choreId == chore.id && $0.dayKey == day }
    }

    func meal(on day: DayKey) -> MealPlan? {
        snapshot.meals.first { $0.dayKey == day }
    }

    func items(in list: HomeList) -> [ListItem] {
        snapshot.items.filter { $0.listId == list.id }
    }

    func lists(of kind: ListKind) -> [HomeList] {
        snapshot.lists.filter { $0.kind == kind }
    }

    /// Imported photos as file URLs, oldest first.
    var photoURLs: [URL] {
        snapshot.photos.map { photoLibrary.url(for: $0.fileName) }
    }

    // MARK: Observation

    /// Completions and meals are read from two weeks before this week, enough for every screen
    /// but the calendar, which widens the window with `include(from:)` as it pages back.
    private static func windowStart(for today: DayKey, calendar: Calendar) -> DayKey {
        HomeWeek(containing: today, calendar: calendar).first.adding(days: -14, calendar: calendar)
    }

    private var since: DayKey {
        let usual = Self.windowStart(for: today, calendar: calendar)
        return requestedStart.map { min($0, usual) } ?? usual
    }

    /// Makes sure completions from `day` on are loaded, for a calendar showing older weeks.
    func include(from day: DayKey) {
        guard day < since else { return }
        requestedStart = day
        // Read synchronously so the newly shown weeks don't flash empty, then keep listening.
        if let wider = try? database.homeSnapshot(since: day) { snapshot = wider }
        observe()
    }

    private func observe() {
        observation?.cancel()
        let since = since
        observation = Task { [weak self, database] in
            do {
                for try await snapshot in database.homeUpdates(since: since) {
                    guard let self else { return }
                    // Another household may keep another time zone: today follows it at once.
                    let switched = snapshot.household?.id != self.snapshot.household?.id
                    self.snapshot = snapshot
                    if switched {
                        let today = DayKey(CompanionClock.now(), calendar: self.calendar)
                        if today != self.today { self.today = today }
                    }
                }
            } catch is CancellationError {
            } catch {
                self?.lastError = error.userMessage
            }
        }
    }

    /// Moves `today` forward at midnight (and when the app comes back after a long sleep).
    private func watchForNewDay() {
        dayWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                let now = DayKey(CompanionClock.now(), calendar: self.calendar)
                if now != self.today {
                    self.today = now
                    self.observe()
                }
            }
        }
    }

    // MARK: Chores

    @discardableResult
    func saveChore(_ draft: ChoreDraft, id: Chore.ID? = nil) -> Bool {
        guard let householdId else { return false }
        return perform { try database.saveChore(draft, id: id, householdId: householdId) }
    }

    func setArchived(_ chore: Chore, _ archived: Bool) {
        let id = chore.id
        perform { try database.setChoreArchived(id: id, archived: archived) }
    }

    func delete(_ chore: Chore) {
        let id = chore.id
        perform { try database.deleteChore(id: id) }
    }

    /// Marks who did a chore on a day (checking it off if it wasn't).
    func credit(_ chore: Chore, on day: DayKey, to personId: Person.ID) {
        let id = chore.id
        perform { try database.creditChore(id: id, day: day, personId: personId) }
    }

    /// Checks a chore off for today (or another day), crediting `personId` for "Anyone" chores.
    func toggle(_ chore: Chore, on day: DayKey? = nil, by personId: Person.ID? = nil) {
        let id = chore.id
        perform { try database.toggleChore(id: id, day: day ?? today, personId: personId) }
    }

    /// Checks a chore off today unless it is already done, crediting `personId` for
    /// "Anyone" chores. Nil, with `lastError` set, when it is rejected.
    func complete(_ chore: Chore, by personId: Person.ID?, now: Date = CompanionClock.now()) -> ChoreCheckOff? {
        let id = chore.id
        let day = today
        var result: ChoreCheckOff?
        perform { result = try database.completeChore(id: id, day: day, personId: personId, now: now) }
        return result
    }

    /// Undoes one check-off.
    func undo(_ completion: ChoreCompletion) {
        let id = completion.id
        perform { try database.deleteChoreCompletion(id: id) }
    }

    // MARK: Rewards

    @discardableResult
    func saveReward(_ draft: RewardDraft, id: Reward.ID? = nil) -> Bool {
        guard let householdId else { return false }
        return perform { try database.saveReward(draft, id: id, householdId: householdId, today: today) }
    }

    /// Spends a reached reward's stars ("cash in") and starts it over. Returns the cash-in,
    /// or nil when it didn't happen (another tap or device already cashed this round in).
    @discardableResult
    func cashIn(_ reward: Reward, now: Date = CompanionClock.now()) -> RewardRedemption? {
        let id = reward.id
        let stars = earned(toward: reward)
        let known = snapshot.redemptions.first { $0.rewardId == id }?.id
        var cashedIn: RewardRedemption?
        perform {
            do {
                cashedIn = try database.cashInReward(id: id, stars: stars, day: today, after: known, now: now)
            } catch HomeValidationError.alreadyCashedIn {
                // A second tap before the board refreshed: the first one already did it.
            }
        }
        return cashedIn
    }

    /// Starts a reward over without cashing it in.
    func restart(_ reward: Reward) {
        let id = reward.id
        perform { try database.restartReward(id: id, from: today) }
    }

    func setArchived(_ reward: Reward, _ archived: Bool) {
        let id = reward.id
        perform { try database.setRewardArchived(id: id, archived: archived) }
    }

    func delete(_ reward: Reward) {
        let id = reward.id
        perform { try database.deleteReward(id: id) }
    }

    // MARK: Lists

    func ensureDefaultLists() {
        guard let householdId, snapshot.lists.isEmpty else { return }
        perform { try database.ensureDefaultLists(householdId: householdId) }
    }

    @discardableResult
    func createList(title: String, kind: ListKind) -> Bool {
        guard let householdId else { return false }
        return perform { try database.createList(title: title, kind: kind, householdId: householdId) }
    }

    @discardableResult
    func rename(_ list: HomeList, to title: String) -> Bool {
        let id = list.id
        return perform { try database.renameList(id: id, to: title) }
    }

    func delete(_ list: HomeList) {
        let id = list.id
        perform { try database.deleteList(id: id) }
    }

    @discardableResult
    func addItem(_ title: String, to list: HomeList, section: String? = nil, addedBy: Person.ID?) -> Bool {
        let id = list.id
        return perform { try database.addListItem(title: title, to: id, section: section, addedBy: addedBy) }
    }

    @discardableResult
    func update(_ item: ListItem, title: String, section: String?) -> Bool {
        let id = item.id
        return perform { try database.updateListItem(id: id, title: title, section: section) }
    }

    func toggle(_ item: ListItem) {
        let id = item.id
        perform { try database.setListItemChecked(id: id, checked: !item.checked) }
    }

    func delete(_ item: ListItem) {
        let id = item.id
        perform { try database.deleteListItem(id: id) }
    }

    func clearChecked(in list: HomeList) {
        let id = list.id
        perform { try database.clearCheckedItems(listId: id) }
    }

    // MARK: Meals

    @discardableResult
    func setMeal(on day: DayKey, title: String, emoji: String?, dishId: Dish.ID? = nil) -> Bool {
        guard let householdId else { return false }
        return perform { try database.setMeal(day: day, title: title, emoji: emoji, householdId: householdId, dishId: dishId) }
    }

    /// Adds a recipe's ingredients to a list as items to buy, one each, in their aisles
    /// (docs/design/dishes.md, "Recipes"). Returns the items added, for Undo.
    func addIngredients(_ lines: [String], to list: HomeList, addedBy: Person.ID?) -> [ListItem] {
        let titles = lines.map(Ingredient.groceryName)
        do {
            let added = try database.addListItems(titles: titles, to: list.id, addedBy: addedBy)
            lastError = nil
            return added
        } catch {
            lastError = error.userMessage
            return []
        }
    }

    /// Takes back what `addIngredients` added.
    func removeItems(_ items: [ListItem]) {
        let ids = items.map(\.id)
        perform { try database.deleteListItems(ids: ids) }
    }

    // MARK: Ambient photos

    /// Downsizes and stores picked images, then records them. Returns how many were added.
    @discardableResult
    func importPhotos(_ datas: [Data]) async -> Int {
        guard let householdId else { return 0 }
        var added = 0
        for data in datas {
            do {
                let stored = try await photoLibrary.store(data)
                try database.addAmbientPhoto(fileName: stored.fileName, caption: stored.caption, householdId: householdId)
                added += 1
            } catch {
                lastError = error.userMessage
            }
        }
        return added
    }

    func remove(_ photos: [AmbientPhoto]) {
        let ids = photos.map(\.id)
        guard !ids.isEmpty else { return }
        perform {
            for fileName in try database.removeAmbientPhotos(ids: ids) {
                photoLibrary.removeFile(named: fileName)
            }
        }
    }

    // MARK: Errors

    @discardableResult
    private func perform(_ work: () throws -> Void) -> Bool {
        do {
            try work()
            lastError = nil
            return true
        } catch {
            lastError = error.userMessage
            return false
        }
    }
}
