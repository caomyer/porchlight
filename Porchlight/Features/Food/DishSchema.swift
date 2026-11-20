import Foundation
import GRDB

// MARK: - Records

/// A dish the household has had: a name in one kitchen, with a memory of every meal it was
/// on (docs/design/dishes.md). "Pho tai" at Pho Saigon House and "Pho tai" made at home are
/// two dishes.
struct Dish: Codable, Equatable, Hashable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<Dish>

    var id: ID = .new()
    var householdId: Household.ID
    var name: String
    var emoji: String
    /// Background of the illustration, as 0xRRGGBB.
    var tint: Int
    /// `DishKitchen.kind`: home, place or elsewhere.
    var kitchenKind: String
    /// The restaurant, for a dish of a place. A plain id, like a meal's.
    var placeId: FoodPlace.ID?
    /// A household favourite.
    var favorite: Bool = false
    /// The dish this one was merged into. A merged dish stays, so a line that arrives late
    /// from an offline device still finds its way; it is never shown.
    var mergedInto: ID?
    var createdAt: Date

    var kitchen: DishKitchen {
        get { DishKitchen(kind: kitchenKind, placeId: placeId) }
        set {
            kitchenKind = newValue.kind
            placeId = newValue.placeId
        }
    }

    var key: String { DishName.key(name) }

    enum CodingKeys: String, CodingKey {
        case id, householdId, name, emoji, tint, placeId, favorite, mergedInto, createdAt
        case kitchenKind = "kitchen"
    }

    /// The id a dish gets when it is first made from a name, the same on every device, so
    /// two devices that add "Bun cha" at the same place offline end with one.
    static func id(householdId: Household.ID, kitchen: DishKitchen, name: String) -> ID {
        .derived(householdId.description, kitchen.idPart, DishName.key(name))
    }
}

extension Dish: FetchableRecord, PersistableRecord {
    enum Columns {
        static let householdId = Column(CodingKeys.householdId)
    }
}

/// One dish on one meal: which dish, its place in the meal, and the table's face for it.
struct MealDish: Codable, Equatable, Hashable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<MealDish>

    var id: ID = .new()
    var entryId: JournalEntry.ID
    var dishId: Dish.ID
    var sortOrder: Int
    /// The table's face, for everyone who ate, until someone gives their own.
    var rating: MealRating?

    /// The line a meal from before dishes gets: one per meal, the same on every device.
    static func adoptedId(entryId: JournalEntry.ID) -> ID {
        .derived(entryId.description, "dish")
    }
}

extension MealDish: FetchableRecord, PersistableRecord {
    static let databaseTableName = "mealDish"
}

/// One person's own face for a dish on a meal, when it differs from the table's.
struct MealDishRating: Codable, Equatable, Hashable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<MealDishRating>

    /// Derived from the line and the person: one face each.
    var id: ID
    var mealDishId: MealDish.ID
    /// A plain id: it may point at nobody yet after a sync.
    var personId: Person.ID
    var rating: MealRating

    init(mealDishId: MealDish.ID, personId: Person.ID, rating: MealRating) {
        id = .derived(mealDishId.description, personId.description)
        self.mealDishId = mealDishId
        self.personId = personId
        self.rating = rating
    }
}

extension MealDishRating: FetchableRecord, PersistableRecord {
    static let databaseTableName = "mealDishRating"
}

// MARK: - Migration

extension AppDatabase {
    static let dishMigration = "dishes v1: dishes on meals, and each person's face"

    /// Adds the dish tables, and gives every meal named before them one dish line
    /// (docs/design/dishes.md, "Existing meals").
    ///
    /// The rows it writes have derived ids, so every device that updates writes the same
    /// ones; the sync engine sends a new table's rows when it first starts with it.
    static func registerDishMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(dishMigration) { db in
            for table in SyncSchema.dishTables {
                try db.execute(sql: "CREATE TABLE \"\(table.name)\" (\(table.columns)) STRICT")
            }
            try db.execute(sql: """
                CREATE INDEX "dish_on_householdId" ON "dish"("householdId");
                CREATE INDEX "mealDish_on_entryId" ON "mealDish"("entryId");
                CREATE INDEX "mealDish_on_dishId" ON "mealDish"("dishId");
                CREATE INDEX "mealDishRating_on_mealDishId" ON "mealDishRating"("mealDishId");
                """)
            try DishTidy.adoptMeals(db, now: .now)
        }
    }
}
