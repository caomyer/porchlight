import Foundation
import Observation

/// Live chores, lists, meals and ambient photos. Mirrors the database and forwards edits to it.
@MainActor
@Observable
final class HomeStore {
    let database: AppDatabase
    let photoLibrary: AmbientPhotoLibrary

    private(set) var snapshot: HomeSnapshot = .empty
    /// Today in the household's time zone. Rolls over at midnight.
    private(set) var today: DayKey
    /// The last failed edit, shown near the control that caused it.
    var lastError: String?

    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var dayWatch: Task<Void, Never>?

    init(database: AppDatabase, photoLibrary: AmbientPhotoLibrary = .shared) {
        self.database = database
        self.photoLibrary = photoLibrary
        let household = try? database.snapshot().household
        today = DayKey(.now, calendar: household?.calendar ?? .current)
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
    var householdId: Int64? { snapshot.household?.id }
    var week: HomeWeek { HomeWeek(containing: today, calendar: calendar) }

    var activeChores: [Chore] { snapshot.chores.filter { !$0.archived } }

    func board(people: [Person]) -> ChoreBoard {
        ChoreBoard(
            people: people, chores: snapshot.chores, completions: snapshot.completions,
            rewards: snapshot.rewards, today: today, calendar: calendar
        )
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

    /// Completions and meals are read from two weeks before this week, enough for every screen.
    private static func windowStart(for today: DayKey, calendar: Calendar) -> DayKey {
        HomeWeek(containing: today, calendar: calendar).first.adding(days: -14, calendar: calendar)
    }

    private func observe() {
        observation?.cancel()
        let since = Self.windowStart(for: today, calendar: calendar)
        observation = Task { [weak self, database] in
            do {
                for try await snapshot in database.homeUpdates(since: since) {
                    self?.snapshot = snapshot
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
                let now = DayKey(.now, calendar: self.calendar)
                if now != self.today {
                    self.today = now
                    self.observe()
                }
            }
        }
    }

    // MARK: Chores

    @discardableResult
    func saveChore(_ draft: ChoreDraft, id: Int64? = nil) -> Bool {
        guard let householdId else { return false }
        return perform { try database.saveChore(draft, id: id, householdId: householdId) }
    }

    func setArchived(_ chore: Chore, _ archived: Bool) {
        guard let id = chore.id else { return }
        perform { try database.setChoreArchived(id: id, archived: archived) }
    }

    func delete(_ chore: Chore) {
        guard let id = chore.id else { return }
        perform { try database.deleteChore(id: id) }
    }

    /// Checks a chore off for today (or another day), crediting `personId` for "Anyone" chores.
    func toggle(_ chore: Chore, on day: DayKey? = nil, by personId: Int64? = nil) {
        guard let id = chore.id else { return }
        perform { try database.toggleChore(id: id, day: day ?? today, personId: personId) }
    }

    // MARK: Rewards

    @discardableResult
    func saveReward(_ draft: RewardDraft, id: Int64? = nil) -> Bool {
        guard let householdId else { return false }
        return perform { try database.saveReward(draft, id: id, householdId: householdId, today: today) }
    }

    func restart(_ reward: Reward) {
        guard let id = reward.id else { return }
        perform { try database.restartReward(id: id, from: today) }
    }

    func setArchived(_ reward: Reward, _ archived: Bool) {
        guard let id = reward.id else { return }
        perform { try database.setRewardArchived(id: id, archived: archived) }
    }

    func delete(_ reward: Reward) {
        guard let id = reward.id else { return }
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
        guard let id = list.id else { return false }
        return perform { try database.renameList(id: id, to: title) }
    }

    func delete(_ list: HomeList) {
        guard let id = list.id else { return }
        perform { try database.deleteList(id: id) }
    }

    @discardableResult
    func addItem(_ title: String, to list: HomeList, section: String? = nil, addedBy: Int64?) -> Bool {
        guard let id = list.id else { return false }
        return perform { try database.addListItem(title: title, to: id, section: section, addedBy: addedBy) }
    }

    @discardableResult
    func update(_ item: ListItem, title: String, section: String?) -> Bool {
        guard let id = item.id else { return false }
        return perform { try database.updateListItem(id: id, title: title, section: section) }
    }

    func toggle(_ item: ListItem) {
        guard let id = item.id else { return }
        perform { try database.setListItemChecked(id: id, checked: !item.checked) }
    }

    func delete(_ item: ListItem) {
        guard let id = item.id else { return }
        perform { try database.deleteListItem(id: id) }
    }

    func clearChecked(in list: HomeList) {
        guard let id = list.id else { return }
        perform { try database.clearCheckedItems(listId: id) }
    }

    // MARK: Meals

    @discardableResult
    func setMeal(on day: DayKey, title: String, emoji: String?) -> Bool {
        guard let householdId else { return false }
        return perform { try database.setMeal(day: day, title: title, emoji: emoji, householdId: householdId) }
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

    func remove(_ photo: AmbientPhoto) {
        guard let id = photo.id else { return }
        perform {
            if let fileName = try database.removeAmbientPhoto(id: id) {
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
