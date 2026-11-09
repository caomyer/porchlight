import Foundation
import GRDB
import Testing
import UIKit
@testable import Porchlight

/// Writes, validation and the snapshot read, against an in-memory database.
@Suite("Home database")
struct HomeDatabaseTests {
    private let db: AppDatabase
    private let householdId: Int64
    private let a: Int64
    private let b: Int64
    private let today = DayKey(rawValue: "2026-11-04")

    init() throws {
        db = try AppDatabase.inMemory()
        let household = try db.createHousehold(
            name: "Home",
            people: [PersonDraft(name: "A", color: .blue), PersonDraft(name: "B", color: .coral)],
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        householdId = try #require(household.id)
        let people = try db.snapshot().people
        a = try #require(people[0].id)
        b = try #require(people[1].id)
    }

    private func snapshot() throws -> HomeSnapshot {
        try db.homeSnapshot(since: DayKey(rawValue: "2026-10-01"))
    }

    private func draft(_ title: String = "Dishes", owner: Int64?, _ recurrence: Recurrence = .daily, stars: Int = 1) -> ChoreDraft {
        ChoreDraft(title: title, emoji: "🍽️", ownerId: owner, recurrence: recurrence, anchorDay: DayKey(rawValue: "2026-11-01"), timeHint: " after dinner ", stars: stars)
    }

    // MARK: Chores

    @Test("Saving a chore trims text and keeps the recurrence")
    func saveChore() throws {
        let chore = try db.saveChore(draft("  Dishes ", owner: a, .weekdays([2, 4])), householdId: householdId)
        let stored = try #require(try snapshot().chores.first)
        #expect(stored.id == chore.id)
        #expect(stored.title == "Dishes")
        #expect(stored.timeHint == "after dinner")
        #expect(stored.emoji == "🍽️")
        #expect(stored.recurrence == .weekdays([2, 4]))
        #expect(stored.owner == .person(a))

        var edited = draft("Dishes", owner: nil, .everyNDays(2), stars: 3)
        edited.timeHint = ""
        try db.saveChore(edited, id: chore.id, householdId: householdId)
        let updated = try #require(try snapshot().chores.first)
        #expect(updated.owner == .everyone)
        #expect(updated.recurrence == .everyNDays(2))
        #expect(updated.timeHint == nil)
        #expect(updated.stars == 3)
        #expect(try snapshot().chores.count == 1)
    }

    @Test("Chore validation", arguments: [
        (ChoreDraft(title: "  ", anchorDay: DayKey(rawValue: "2026-11-01")), HomeValidationError.emptyTitle),
        (ChoreDraft(title: String(repeating: "x", count: 61), anchorDay: DayKey(rawValue: "2026-11-01")), .titleTooLong(limit: 60)),
        (ChoreDraft(title: "T", recurrence: .weekdays([]), anchorDay: DayKey(rawValue: "2026-11-01")), .noWeekdays),
        (ChoreDraft(title: "T", recurrence: .everyNDays(0), anchorDay: DayKey(rawValue: "2026-11-01")), .intervalOutOfRange(1...365)),
        (ChoreDraft(title: "T", anchorDay: DayKey(rawValue: "2026-11-01"), stars: 21), .starsOutOfRange(0...20)),
        (ChoreDraft(title: "T", anchorDay: DayKey(rawValue: "2026-11-01"), timeHint: String(repeating: "x", count: 31)), .hintTooLong(limit: 30)),
        (ChoreDraft(title: "T", anchorDay: DayKey(rawValue: "soon")), .invalidDay),
    ])
    func choreValidation(draft: ChoreDraft, error: HomeValidationError) throws {
        #expect(throws: error) { try db.saveChore(draft, householdId: householdId) }
    }

    @Test("A chore can't belong to someone outside the household")
    func choreOwnerValidation() throws {
        let other = try db.writer.write { db -> Int64 in
            var household = Household(name: "Other", timeZoneIdentifier: "UTC", firstWeekday: 1, setupCompleted: true, createdAt: .now)
            try household.insert(db)
            var person = Person(householdId: household.id!, name: "Z", color: .sage, sortOrder: 0, createdAt: .now)
            try person.insert(db)
            return person.id!
        }
        #expect(throws: HomeValidationError.unknownPerson) {
            try db.saveChore(draft(owner: other), householdId: householdId)
        }
    }

