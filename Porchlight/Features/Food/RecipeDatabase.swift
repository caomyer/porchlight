import Foundation
import GRDB

// Recipe reads and writes (docs/design/dishes.md, "Recipes").

/// A card photo being added to a recipe: its pictures, prepared like a meal's.
struct NewRecipePhoto: Equatable, Sendable {
    var id: RecipePhoto.ID = .new()
    var image: Data
    var thumbnail: Data
}

/// One of a recipe's card photos as the editor leaves them, in order.
enum RecipePhotoItem: Equatable, Sendable {
    case kept(RecipePhoto.ID)
    case added(NewRecipePhoto)
}

/// A recipe as the editor saves it.
struct RecipeDraft: Equatable, Sendable {
    /// The dish's name. A name a home dish already has joins that dish (and its history).
    var name: String
    /// The home dish being edited or given a recipe, when there is one.
    var dishId: Dish.ID?
    var serves: Int?
    var ingredients: [String] = []
    var steps: [String] = []
    /// As typed: "https://" is added when left off.
    var link: String = ""
    var notes: String = ""
    var photos: [RecipePhotoItem] = []
}

/// What removing a recipe took, to put back with Undo: the recipe and its card photos,
/// pictures and all.
struct RecipeRemoval: Equatable, Sendable {
    var recipe: Recipe
    var photos: [RecipePhotoRow]
}

extension AppDatabase {
    /// Adds or edits the recipe of a home dish, and returns the dish and its recipe.
    ///
    /// A new recipe whose name a home dish has joins that dish, so its history and faces
    /// come with it; otherwise it makes the dish. Editing the name renames the dish
    /// everywhere, unless another home dish has it (`nameTaken`). A recipe the dish already
    /// has (or one on a dish merged into it) is edited, never doubled.
    @discardableResult
    func saveRecipe(_ draft: RecipeDraft, householdId: Household.ID, addedBy: Person.ID?, now: Date = .now) throws -> (dish: Dish, recipe: Recipe) {
        let name = DishName.cleaned(draft.name)
        guard !DishName.key(name).isEmpty else { throw RecipeError.emptyName }
        guard name.count <= DishName.limit else { throw RecipeError.nameTooLong(limit: DishName.limit) }
        let ingredients = RecipeText.stored(draft.ingredients)
        let steps = RecipeText.stored(draft.steps)
        for lines in [RecipeText.lines(ingredients), RecipeText.lines(steps)] {
            guard lines.count <= RecipeLimits.lines else { throw RecipeError.tooManyLines(limit: RecipeLimits.lines) }
            guard lines.allSatisfy({ $0.count <= RecipeLimits.lineLength }) else { throw RecipeError.lineTooLong(limit: RecipeLimits.lineLength) }
        }
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard notes.count <= RecipeLimits.notes else { throw RecipeError.notesTooLong(limit: RecipeLimits.notes) }
        let link = try RecipeText.link(draft.link).get()
        if let serves = draft.serves, !RecipeLimits.serves.contains(serves) { throw RecipeError.invalidServes }
        guard draft.photos.count <= RecipeLimits.photos else { throw RecipeError.tooManyPhotos(limit: RecipeLimits.photos) }

        return try writer.write { db in
            var dish: Dish
            if let dishId = draft.dishId {
                guard let live = try DishTidy.live(dishId, db: db) else { throw DishError.dishNotFound }
                guard live.kitchen == .home else { throw RecipeError.notAHomeDish }
                dish = live
                if DishName.key(name) != dish.key {
                    if let other = try DishTidy.named(name, kitchen: .home, householdId: dish.householdId, db: db), other.id != dish.id {
                        throw RecipeError.nameTaken(other.id)
                    }
                    try DishTidy.rename(&dish, to: name, db: db)
                } else if name != dish.name {
                    try DishTidy.rename(&dish, to: name, db: db)
                }
            } else {
                dish = try DishTidy.findOrMake(name: name, kitchen: .home, householdId: householdId, emoji: nil, tint: nil, db: db, now: now)
            }

            var recipe: Recipe
            if var existing = try RecipeTidy.recipe(ofLive: dish.id, db: db) {
                existing.serves = draft.serves
                existing.ingredients = ingredients
                existing.steps = steps
                existing.link = link
                existing.notes = notes
                existing.updatedAt = now
                try existing.update(db)
                recipe = existing
            } else {
                recipe = Recipe(
                    id: Recipe.id(dishId: dish.id), dishId: dish.id, serves: draft.serves, ingredients: ingredients,
                    steps: steps, link: link, notes: notes, addedById: addedBy, createdAt: now, updatedAt: now
                )
                try recipe.insert(db)
            }
            try Self.writeRecipePhotos(draft.photos, recipe: recipe, db: db, now: now)
            return (dish, recipe)
        }
    }

    /// Replaces a recipe's card photos with `items`, in order: kept ones are re-ordered,
    /// added ones are attached with their pictures, and the rest go.
    private static func writeRecipePhotos(_ items: [RecipePhotoItem], recipe: Recipe, db: Database, now: Date) throws {
        let existing = try RecipePhoto.filter(Column("recipeId") == recipe.id).fetchAll(db)
        let kept = Set(items.compactMap { if case let .kept(id) = $0 { id } else { nil } })
        for photo in existing where !kept.contains(photo.id) { _ = try photo.delete(db) }
        let byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for (index, item) in items.enumerated() {
            switch item {
            case let .kept(id):
                guard var photo = byId[id] else { continue }
                if photo.sortOrder != index {
                    photo.sortOrder = index
                    try photo.update(db)
                }
            case let .added(new):
                try RecipePhotoRow(
                    id: new.id, dishId: recipe.dishId, recipeId: recipe.id, sortOrder: index, createdAt: now,
                    thumbnail: new.thumbnail, image: new.image
                ).insert(db)
            }
        }
    }

