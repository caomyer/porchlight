import Foundation
import GRDB
import Testing
@testable import Porchlight

@Suite("Dishes: saving, renaming, merging and tidying")
struct DishDatabaseTests {
    let db: AppDatabase
    let householdId: Household.ID
    let people: [Person]
    let journal: Journal

    init() throws {
        db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "The Lake House", people: [
            PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral), PersonDraft(name: "Ava", color: .ochre),
        ])
        householdId = household.id
        people = try db.snapshot().people
        journal = try db.ensureFoodJournal(householdId: householdId)
    }

    private var pho: PlaceDraft { PlaceDraft(name: "Pho Saigon House", address: "412 Valencia St") }

    private func meal(
        _ dishes: [DishLineDraft]?, source: MealSource = .dineOut, place: PlaceDraft? = nil, title: String = "",
        slot: String = "Dinner", at time: TimeInterval = 1_000, rating: MealRating? = nil
    ) throws -> JournalEntry {
        var draft = MealDraft(
            day: DayKey(rawValue: "2026-11-15"), slot: slot, source: source, title: title, rating: rating,
            eaterIds: people.map(\.id), eatenAt: Date(timeIntervalSince1970: time), place: place ?? (source.hasPlace ? pho : nil)
        )
        draft.dishes = dishes
        return try db.addMeal(draft, journalId: journal.id, now: Date(timeIntervalSince1970: time))
    }

    private func lines(_ entry: JournalEntry) throws -> [MealDish] {
        try db.writer.read { try MealDish.filter(Column("entryId") == entry.id).order(Column("sortOrder")).fetchAll($0) }
    }

    private func entry(_ id: JournalEntry.ID) throws -> JournalEntry {
        try #require(try db.writer.read { try JournalEntry.fetchOne($0, id: id) })
    }

    private func liveDishes() throws -> [Dish] {
        try db.writer.read { try Dish.filter(Column("mergedInto") == nil).order(Column("createdAt"), Column("id")).fetchAll($0) }
    }

    // MARK: Saving

    @Test("A meal's dishes are lines in order, and its title, face and picture are written from them")
    func savesLines() throws {
        let saved = try meal([
            DishLineDraft(name: "Pho tai", rating: .favorite), DishLineDraft(name: "Spring rolls", rating: .again), DishLineDraft(name: "Bun cha"),
        ])
        let lines = try lines(saved)
        #expect(lines.map(\.sortOrder) == [0, 1, 2])
        #expect(lines.map(\.rating) == [.favorite, .again, nil])
        let stored = try entry(saved.id)
        #expect(stored.title == "Pho tai, spring rolls, bun cha")
        #expect(stored.rating == .favorite)
        #expect(stored.emoji == "🍜")
        let dishes = try liveDishes()
        #expect(Set(dishes.map(\.name)) == ["Pho tai", "Spring rolls", "Bun cha"])
        #expect(Set(dishes.map(\.kitchen)) == [.place(try #require(stored.placeId))])
    }

    @Test("A meal with no dishes is a whole meal, titled by its slot, with its own face (L1, L3)")
    func noDishes() throws {
        let saved = try meal([], source: .company, slot: "Lunch", rating: .fine)
        #expect(try lines(saved).isEmpty)
        #expect(try entry(saved.id).title == "Lunch")
        #expect(try entry(saved.id).rating == .fine)
        // Faces are optional on dishes too.
        let unrated = try meal([DishLineDraft(name: "Pho tai")], at: 2_000)
        #expect(try entry(unrated.id).rating == nil)
    }

    @Test("A name typed again in the same kitchen is the same dish, whatever its case or accents (M3)")
    func sameDish() throws {
        _ = try meal([DishLineDraft(name: "Pho tai")])
        let again = try meal([DishLineDraft(name: " phở   TÁI ")], at: 2_000)
        #expect(try liveDishes().count == 1)
        #expect(try lines(again).first?.dishId == (try liveDishes()[0].id))
        // The dish keeps the name it was first given.
        #expect(try liveDishes()[0].name == "Pho tai")
    }

    @Test("The same name at two restaurants, or at home, is another dish")
    func kitchensKeepDishesApart() throws {
        _ = try meal([DishLineDraft(name: "Pho tai")])
        _ = try meal([DishLineDraft(name: "Pho tai")], place: PlaceDraft(name: "Pho 2000"), at: 2_000)
        _ = try meal([DishLineDraft(name: "Pho tai")], source: .home, at: 3_000)
        _ = try meal([DishLineDraft(name: "Pho tai")], source: .company, at: 4_000)
        let kinds = try liveDishes().map(\.kitchenKind)
        #expect(kinds == ["place", "place", "home", "elsewhere"])
    }

    @Test("A dish picked from another kitchen is looked up by name in the meal's own")
    func pickedFromElsewhere() throws {
        let home = try meal([DishLineDraft(name: "Pad thai")], source: .home)
        let homeDish = try #require(try lines(home).first?.dishId)
        let out = try meal([DishLineDraft(name: "Pad thai", dishId: homeDish)], at: 2_000)
        let outDish = try #require(try lines(out).first?.dishId)
        #expect(outDish != homeDish)
        #expect(try liveDishes().count == 2)
    }

    @Test("A dish of another household is never used")
    func householdScoping() throws {
        let other = try db.createHousehold(name: "Grandma's", people: [PersonDraft(name: "Grandma", color: .sage)])
        let foreign = Dish(householdId: other.id, name: "Dumplings", emoji: "🥟", tint: 0, kitchenKind: "home", createdAt: .now)
        try db.writer.write { try foreign.insert($0) }
        let saved = try meal([DishLineDraft(name: "Dumplings", dishId: foreign.id)], source: .home)
        let line = try #require(try lines(saved).first)
        #expect(line.dishId != foreign.id)
        let dish = try #require(try db.writer.read { try Dish.fetchOne($0, id: line.dishId) })
        #expect(dish.householdId == householdId)
    }

    @Test("The same dish twice is one line; more than 12 dishes or a long or blank name is refused (L6)")
    func limits() throws {
        let saved = try meal([DishLineDraft(name: "Pho tai"), DishLineDraft(name: "pho tai")])
        #expect(try lines(saved).count == 1)
        let thirteen = (1...13).map { DishLineDraft(name: "Dish \($0)") }
        #expect(throws: DishError.tooManyDishes(limit: 12)) { try meal(thirteen, at: 2_000) }
        #expect(throws: DishError.nameTooLong(limit: 60)) { try meal([DishLineDraft(name: String(repeating: "a", count: 61))], at: 3_000) }
        #expect(throws: DishError.emptyName) { try meal([DishLineDraft(name: " ! ")], at: 4_000) }
        // Nothing of a refused meal is saved.
        #expect(try db.foodSnapshot().entries.count == 1)
    }

    @Test("Editing keeps the lines of dishes still on the meal, with everyone's own faces (E1)")
    func editKeepsLines() throws {
        let saved = try meal([DishLineDraft(name: "Pho tai"), DishLineDraft(name: "Bun cha", rating: .fine)])
        let bunCha = try lines(saved)[1]
        try db.setPersonFace(lineId: bunCha.id, personId: people[2].id, .meh)
        var draft = MealDraft(day: saved.dayKey, slot: "Dinner", source: .dineOut, eaterIds: people.map(\.id), eatenAt: saved.eatenAt, place: pho)
        draft.dishes = [DishLineDraft(name: "Bun cha", rating: .fine), DishLineDraft(name: "Iced coffee", rating: .again)]
        try db.updateMeal(id: saved.id, draft)
        let after = try lines(saved)
        #expect(after.count == 2)
        #expect(after[0].id == bunCha.id)
        #expect(try db.writer.read { try MealDishRating.fetchCount($0) } == 1)
        #expect(try entry(saved.id).title == "Bun cha, iced coffee")
        // Taking every dish off leaves the meal, titled by its slot.
        draft.dishes = []
        try db.updateMeal(id: saved.id, draft)
        #expect(try lines(saved).isEmpty)
        #expect(try entry(saved.id).title == "Dinner")
    }

    @Test("A meal that moves restaurant takes its dishes to the new one; unused ones go")
    func kitchenMove() throws {
        let saved = try meal([DishLineDraft(name: "Pho tai"), DishLineDraft(name: "Spring rolls")])
        var draft = MealDraft(day: saved.dayKey, slot: "Dinner", source: .dineOut, eaterIds: people.map(\.id), eatenAt: saved.eatenAt, place: PlaceDraft(name: "Pho 2000"))
        try db.updateMeal(id: saved.id, draft)
        let stored = try entry(saved.id)
        let dishes = try liveDishes()
        #expect(Set(dishes.map(\.name)) == ["Pho tai", "Spring rolls"])
        #expect(Set(dishes.map(\.placeId)) == [stored.placeId])
        #expect(try lines(saved).count == 2)
        #expect(stored.title == "Pho tai, spring rolls")
        // From delivery to home-cooked, a favourite stays behind.
        try db.setFavorite(dishId: try #require(dishes.first { $0.name == "Pho tai" }).id, true)
        draft.source = .home
        draft.place = nil
        try db.updateMeal(id: saved.id, draft)
        let kinds = try Set(liveDishes().map { "\($0.name) \($0.kitchenKind)" })
        #expect(kinds == ["Pho tai place", "Pho tai home", "Spring rolls home"])
    }

    @Test("An edit that names no dishes keeps the dishes as the meal's title (decision 8)")
    func dishesAreTheTruth() throws {
        let saved = try meal([DishLineDraft(name: "Pho tai")])
        let draft = MealDraft(day: saved.dayKey, slot: "Dinner", source: .dineOut, title: "Something else", eaterIds: people.map(\.id), eatenAt: saved.eatenAt, place: pho)
        try db.updateMeal(id: saved.id, draft)
        #expect(try entry(saved.id).title == "Pho tai")
    }

    @Test("Removing a meal takes its lines and faces with it, and leaves the dish")
    func removingAMeal() throws {
        let saved = try meal([DishLineDraft(name: "Pho tai", rating: .again)])
        try db.setPersonFace(lineId: try lines(saved)[0].id, personId: people[0].id, .favorite)
        try db.deleteMeal(id: saved.id)
        #expect(try db.writer.read { try MealDish.fetchCount($0) } == 0)
        #expect(try db.writer.read { try MealDishRating.fetchCount($0) } == 0)
        #expect(try liveDishes().count == 1)
    }

    // MARK: Faces

    @Test("One face is the table's; a person's own overrides it for them, and the meal shows the best (F1 to F4)")
    func faces() throws {
        let saved = try meal([DishLineDraft(name: "Bun cha", rating: .fine)])
        let line = try lines(saved)[0]
        try db.setPersonFace(lineId: line.id, personId: people[0].id, .favorite)
        try db.setPersonFace(lineId: line.id, personId: people[2].id, .meh)
        #expect(try entry(saved.id).rating == .favorite)
        let book = DishBook(try db.foodSnapshot())
        let faces = book.faces(of: line, entry: try entry(saved.id))
        #expect(faces == [people[0].id: .favorite, people[1].id: .fine, people[2].id: .meh])
        // Back to the table's.
        try db.setPersonFace(lineId: line.id, personId: people[0].id, nil)
        try db.setTableFace(lineId: line.id, .again)
        #expect(try entry(saved.id).rating == .again)
    }

    // MARK: Renaming, merging, removing

    @Test("Renaming changes the dish on every meal and their titles (E2)")
    func rename() throws {
        let one = try meal([DishLineDraft(name: "Spring rolls"), DishLineDraft(name: "Pho tai")])
        let two = try meal([DishLineDraft(name: "Spring rolls")], at: 2_000)
        let rolls = try lines(two)[0].dishId
        try db.renameDish(id: rolls, to: "Crispy rolls")
        #expect(try entry(one.id).title == "Crispy rolls, pho tai")
        #expect(try entry(two.id).title == "Crispy rolls")
    }

    @Test("Renaming onto another dish's name in the kitchen offers to merge; merging joins their histories")
    func renameThenMerge() throws {
        let one = try meal([DishLineDraft(name: "Spring rolls", rating: .again)])
        let two = try meal([DishLineDraft(name: "Imperial rolls", rating: .fine)], at: 2_000)
        let both = try meal([DishLineDraft(name: "Spring rolls"), DishLineDraft(name: "Imperial rolls", rating: .favorite)], at: 3_000)
        let rolls = try lines(one)[0].dishId
        let imperial = try lines(two)[0].dishId
        try db.setFavorite(dishId: rolls, true)
        #expect(throws: DishError.nameTaken(imperial)) { try db.renameDish(id: rolls, to: "imperial ROLLS") }

        try db.mergeDish(id: rolls, into: imperial)
        #expect(try lines(one)[0].dishId == imperial)
        // The meal that had both keeps one line, and the face it had.
        #expect(try lines(both).map(\.dishId) == [imperial])
        #expect(try lines(both)[0].rating == .favorite)
        #expect(try entry(both.id).title == "Imperial rolls")
        let merged = try #require(try db.writer.read { try Dish.fetchOne($0, id: rolls) })
        #expect(merged.mergedInto == imperial)
        #expect(try liveDishes().map(\.name) == ["Imperial rolls"])
        #expect(try liveDishes()[0].favorite)
    }

    @Test("Removing a dish takes it off its meals after which Undo puts it back (E3, E5)")
    func removeAndRestore() throws {
        let one = try meal([DishLineDraft(name: "Pho tai"), DishLineDraft(name: "Banh xeo", rating: .meh)])
        let two = try meal([DishLineDraft(name: "Banh xeo")], at: 2_000)
        let banhXeo = try lines(two)[0]
        try db.setPersonFace(lineId: banhXeo.id, personId: people[1].id, .fine)
        let removal = try db.removeDish(id: banhXeo.dishId)
        #expect(removal.lines.count == 2)
        #expect(try entry(one.id).title == "Pho tai")
        #expect(try entry(two.id).title == "Dinner")
        #expect(try db.foodSnapshot().entries.count == 2)

        try db.restore(removal)
        #expect(try entry(one.id).title == "Pho tai, banh xeo")
        #expect(try entry(two.id).title == "Banh xeo")
        #expect(try db.writer.read { try MealDishRating.fetchCount($0) } == 1)
    }

    // MARK: The upgrade and tidying

    /// A meal written the way an older build writes one: a title, no dish lines.
    private func olderMeal(_ title: String, source: MealSource = .home, slot: String = "Dinner", at time: TimeInterval, rating: MealRating? = .again) throws -> JournalEntry {
        var draft = MealDraft(day: DayKey(rawValue: "2026-11-15"), slot: slot, source: source, title: title, rating: rating,
                              eaterIds: people.map(\.id), eatenAt: Date(timeIntervalSince1970: time), place: source.hasPlace ? pho : nil)
        draft.dishes = nil
        return try db.addMeal(draft, journalId: journal.id, now: Date(timeIntervalSince1970: time))
    }

    @Test("Every named meal gets one dish line, the same name in a kitchen one dish; slot names get none (S3)")
    func adoption() throws {
        let pesto1 = try olderMeal("Pesto pasta", at: 1_000)
        let pesto2 = try olderMeal("pesto  pasta", at: 2_000, rating: .favorite)
        let pho = try olderMeal("Pho", source: .dineOut, at: 3_000)
        let plain = try olderMeal("Dinner", at: 4_000)
        let lunch = try olderMeal("Lunch", at: 5_000)
        #expect(try db.dishesNeedTidying())
        try db.tidyDishes()
        #expect(try !db.dishesNeedTidying())

        #expect(try lines(pesto1).first?.dishId == (try lines(pesto2).first?.dishId))
        #expect(try lines(pesto2).first?.rating == .favorite)
        #expect(try lines(pesto1).first?.id == MealDish.adoptedId(entryId: pesto1.id))
        #expect(try lines(pho).count == 1)
        #expect(try lines(plain).isEmpty)
        #expect(try lines(lunch).isEmpty)
        #expect(try liveDishes().map(\.name) == ["Pesto pasta", "Pho"])
        // Titles and faces are left as they were.
        #expect(try entry(pesto2.id).title == "pesto  pasta")
        #expect(try entry(pesto2.id).rating == .favorite)
        // Tidying again changes nothing.
        try db.tidyDishes()
        #expect(try db.writer.read { try MealDish.fetchCount($0) } == 3)
    }

    @Test("Two devices adopting the same meals write the same rows")
    func adoptionIsTheSameEverywhere() throws {
        let meal = try olderMeal("Pho", source: .dineOut, at: 1_000)
        // The same household, people and meal on a second device.
        let other = try AppDatabase.inMemory()
        try db.writer.read { source in
            try other.writer.write { target in
                for table in ["household", "person", "journal", "foodPlace", "journalEntry", "journalEntryEater"] {
                    for row in try Row.fetchAll(source, sql: "SELECT * FROM \(table)") {
                        let columns = Array(row.columnNames)
                        try target.execute(
                            sql: "INSERT INTO \(table) (\(columns.map { "\"\($0)\"" }.joined(separator: ","))) VALUES (\(columns.map { _ in "?" }.joined(separator: ",")))",
                            arguments: StatementArguments(columns.map { row[$0] as DatabaseValue })
                        )
                    }
                }
            }
        }
        try db.tidyDishes()
        try other.tidyDishes()
        let here = try db.writer.read { try MealDish.filter(Column("entryId") == meal.id).fetchAll($0) }
        let there = try other.writer.read { try MealDish.filter(Column("entryId") == meal.id).fetchAll($0) }
        #expect(here.count == 1)
        #expect(here == there)
        #expect(try db.writer.read { try Dish.fetchAll($0) } == (try other.writer.read { try Dish.fetchAll($0) }))
    }

    @Test("Two dishes of one name in a kitchen, from two devices, become one; late lines follow the merge (S2)")
    func tidyMergesTwins() throws {
        let one = try meal([DishLineDraft(name: "Bun cha", rating: .fine)])
        let first = try lines(one)[0].dishId
        // Another device made its own "Bun cha" at the same place, with another id.
        let place = try #require(try entry(one.id).placeId)
        let twin = Dish(householdId: householdId, name: "bun cha", emoji: "🍲", tint: 0, kitchenKind: "place", placeId: place, createdAt: Date(timeIntervalSince1970: 5_000))
        let two = try meal([DishLineDraft(name: "Pho tai")], at: 6_000)
        try db.writer.write { db in
            try twin.insert(db)
            try MealDish(entryId: two.id, dishId: twin.id, sortOrder: 1, rating: .meh).insert(db)
        }
        try db.tidyDishes()
        #expect(try liveDishes().filter { $0.key == "bun cha" }.map(\.id) == [first])
        #expect(try lines(two).map(\.dishId).contains(first))

        // A line that arrives after the merge, naming the merged dish, is pointed at the survivor.
        let three = try meal([DishLineDraft(name: "Pho tai")], at: 7_000)
        try db.writer.write { try MealDish(entryId: three.id, dishId: twin.id, sortOrder: 1, rating: nil).insert($0) }
        #expect(try db.dishesNeedTidying())
        try db.tidyDishes()
        #expect(try lines(three).map(\.dishId).last == first)
        #expect(try entry(three.id).title == "Pho tai, bun cha")
    }

    @Test("A line whose dish hasn't arrived leaves the meal's title alone")
    func lineBeforeItsDish() throws {
        let saved = try meal([DishLineDraft(name: "Pho tai")])
        try db.writer.write { db in
            try MealDish(entryId: saved.id, dishId: .new(), sortOrder: 1, rating: .favorite).insert(db)
            var entry = try #require(try JournalEntry.fetchOne(db, id: saved.id))
            try DishTidy.writeCopies(of: &entry, db: db)
        }
        #expect(try entry(saved.id).title == "Pho tai")
        #expect(DishBook(try db.foodSnapshot()).dishes(of: try entry(saved.id)).count == 1)
    }

    @Test("The upgrade gives existing meals their dishes")
    func migration() throws {
        _ = try olderMeal("Chicken curry", at: 1_000)
        _ = try olderMeal("Dinner", at: 2_000)
        // Back to the schema from before dishes, then up again.
        try db.writer.write { db in
            try db.execute(sql: """
                DROP TABLE mealDishRating; DROP TABLE mealDish; DROP TABLE dish;
                DELETE FROM grdb_migrations WHERE identifier = ?;
                """, arguments: [AppDatabase.dishMigration])
        }
        try AppDatabase.migrator(files: nil).migrate(db.writer)
        #expect(try db.writer.read { try MealDish.fetchCount($0) } == 1)
        #expect(try liveDishes().map(\.name) == ["Chicken curry"])
    }
}