    @Test("Toggling credits the owner, snapshots stars, and undoes")
    func toggleOwned() throws {
        let chore = try db.saveChore(draft(owner: a, stars: 2), householdId: householdId)
        let id = try #require(chore.id)
        #expect(try db.toggleChore(id: id, day: today, personId: b))
        var completion = try #require(try snapshot().completions.first)
        // The owner gets the credit even if someone else tapped.
        #expect(completion.personId == a)
        #expect(completion.stars == 2)
        #expect(completion.dayKey == today)

        // Changing the star value later doesn't rewrite history.
        try db.saveChore(draft(owner: a, stars: 5), id: id, householdId: householdId)
        completion = try #require(try snapshot().completions.first)
        #expect(completion.stars == 2)

        #expect(try db.toggleChore(id: id, day: today, personId: nil) == false)
        #expect(try snapshot().completions.isEmpty)
    }

    @Test("Anyone chores need to know who did them")
    func toggleShared() throws {
        let chore = try db.saveChore(draft(owner: nil), householdId: householdId)
        let id = try #require(chore.id)
        #expect(throws: HomeValidationError.unknownPerson) { try db.toggleChore(id: id, day: today, personId: nil) }
        try db.toggleChore(id: id, day: today, personId: b)
        #expect(try snapshot().completions.map(\.personId) == [b])
    }

    @Test("Completions are per day")
    func completionsPerDay() throws {
        let id = try #require(try db.saveChore(draft(owner: a), householdId: householdId).id)
        try db.toggleChore(id: id, day: today, personId: nil)
        try db.toggleChore(id: id, day: today.adding(days: -1, calendar: HomeLogicTests.calendar), personId: nil)
        #expect(try snapshot().completions.map(\.day) == ["2026-11-03", "2026-11-04"])
    }

    @Test("A one-off chore is done once: doing it another day moves the completion")
    func toggleOnce() throws {
        let id = try #require(try db.saveChore(draft(owner: a, .once), householdId: householdId).id)
        try db.toggleChore(id: id, day: DayKey(rawValue: "2026-11-02"), personId: nil)
        try db.toggleChore(id: id, day: today, personId: nil)
        #expect(try snapshot().completions.map(\.day) == ["2026-11-04"])
    }

    @Test("Week star totals add up through the store's board")
    func weekStars() throws {
        let mine = try #require(try db.saveChore(draft("Mine", owner: a, stars: 2), householdId: householdId).id)
        let shared = try #require(try db.saveChore(draft("Shared", owner: nil, stars: 3), householdId: householdId).id)
        try db.toggleChore(id: mine, day: today, personId: nil)
        try db.toggleChore(id: mine, day: DayKey(rawValue: "2026-11-02"), personId: nil)
        try db.toggleChore(id: mine, day: DayKey(rawValue: "2026-10-30"), personId: nil) // last week
        try db.toggleChore(id: shared, day: today, personId: b)
        let snap = try snapshot()
        let household = try #require(snap.household)
        let board = ChoreBoard(people: snap.people, chores: snap.chores, completions: snap.completions, earnings: snap.earnings, rewards: snap.rewards, today: today, calendar: household.calendar)
        let stars = Dictionary(uniqueKeysWithValues: board.columns.map { ($0.owner, $0.weekStars) })
        #expect(stars == [.person(a): 4, .person(b): 3, .everyone: 3])
    }

    @Test("Archiving hides a chore but keeps its stars; deleting removes them")
    func archiveAndDelete() throws {
        let id = try #require(try db.saveChore(draft(owner: a), householdId: householdId).id)
        try db.toggleChore(id: id, day: today, personId: nil)
        try db.setChoreArchived(id: id, archived: true)
        #expect(try snapshot().chores.first?.archived == true)
        #expect(try snapshot().completions.count == 1)
        try db.deleteChore(id: id)
        #expect(try snapshot().chores.isEmpty)
        #expect(try snapshot().completions.isEmpty)
    }

    @Test("Removing a person makes their chores shared and keeps shared-goal stars")
    func removePerson() throws {
        let id = try #require(try db.saveChore(draft(owner: b), householdId: householdId).id)
        try db.toggleChore(id: id, day: today, personId: nil)
        try db.saveReward(RewardDraft(title: "Spa", targetStars: 10, ownerId: b), householdId: householdId, today: today)
        try db.deletePerson(id: b)
        let snap = try snapshot()
        #expect(snap.chores.first?.ownerId == nil)
        #expect(snap.completions.first?.personId == nil)
        #expect(snap.completions.first?.stars == 1)
        #expect(snap.rewards.isEmpty)
    }