    /// Removes a dish's recipe with its card photos; the dish, its meals and its planned
    /// dinners stay. Returns what Undo puts back.
    @discardableResult
    func removeRecipe(dishId: Dish.ID) throws -> RecipeRemoval {
        try writer.write { db in
            guard let live = try DishTidy.live(dishId, db: db), let recipe = try RecipeTidy.recipe(ofLive: live.id, db: db) else {
                throw RecipeError.recipeNotFound
            }
            let removal = try RecipeTidy.removal(of: recipe, db: db)
            try RecipeTidy.delete(recipe, db: db)
            return removal
        }
    }

    /// Puts back what `removeRecipe` took, while its dish is still there.
    func restore(_ removal: RecipeRemoval) throws {
        try writer.write { db in
            try RecipeTidy.restore(removal, db: db)
        }
    }

    /// A card photo's whole picture, for the recipe's page.
    func recipePhotoImage(id: RecipePhoto.ID) throws -> Data? {
        try writer.read { db in try Data.fetchOne(db, sql: "SELECT image FROM recipePhoto WHERE id = ?", arguments: [id]) }
    }

    /// A card photo's small square.
    func recipePhotoThumbnail(id: RecipePhoto.ID) throws -> Data? {
        try writer.read { db in try Data.fetchOne(db, sql: "SELECT thumbnail FROM recipePhoto WHERE id = ?", arguments: [id]) }
    }
}

/// The rules that keep recipes with their dishes, shared by the recipe writes and the dish
/// writes that touch them (renaming, merging, removing).
enum RecipeTidy {
    /// The recipe of a live dish: its own, else one on a dish merged into it (merging leaves
    /// a recipe where it is, and readers follow the merge, as they do for late dish lines).
    static func recipe(ofLive dishId: Dish.ID, db: Database) throws -> Recipe? {
        if let own = try Recipe.filter(Column("dishId") == dishId).fetchOne(db) { return own }
        for merged in try mergedInto(dishId, db: db) {
            if let recipe = try Recipe.filter(Column("dishId") == merged).order(Column("updatedAt").desc).fetchOne(db) { return recipe }
        }
        return nil
    }

    /// Every dish merged into `dishId`, directly or through another merge.
    static func mergedInto(_ dishId: Dish.ID, db: Database) throws -> [Dish.ID] {
        var found: [Dish.ID] = []
        var frontier = [dishId]
        var seen: Set<Dish.ID> = [dishId]
        while let next = frontier.popLast() {
            for id in try Dish.select(Column("id"), as: Dish.ID.self).filter(Column("mergedInto") == next).fetchAll(db) where seen.insert(id).inserted {
                found.append(id)
                frontier.append(id)
            }
        }
        return found
    }

    static func removal(of recipe: Recipe, db: Database) throws -> RecipeRemoval {
        RecipeRemoval(
            recipe: recipe,
            photos: try RecipePhotoRow.filter(Column("recipeId") == recipe.id).order(Column("sortOrder"), Column("id")).fetchAll(db)
        )
    }

    /// Removes a recipe and its card photos, which hang off the dish and so don't go with it
    /// by themselves.
    static func delete(_ recipe: Recipe, db: Database) throws {
        try RecipePhoto.filter(Column("recipeId") == recipe.id).deleteAll(db)
        _ = try recipe.delete(db)
    }

    static func restore(_ removal: RecipeRemoval, db: Database) throws {
        guard try Dish.exists(db, id: removal.recipe.dishId) else { return }
        try removal.recipe.upsert(db)
        for photo in removal.photos where try Dish.exists(db, id: photo.dishId) { try photo.upsert(db) }
    }
}

/// Which home dish a planned dinner names (docs/design/dishes.md, "Planned dinners").
enum PlannedDish {
    /// The dish it was planned from, while its title still names it; else the home dish its
    /// words name; else none. The title is checked because an older build that renames the
    /// dinner keeps the dish id on iCloud but changes the words.
    static func dish(for plan: MealPlan, in book: DishBook) -> Dish? {
        let key = DishName.key(plan.title)
        guard !key.isEmpty else { return nil }
        if let id = plan.dishId, let dish = book.dish(id), dish.kitchen == .home, dish.key == key { return dish }
        return book.liveDishes.first { $0.kitchen == .home && $0.key == key }
    }

    /// Follows a dish's new name in every planned dinner of it that still had its old one,
    /// so renaming a dish renames the dinners planned from it.
    static func rename(plansOf dishIds: Set<Dish.ID>, from oldName: String, to dish: Dish, db: Database) throws {
        let oldKey = DishName.key(oldName)
        for var plan in try MealPlan.filter(Column("householdId") == dish.householdId && Column("dishId") != nil).fetchAll(db) {
            guard let id = plan.dishId, dishIds.contains(id), DishName.key(plan.title) == oldKey else { continue }
            plan.title = dish.name
            plan.dishId = dish.id
            try plan.update(db)
        }
    }
}
