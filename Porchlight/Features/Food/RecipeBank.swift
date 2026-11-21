import Foundation

/// The recipe bank: our home dishes that know how they are made, read from the dish book
/// (docs/design/dishes.md, "Recipes"). Pure, covered by RecipeBankTests.
struct RecipeBank: Sendable {
    let book: DishBook

    init(_ book: DishBook) {
        self.book = book
    }

    /// One recipe in the bank, with what its dish remembers.
    struct Entry: Identifiable, Equatable, Sendable {
        var dish: Dish
        var recipe: Recipe
        /// How many meals the dish was on: every one of a home dish was cooked here.
        var times: Int
        var last: JournalEntry?
        /// The face it gets most.
        var face: MealRating?
        var photos: [RecipePhoto]
        var id: Dish.ID { dish.id }
    }

    /// Every recipe of a live home dish, most cooked first, then most recently cooked, then
    /// by name; ones not cooked yet last, newest first.
    var entries: [Entry] {
        book.liveDishes
            .filter { $0.kitchen == .home }
            .compactMap(entry)
            .sorted { a, b in
                if a.times != b.times { return a.times > b.times }
                let x = a.last?.eatenAt ?? a.recipe.createdAt, y = b.last?.eatenAt ?? b.recipe.createdAt
                if x != y { return x > y }
                return a.dish.name.localizedCaseInsensitiveCompare(b.dish.name) == .orderedAscending
            }
    }

    func entry(_ dish: Dish) -> Entry? {
        guard let recipe = book.recipe(of: dish.id) else { return nil }
        let summary = book.summary(of: dish.id)
        return Entry(
            dish: dish, recipe: recipe, times: summary.count, last: summary.last, face: summary.face,
            photos: book.snapshot.recipePhotos[recipe.id] ?? []
        )
    }

    /// How long a recipe has to wait before "Haven't made in a while" suggests it.
    static let whileDays = 21

    /// "Haven't made in a while": a recipe we like that wasn't cooked in three weeks, the
    /// best liked first and, among those, the longest ago. Nil when none has waited so long.
    func notMadeInAWhile(now: Date, calendar: Calendar) -> Entry? {
        let today = calendar.startOfDay(for: now)
        return entries
            .filter { entry in
                guard let last = entry.last, (entry.face?.rawValue ?? MealRating.fine.rawValue) >= MealRating.fine.rawValue else { return false }
                // Whole days in the household's time zone, from the day it was cooked to today.
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.eatenAt), to: today).day ?? 0
                return days >= Self.whileDays
            }
            .min { a, b in
                let x = a.face?.rawValue ?? 0, y = b.face?.rawValue ?? 0
                if x != y { return x > y }
                return (a.last?.eatenAt ?? .distantPast) < (b.last?.eatenAt ?? .distantPast)
            }
    }

    /// "You cook these often": home dishes cooked at least twice that have no recipe yet,
    /// most cooked first.
    func cookedOftenWithoutRecipe(limit: Int = 3) -> [(dish: Dish, times: Int)] {
        book.homeDishes
            .filter { book.recipe(of: $0.id) == nil }
            .map { ($0, book.summary(of: $0.id).count) }
            .filter { $0.1 >= 2 }
            .prefix(limit)
            .map { (dish: $0.0, times: $0.1) }
    }

    /// Recipes whose name, or one of whose ingredients, has every word typed
    /// ("curry powder" finds the chicken curry).
    func search(_ text: String) -> [Entry] {
        let query = DishName.key(text)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            DishBook.matches(query, entry.dish.key)
                || entry.recipe.ingredientLines.contains { DishBook.matches(query, DishName.key($0)) }
        }
    }

    /// The home dish a new recipe of this name would join, with how often it was cooked
    /// ("Joins the dish you already cook"); nil for a new dish, or one with a recipe already.
    func joins(_ name: String) -> (dish: Dish, times: Int)? {
        let key = DishName.key(name)
        guard !key.isEmpty, let dish = book.liveDishes.first(where: { $0.kitchen == .home && $0.key == key }) else { return nil }
        return (dish, book.summary(of: dish.id).count)
    }
}