    // MARK: Rewards

    @Test("Rewards validate, save and restart")
    func rewards() throws {
        #expect(throws: HomeValidationError.emptyTitle) {
            try db.saveReward(RewardDraft(title: " "), householdId: householdId, today: today)
        }
        #expect(throws: HomeValidationError.targetOutOfRange(1...10_000)) {
            try db.saveReward(RewardDraft(title: "X", targetStars: 0), householdId: householdId, today: today)
        }
        let reward = try db.saveReward(RewardDraft(title: " Date night ", emoji: "🍷", targetStars: 100, ownerId: nil), householdId: householdId, today: today)
        let id = try #require(reward.id)
        var stored = try #require(try snapshot().rewards.first)
        #expect(stored.title == "Date night")
        #expect(stored.isShared)
        #expect(stored.startDay == "2026-11-04")

        let chore = try #require(try db.saveChore(draft(owner: a, stars: 4), householdId: householdId).id)
        try db.toggleChore(id: chore, day: today, personId: nil)
        #expect(RewardProgress.earned(for: stored, earnings: try snapshot().earnings) == 4)

        try db.restartReward(id: id, from: DayKey(rawValue: "2026-11-05"))
        stored = try #require(try snapshot().rewards.first)
        #expect(RewardProgress.earned(for: stored, earnings: try snapshot().earnings) == 0)

        try db.setRewardArchived(id: id, archived: true)
        #expect(try snapshot().rewards.first?.archived == true)
        try db.deleteReward(id: id)
        #expect(try snapshot().rewards.isEmpty)
    }

    @Test("The snapshot reads completions back to the oldest active reward")
    func snapshotWindow() throws {
        let chore = try #require(try db.saveChore(draft(owner: a), householdId: householdId).id)
        try db.toggleChore(id: chore, day: DayKey(rawValue: "2026-08-01"), personId: nil)
        try db.toggleChore(id: chore, day: DayKey(rawValue: "2026-09-15"), personId: nil)
        try db.toggleChore(id: chore, day: today, personId: nil)
        let since = DayKey(rawValue: "2026-10-01")
        #expect(try db.homeSnapshot(since: since).completions.map(\.day) == ["2026-11-04"])
        let reward = try db.saveReward(RewardDraft(title: "Long goal", targetStars: 500), householdId: householdId, today: today)
        try db.restartReward(id: try #require(reward.id), from: DayKey(rawValue: "2026-09-01"))
        #expect(try db.homeSnapshot(since: since).completions.map(\.day) == ["2026-09-15", "2026-11-04"])
    }

    // MARK: Lists

    @Test("Default lists are created once")
    func defaultLists() throws {
        try db.ensureDefaultLists(householdId: householdId)
        try db.ensureDefaultLists(householdId: householdId)
        let lists = try snapshot().lists
        #expect(lists.map(\.kind) == [.grocery, .todo])
        #expect(lists.map(\.title) == ["Groceries", "To-do"])
    }

    @Test("Grocery items get a guessed section unless one is given; to-dos get none")
    func addItems() throws {
        let groceries = try db.createList(title: "Groceries", kind: .grocery, householdId: householdId)
        let todo = try db.createList(title: "House", kind: .todo, householdId: householdId)
        try db.addListItem(title: " Limes ", to: groceries.id!, addedBy: a)
        try db.addListItem(title: "Candles", to: groceries.id!, section: "For the party", addedBy: b)
        try db.addListItem(title: "Call the plumber", to: todo.id!, section: "Ignored", addedBy: nil)
        let items = try snapshot().items
        #expect(items.map(\.title) == ["Limes", "Candles", "Call the plumber"])
        #expect(items.map(\.section) == ["Produce", "For the party", nil])
        #expect(items.map(\.addedById) == [a, b, nil])
        #expect(items.map(\.sortOrder) == [0, 1, 0])
    }

    @Test("List items check off, edit, clear and delete")
    func itemLifecycle() throws {
        let list = try db.createList(title: "Groceries", kind: .grocery, householdId: householdId)
        let listId = try #require(list.id)
        let basil = try db.addListItem(title: "Basil", to: listId, addedBy: a)
        let rice = try db.addListItem(title: "Rice", to: listId, addedBy: a)
        let milk = try db.addListItem(title: "Milk", to: listId, addedBy: a)
        try db.setListItemChecked(id: basil.id!, checked: true)
        try db.setListItemChecked(id: rice.id!, checked: true)
        try db.setListItemChecked(id: rice.id!, checked: false)
        #expect(try snapshot().items.filter(\.checked).map(\.title) == ["Basil"])

        try db.updateListItem(id: milk.id!, title: "Oat milk", section: "")
        #expect(try snapshot().items.last?.title == "Oat milk")
        #expect(try snapshot().items.last?.section == "Dairy")
        try db.updateListItem(id: milk.id!, title: "Oat milk", section: "Drinks")
        #expect(try snapshot().items.last?.section == "Drinks")
        #expect(throws: HomeValidationError.emptyTitle) { try db.updateListItem(id: milk.id!, title: "", section: nil) }

        #expect(try db.clearCheckedItems(listId: listId) == 1)
        #expect(try snapshot().items.map(\.title) == ["Rice", "Oat milk"])
        try db.deleteListItem(id: rice.id!)
        #expect(try snapshot().items.map(\.title) == ["Oat milk"])
    }

    @Test("Lists rename and delete with their items; people must belong to the household")
    func listLifecycle() throws {
        let list = try db.createList(title: "Hardware", kind: .todo, householdId: householdId)
        try db.addListItem(title: "Screws", to: list.id!, addedBy: nil)
        try db.renameList(id: list.id!, to: " Hardware store ")
        #expect(try snapshot().lists.first?.title == "Hardware store")
        #expect(throws: HomeValidationError.emptyTitle) { try db.renameList(id: list.id!, to: "") }
        #expect(throws: HomeValidationError.unknownPerson) { try db.addListItem(title: "Nails", to: list.id!, addedBy: 9999) }
        try db.deleteList(id: list.id!)
        #expect(try snapshot().lists.isEmpty)
        #expect(try snapshot().items.isEmpty)
    }

    // MARK: Meals

    @Test("Meals set, guess an emoji, replace and clear")
    func meals() throws {
        try db.setMeal(day: today, title: " Taco night ", emoji: nil, householdId: householdId)
        var meal = try #require(try snapshot().meals.first)
        #expect(meal.title == "Taco night")
        #expect(meal.emoji == "🌮")
        try db.setMeal(day: today, title: "Leftovers", emoji: "🍲", householdId: householdId)
        meal = try #require(try snapshot().meals.first)
        #expect(meal.title == "Leftovers")
        #expect(meal.emoji == "🍲")
        #expect(try snapshot().meals.count == 1)
        try db.setMeal(day: today, title: "  ", emoji: nil, householdId: householdId)
        #expect(try snapshot().meals.isEmpty)
    }

    // MARK: Photos

    @Test("Ambient photo rows add and remove, returning the file to delete")
    func photos() throws {
        let photo = try db.addAmbientPhoto(fileName: "a.jpg", caption: "Aug 2026", householdId: householdId)
        #expect(try db.ambientPhotoFileNames() == ["a.jpg"])
        #expect(try db.removeAmbientPhoto(id: photo.id!) == "a.jpg")
        #expect(try db.removeAmbientPhoto(id: photo.id!) == nil)
        #expect(try snapshot().photos.isEmpty)
    }

    @Test("Deleting the household removes every Home row")
    func cascade() throws {
        let list = try db.createList(title: "L", kind: .grocery, householdId: householdId)
        try db.addListItem(title: "Basil", to: list.id!, addedBy: a)
        let chore = try db.saveChore(draft(owner: a), householdId: householdId)
        try db.toggleChore(id: chore.id!, day: today, personId: nil)
        try db.setMeal(day: today, title: "Soup", emoji: nil, householdId: householdId)
        try db.writer.write { db in _ = try Household.deleteAll(db) }
        let counts = try db.writer.read { db in
            try ["chore", "choreCompletion", "reward", "homeList", "listItem", "mealPlan", "ambientPhoto"].map {
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? -1
            }
        }
        #expect(counts == [0, 0, 0, 0, 0, 0, 0])
    }

    // MARK: One star ledger

    /// A dog with one walk routine worth `stars`, returning the routine id.
    private func dog(stars: Int = 2) throws -> Int64 {
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        draft.routines = [CareRoutineDraft(kind: .walk, windows: [.anyTime], stars: stars)]
        let id = try db.saveCompanion(draft, householdId: householdId)
        return try #require(try db.writer.read { db in try Int64.fetchOne(db, sql: "SELECT id FROM careRoutine WHERE companionId = ?", arguments: [id]) })
    }

    private func at(_ day: String, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(byAdding: .hour, value: hour, to: DayKey(rawValue: day).startDate(in: calendar))!
    }

    @Test("Care given and chores done both earn stars; care together credits everyone who helped")
    func ledger() throws {
        let walk = try dog(stars: 2)
        try db.logCare(routineId: walk, CareLogDraft(people: [a, b], occurredAt: at("2026-11-03", 8)), now: at("2026-11-04", 9))
        let chore = try db.saveChore(draft(owner: a, stars: 3), householdId: householdId)
        try db.toggleChore(id: chore.id!, day: today, personId: nil)
        let earnings = try snapshot().earnings
        #expect(earnings.count == 3)
        let carers: Set<Int64> = Set(earnings.filter(\.isCare).compactMap(\.personId))
        #expect(carers == [a, b])
        #expect(earnings.first { $0.isCare }?.title == "Walk Yo-Yo")
        #expect(earnings.first { $0.isCare }?.day == DayKey(rawValue: "2026-11-03"))
        let lifetime: [Int64: Int] = try snapshot().lifetimeStars
        #expect(lifetime == [a: 5, b: 2])
    }

    @Test("Rewards count care stars too, and cashing in records it and starts over")
    func cashIn() throws {
        let walk = try dog(stars: 4)
        let reward = try db.saveReward(RewardDraft(title: "Ice cream", emoji: "🍦", targetStars: 6, ownerId: a), householdId: householdId, today: DayKey(rawValue: "2026-11-01"))
        try db.logCare(routineId: walk, CareLogDraft(people: [a], occurredAt: at("2026-11-02", 8)), now: at("2026-11-04", 9))
        try db.logCare(routineId: walk, CareLogDraft(people: [a], occurredAt: at("2026-11-04", 8)), now: at("2026-11-04", 9))
        var home = try snapshot()
        #expect(RewardProgress.earned(for: home.rewards[0], earnings: home.earnings, redemptions: home.redemptions) == 8)

        try db.cashInReward(id: reward.id!, stars: 8, day: today, now: at("2026-11-04", 10))
        try db.logCare(routineId: walk, CareLogDraft(people: [a], occurredAt: at("2026-11-04", 11)), now: at("2026-11-04", 12))
        home = try snapshot()
        let redemption = try #require(home.redemptions.first)
        #expect(redemption.stars == 8 && redemption.personId == a && redemption.day == today.rawValue)
        // Only the walk after cashing in counts toward the next round, though it's the same day.
        #expect(RewardProgress.earned(for: home.rewards[0], earnings: home.earnings, redemptions: home.redemptions) == 4)
    }

    @Test("Saying who did a chore re-credits it, or checks it off for them")
    func credit() throws {
        let chore = try db.saveChore(draft(owner: a, stars: 2), householdId: householdId)
        try db.creditChore(id: chore.id!, day: today, personId: b)
        var done = try #require(try snapshot().completions.first)
        #expect(done.personId == b, "Anyone can pitch in on someone else's chore")
        try db.creditChore(id: chore.id!, day: today, personId: a)
        done = try #require(try snapshot().completions.first)
        #expect(done.personId == a)
        #expect(try snapshot().completions.count == 1)
    }

}

/// The photo importer, against a temporary folder.
@Suite("Ambient photo library")
struct AmbientPhotoLibraryTests {
    @Test("Imports downsize to JPEG and orphaned files are cleaned up")
    func importAndClean() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = AmbientPhotoLibrary(folder: folder)
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let stored = try await library.store(try #require(big.pngData()))
        let url = library.url(for: stored.fileName)
        let image = try #require(UIImage(contentsOfFile: url.path))
        #expect(max(image.size.width, image.size.height) == CGFloat(AmbientPhotoLibrary.maxPixelSize))
        #expect(stored.fileName.hasSuffix(".jpg"))

        await #expect(throws: AmbientPhotoLibrary.ImportError.self) { try await library.store(Data("nope".utf8)) }

        await library.removeFiles(notIn: [])
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
