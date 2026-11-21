import Foundation
import GRDB
import Testing
@testable import Porchlight

/// Recipes in the database (docs/design/dishes.md, "Recipes"): adding one makes or joins a
/// home dish, editing never doubles it, removing keeps the dish and its dinners, and the
/// dish writes (renaming, merging, removing, tidying) carry recipes and planned dinners.
@Suite("Recipes: saving, joining, removing, and what dishes do with them")
struct RecipeDatabaseTests {
    let db: AppDatabase
    let householdId: Household.ID
    let people: [Person]
    let journal: Journal

    init() throws {
        db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "The Lake House", people: [
            PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral),
        ])
        householdId = household.id
        people = try db.snapshot().people
        journal = try db.ensureFoodJournal(householdId: householdId)
    }

    private var mia: Person.ID { people[1].id }

    private func homeMeal(_ names: [String], day: String = "2026-11-02", at time: TimeInterval = 1_000) throws -> JournalEntry {
        var draft = MealDraft(
            day: DayKey(rawValue: day), slot: "Dinner", sources: MealSources(.home), eaterIds: people.map(\.id),
            eatenAt: Date(timeIntervalSince1970: time)
        )
        draft.dishes = names.map { DishLineDraft(name: $0, rating: .again) }
        return try db.addMeal(draft, journalId: journal.id, now: Date(timeIntervalSince1970: time))
    }

    private func curry(_ name: String = "Chicken curry", dishId: Dish.ID? = nil, photos: [RecipePhotoItem] = []) -> RecipeDraft {
        RecipeDraft(
            name: name, dishId: dishId, serves: 4,
            ingredients: ["2 lb chicken thighs", "1 onion", "", "1 can coconut milk"],
            steps: ["Brown the chicken.", "Simmer 30 min."], link: "example.com/curry", notes: " Ava likes it mild. ", photos: photos
        )
    }

    private func book() throws -> DishBook { DishBook(try db.foodSnapshot()) }

    private func card() -> NewRecipePhoto {
        NewRecipePhoto(image: Data("whole card".utf8), thumbnail: Data("small".utf8))
    }

    // MARK: Adding and editing

    @Test("A new recipe makes its home dish, with an id derived from it, and stores plain lines")
    func addsDishAndRecipe() throws {
        let saved = try db.saveRecipe(curry(), householdId: householdId, addedBy: mia, now: Date(timeIntervalSince1970: 50))
        #expect(saved.dish.kitchen == .home)
        #expect(saved.dish.name == "Chicken curry")
        #expect(saved.recipe.id == Recipe.id(dishId: saved.dish.id))
        #expect(saved.recipe.ingredientLines == ["2 lb chicken thighs", "1 onion", "1 can coconut milk"])
        #expect(saved.recipe.stepLines == ["Brown the chicken.", "Simmer 30 min."])
        #expect(saved.recipe.link == "https://example.com/curry")
        #expect(saved.recipe.notes == "Ava likes it mild.")
        #expect(saved.recipe.addedById == mia)
        #expect(try book().recipe(of: saved.dish.id) == saved.recipe)
        #expect(try db.dishesNeedTidying() == false, "a dish with a recipe and no meals is tidy")
    }

    @Test("A recipe named like a home dish joins it: its meals and faces come with it (R2)")
    func joinsTheDishWeCook() throws {
        let meal = try homeMeal(["Chicken Curry"])
        let before = try #require(try book().dishes(of: meal).first?.dish)
        let saved = try db.saveRecipe(curry("chicken curry "), householdId: householdId, addedBy: mia)
        #expect(saved.dish.id == before.id)
        #expect(saved.dish.name == "Chicken Curry", "the dish keeps its name when only the case differs")
        #expect(try book().summary(of: saved.dish.id).count == 1)
        #expect(RecipeBank(try book()).entries.map(\.times) == [1])
    }

    @Test("Saving again edits the one recipe, keeping who added it and when")
    func editsInPlace() throws {
        let first = try db.saveRecipe(curry(), householdId: householdId, addedBy: mia, now: Date(timeIntervalSince1970: 10))
        var draft = curry(dishId: first.dish.id)
        draft.serves = 6
        draft.steps = ["Brown it.", "Simmer.", "Serve with rice."]
        draft.link = ""
        let second = try db.saveRecipe(draft, householdId: householdId, addedBy: people[0].id, now: Date(timeIntervalSince1970: 20))
        #expect(second.recipe.id == first.recipe.id)
        #expect(second.recipe.serves == 6)
        #expect(second.recipe.stepLines.count == 3)
        #expect(second.recipe.link == nil)
        #expect(second.recipe.addedById == mia)
        #expect(second.recipe.createdAt == Date(timeIntervalSince1970: 10))
        #expect(second.recipe.updatedAt == Date(timeIntervalSince1970: 20))
        #expect(try db.writer.read { try Recipe.fetchCount($0) } == 1)
    }

    @Test("Renaming in the recipe renames the dish everywhere, but not onto another home dish")
    func renames() throws {
        let meal = try homeMeal(["Chicken curry"])
        _ = try homeMeal(["Pesto pasta"], at: 2_000)
        let saved = try db.saveRecipe(curry(), householdId: householdId, addedBy: mia)
        _ = try db.saveRecipe(curry("Mia's chicken curry", dishId: saved.dish.id), householdId: householdId, addedBy: mia)
        #expect(try book().dish(saved.dish.id)?.name == "Mia's chicken curry")
        #expect(try db.writer.read { try JournalEntry.fetchOne($0, id: meal.id)?.title } == "Mia's chicken curry")
        let pesto = try #require(try book().liveDishes.first { $0.name == "Pesto pasta" })
        #expect(throws: RecipeError.nameTaken(pesto.id)) {
            try db.saveRecipe(curry("pesto pasta", dishId: saved.dish.id), householdId: householdId, addedBy: mia)
        }
    }

    @Test("Only a home dish can have a recipe; a bad link, serves or too many lines are refused")
    func refuses() throws {
        var draft = MealDraft(
            day: DayKey(rawValue: "2026-11-02"), slot: "Dinner", sources: MealSources(.dineOut), eaterIds: people.map(\.id),
            eatenAt: Date(timeIntervalSince1970: 1), place: PlaceDraft(name: "Pho Saigon House")
        )
        draft.dishes = [DishLineDraft(name: "Pho tai")]
        let out = try db.addMeal(draft, journalId: journal.id)
        let pho = try #require(try book().dishes(of: out).first?.dish)
        #expect(throws: RecipeError.notAHomeDish) { try db.saveRecipe(curry("Pho tai", dishId: pho.id), householdId: householdId, addedBy: nil) }
        var bad = curry()
        bad.link = "not a link"
        #expect(throws: RecipeError.invalidLink) { try db.saveRecipe(bad, householdId: householdId, addedBy: nil) }
        bad = curry()
        bad.serves = 0
        #expect(throws: RecipeError.invalidServes) { try db.saveRecipe(bad, householdId: householdId, addedBy: nil) }
        bad = curry()
        bad.ingredients = Array(repeating: "salt", count: RecipeLimits.lines + 1)
        #expect(throws: RecipeError.tooManyLines(limit: RecipeLimits.lines)) { try db.saveRecipe(bad, householdId: householdId, addedBy: nil) }
        #expect(throws: RecipeError.emptyName) { try db.saveRecipe(curry("  "), householdId: householdId, addedBy: nil) }
        #expect(try db.writer.read { try Recipe.fetchCount($0) } == 0, "nothing was written")
    }

    @Test("Card photos are kept in order, added with both pictures, and dropped with theirs")
    func cardPhotos() throws {
        let one = card(), two = card()
        let saved = try db.saveRecipe(curry(photos: [.added(one), .added(two)]), householdId: householdId, addedBy: mia)
        #expect(try db.foodSnapshot().recipePhotos[saved.recipe.id]?.map(\.id) == [one.id, two.id])
        #expect(try db.recipePhotoImage(id: one.id) == Data("whole card".utf8))
        let three = card()
        _ = try db.saveRecipe(curry(dishId: saved.dish.id, photos: [.kept(two.id), .added(three)]), householdId: householdId, addedBy: mia)
        #expect(try db.foodSnapshot().recipePhotos[saved.recipe.id]?.map(\.id) == [two.id, three.id])
        #expect(try db.recipePhotoImage(id: one.id) == nil)
        #expect(try db.recipePhotoThumbnail(id: one.id) == nil)
    }

    // MARK: Removing

    @Test("Removing a recipe keeps the dish, its meals and its planned dinner; Undo brings it back with its photos (E4, E5)")
    func removesAndRestores() throws {
        _ = try homeMeal(["Chicken curry"])
        let photo = card()
        let saved = try db.saveRecipe(curry(photos: [.added(photo)]), householdId: householdId, addedBy: mia)
        try db.setMeal(day: DayKey(rawValue: "2026-11-20"), title: "Chicken curry", emoji: nil, householdId: householdId, dishId: saved.dish.id)
        let removal = try db.removeRecipe(dishId: saved.dish.id)
        #expect(try book().recipe(of: saved.dish.id) == nil)
        #expect(try book().summary(of: saved.dish.id).count == 1, "the dish and its meal stay")
        #expect(try db.writer.read { try MealPlan.fetchOne($0)?.dishId } == saved.dish.id, "the planned dinner still names the dish")
        #expect(try db.recipePhotoImage(id: photo.id) == nil)
        try db.restore(removal)
        #expect(try book().recipe(of: saved.dish.id)?.id == saved.recipe.id)
        #expect(try book().recipe(of: saved.dish.id)?.ingredients == saved.recipe.ingredients)
        #expect(try db.recipePhotoImage(id: photo.id) == Data("whole card".utf8))
    }

    @Test("Removing a dish takes its recipe and unlinks its planned dinner; Undo puts both back")
    func dishRemovalTakesTheRecipe() throws {
        _ = try homeMeal(["Chicken curry"])
        let saved = try db.saveRecipe(curry(photos: [.added(card())]), householdId: householdId, addedBy: mia)
        let day = DayKey(rawValue: "2026-11-20")
        try db.setMeal(day: day, title: "Chicken curry", emoji: nil, householdId: householdId, dishId: saved.dish.id)
        let removal = try db.removeDish(id: saved.dish.id)
        #expect(removal.recipes.map(\.recipe.id) == [saved.recipe.id])
        #expect(try db.writer.read { try Recipe.fetchCount($0) } == 0)
        let plan = try #require(try db.writer.read { try MealPlan.fetchOne($0) })
        #expect(plan.title == "Chicken curry" && plan.dishId == nil, "the dinner keeps its words but no longer links")
        try db.restore(removal)
        #expect(try book().recipe(of: saved.dish.id)?.id == saved.recipe.id)
        #expect(try db.writer.read { try MealPlan.fetchOne($0)?.dishId } == saved.dish.id)
    }

    @Test("A dish with a recipe stays when its last meal moves to another kitchen")
    func recipeKeepsTheDish() throws {
        let meal = try homeMeal(["Chicken curry"])
        let saved = try db.saveRecipe(curry(), householdId: householdId, addedBy: mia)
        var draft = MealDraft(
            day: DayKey(rawValue: "2026-11-02"), slot: "Dinner", sources: MealSources(.delivery), eaterIds: people.map(\.id),
            eatenAt: Date(timeIntervalSince1970: 1_000)
        )
        draft.dishes = nil
        _ = try db.updateMeal(id: meal.id, draft)
        #expect(try book().dish(saved.dish.id) != nil)
        #expect(try book().recipe(of: saved.dish.id) != nil)
        #expect(try book().summary(of: saved.dish.id).count == 0)
    }

    // MARK: Merging and renaming dishes

    @Test("Merging a dish with a recipe into one without: the survivor finds the recipe through the merge")
    func mergeFollowsTheRecipe() throws {
        let typo = try db.saveRecipe(curry("Chiken curry"), householdId: householdId, addedBy: mia)
        _ = try homeMeal(["Chicken curry"])
        let right = try #require(try book().liveDishes.first { $0.name == "Chicken curry" })
        try db.mergeDish(id: typo.dish.id, into: right.id)
        #expect(try book().recipe(of: right.id)?.id == typo.recipe.id)
        // Editing it from the survivor edits that recipe, not a second one.
        _ = try db.saveRecipe(curry("Chicken curry", dishId: right.id), householdId: householdId, addedBy: mia)
        #expect(try db.writer.read { try Recipe.fetchCount($0) } == 1)
        // And the survivor, with no meals of its own left after a move, isn't dropped.
        #expect(try db.writer.read { try RecipeTidy.recipe(ofLive: right.id, db: $0)?.id } == typo.recipe.id)
    }

    @Test("Renaming or merging a dish renames the dinners planned from it under its old name")
    func plansFollowTheDish() throws {
        let saved = try db.saveRecipe(curry(), householdId: householdId, addedBy: mia)
        let monday = DayKey(rawValue: "2026-11-23"), tuesday = DayKey(rawValue: "2026-11-24")
        try db.setMeal(day: monday, title: "Chicken curry", emoji: nil, householdId: householdId, dishId: saved.dish.id)
        try db.setMeal(day: tuesday, title: "Curry night", emoji: nil, householdId: householdId, dishId: saved.dish.id)
        try db.renameDish(id: saved.dish.id, to: "Mia's curry")
        let plans = try db.writer.read { try MealPlan.order(Column("day")).fetchAll($0) }
        #expect(plans.map(\.title) == ["Mia's curry", "Curry night"], "only the dinner that used the dish's name follows it")

        let other = try db.saveRecipe(curry("Green curry"), householdId: householdId, addedBy: mia)
        try db.setMeal(day: tuesday, title: "Green curry", emoji: nil, householdId: householdId, dishId: other.dish.id)
        try db.mergeDish(id: other.dish.id, into: saved.dish.id)
        let merged = try #require(try db.writer.read { try MealPlan.fetchOne($0, id: MealPlan.id(householdId: householdId, day: tuesday)) })
        #expect(merged.title == "Mia's curry" && merged.dishId == saved.dish.id)
    }

    // MARK: Planned dinners

    @Test("A planned dinner names its dish while its words do, else the home dish its words name")
    func plannedDish() throws {
        _ = try homeMeal(["Pesto pasta"])
        let saved = try db.saveRecipe(curry(), householdId: householdId, addedBy: mia)
        let day = DayKey(rawValue: "2026-11-20")
        func plan() throws -> MealPlan { try #require(try db.writer.read { try MealPlan.fetchOne($0) }) }

        try db.setMeal(day: day, title: "Chicken curry", emoji: nil, householdId: householdId, dishId: saved.dish.id)
        #expect(PlannedDish.dish(for: try plan(), in: try book())?.id == saved.dish.id)

        // Edited by its words with the same name (a new emoji), it keeps the dish.
        try db.setMeal(day: day, title: "chicken curry", emoji: "🍛", householdId: householdId)
        #expect(try plan().dishId == saved.dish.id)

        // An older build renames the dinner: the id stays on iCloud, but the words decide.
        try db.writer.write { try $0.execute(sql: "UPDATE mealPlan SET title = 'Pesto pasta'") }
        #expect(try plan().dishId == saved.dish.id)
        #expect(PlannedDish.dish(for: try plan(), in: try book())?.name == "Pesto pasta", "the words name another home dish")
        try db.writer.write { try $0.execute(sql: "UPDATE mealPlan SET title = 'Tacos'") }
        #expect(PlannedDish.dish(for: try plan(), in: try book()) == nil)
    }

    @Test("Planning a dinner suggests what we cook: most cooked first, a recipe ahead at the same count, narrowed by what is typed")
    func plannedSuggestions() throws {
        _ = try homeMeal(["Pesto pasta", "Garlic bread"], day: "2026-11-02", at: 1_000)
        _ = try homeMeal(["Pesto pasta"], day: "2026-11-03", at: 2_000)
        _ = try homeMeal(["Green salad"], day: "2026-11-04", at: 3_000)
        _ = try db.saveRecipe(curry(), householdId: householdId, addedBy: mia)
        _ = try db.saveRecipe(curry("Green salad"), householdId: householdId, addedBy: mia)

        let all = PlannedDish.suggestions(for: "", in: try book()).map(\.name)
        #expect(all == ["Pesto pasta", "Green salad", "Garlic bread", "Chicken curry"])
        #expect(PlannedDish.suggestions(for: "", in: try book(), limit: 2).map(\.name) == ["Pesto pasta", "Green salad"])
        #expect(PlannedDish.suggestions(for: "gr", in: try book()).map(\.name) == ["Green salad"])
        #expect(PlannedDish.suggestions(for: "pes", in: try book()).map(\.name) == ["Pesto pasta"])
        #expect(PlannedDish.suggestions(for: "  pesto PASTA ", in: try book()).isEmpty, "not the one it already names")
        #expect(PlannedDish.suggestions(for: "tacos", in: try book()).isEmpty)
    }

    // MARK: Groceries

    @Test("Ingredients go to the grocery list one item each, in their aisles, never twice")
    func ingredientsToGroceries() throws {
        try db.ensureDefaultLists(householdId: householdId)
        let groceries = try #require(try db.writer.read { try HomeList.filter(Column("kind") == ListKind.grocery.rawValue).fetchOne($0) })
        let names = ["2 lb chicken thighs", "1 can coconut milk", "2 potatoes"].map(Ingredient.groceryName)
        let added = try db.addListItems(titles: names, to: groceries.id, addedBy: mia)
        #expect(added.map(\.title) == ["Chicken thighs", "Coconut milk", "Potatoes"])
        #expect(added.allSatisfy { $0.section != nil })
        #expect(added.map(\.sortOrder) == added.map(\.sortOrder).sorted())
        let again = try db.addListItems(titles: ["potatoes", "Rice"], to: groceries.id, addedBy: mia)
        #expect(again.map(\.title) == ["Rice"], "potatoes are on the list already")
        try db.deleteListItems(ids: added.map(\.id))
        #expect(try db.writer.read { try ListItem.fetchCount($0) } == 1)
    }
}
