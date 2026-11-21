import Foundation
import GRDB

// MARK: - Records

/// How a home dish is made (docs/design/dishes.md, "Recipes"). A recipe is not a second
/// kind of food: it belongs to one home dish, at most one per dish, so cooking the dish is
/// cooking the recipe, and "cooked 6 times" is that dish's meals.
///
/// Ingredients and steps are plain lines, as people write them: enough to tick groceries
/// and to read at the stove, with no quantities or units to keep up.
struct Recipe: Codable, Equatable, Hashable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<Recipe>

    /// Derived from the dish (`id(dishId:)`), so two devices that add a recipe to the same
    /// dish offline write one row, field by field.
    var id: ID
    var dishId: Dish.ID
    /// How many it feeds; nil when nobody said.
    var serves: Int?
    /// One ingredient per line, as written ("2 lb chicken thighs").
    var ingredients: String = ""
    /// One step per line.
    var steps: String = ""
    /// Where it came from on the web.
    var link: String?
    var notes: String = ""
    /// Who added it, a plain id ("Mia's chicken curry"); nil when unknown.
    var addedById: Person.ID?
    var createdAt: Date
    var updatedAt: Date

    static func id(dishId: Dish.ID) -> ID {
        .derived(dishId.description, "recipe")
    }

    var ingredientLines: [String] { RecipeText.lines(ingredients) }
    var stepLines: [String] { RecipeText.lines(steps) }
}

extension Recipe: FetchableRecord, PersistableRecord {}

/// A photo of a recipe's card, in order. It hangs off the recipe's dish and names its
/// recipe with a plain id (docs/design/dishes.md, "Updating"); its two pictures are in the
/// same row, and this record never reads them: lists load the small square through
/// `PhotoImages`, and the recipe's page the whole picture.
struct RecipePhoto: Codable, Equatable, Hashable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<RecipePhoto>

    var id: ID = .new()
    var dishId: Dish.ID
    var recipeId: Recipe.ID
    var sortOrder: Int
    var createdAt: Date
}

extension RecipePhoto: FetchableRecord, PersistableRecord {
    static let databaseTableName = "recipePhoto"
    /// Everything but the pictures.
    static var databaseSelection: [any SQLSelectable] {
        [Column("id"), Column("dishId"), Column("recipeId"), Column("sortOrder"), Column("createdAt")]
    }
}

/// A card photo's whole row, pictures included: what saving writes, and what removing
/// keeps for Undo.
struct RecipePhotoRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recipePhoto"

    var id: RecipePhoto.ID
    var dishId: Dish.ID
    var recipeId: Recipe.ID
    var sortOrder: Int
    var createdAt: Date
    var thumbnail: Data
    var image: Data
}

// MARK: - Migration

extension AppDatabase {
    static let recipeMigration = "recipes v1: a home dish's recipe, its card photos, and a planned dinner's dish"

    /// Adds the recipe tables and the planned dinner's dish (docs/design/dishes.md,
    /// "Recipes"). It writes no rows: the new column is nil for every planned dinner so far.
    static func registerRecipeMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(recipeMigration) { db in
            for table in SyncSchema.recipeTables {
                try db.execute(sql: "CREATE TABLE \"\(table.name)\" (\(table.columns)) STRICT")
            }
            try db.execute(sql: """
                CREATE INDEX "recipe_on_dishId" ON "recipe"("dishId");
                CREATE INDEX "recipePhoto_on_dishId" ON "recipePhoto"("dishId");
                CREATE INDEX "recipePhoto_on_recipeId" ON "recipePhoto"("recipeId");
                ALTER TABLE "mealPlan" ADD COLUMN "dishId" TEXT;
                """)
        }
    }
}
