import Foundation
import GRDB

// Dish reads and writes (docs/design/dishes.md). Meals write their dishes through
// `AppDatabase.addMeal` and `updateMeal`; everything that changes a dish itself is here.

/// A dish named on a meal being saved: an existing dish picked from the suggestions, or a
/// name typed in, which finds or makes the dish in the meal's kitchen.
struct DishLineDraft: Equatable, Hashable, Sendable {
    var name: String
    /// The dish picked, when one was. A dish of another kitchen is looked up by name instead.
    var dishId: Dish.ID?
    /// The table's face.
    var rating: MealRating?

    init(name: String, dishId: Dish.ID? = nil, rating: MealRating? = nil) {
        self.name = name
        self.dishId = dishId
        self.rating = rating
    }
}

enum DishError: Error, Equatable, LocalizedError {
    case emptyName
    case nameTooLong(limit: Int)
    case tooManyDishes(limit: Int)
    case dishNotFound
    /// Renaming would give the dish another dish's name in the same kitchen.
    case nameTaken(Dish.ID)

    var errorDescription: String? {
        switch self {
        case .emptyName: "Please name the dish."
        case let .nameTooLong(limit): "Dish names can be at most \(limit) characters."
        case let .tooManyDishes(limit): "A meal can have at most \(limit) dishes."
        case .dishNotFound: "That dish was removed."
        case .nameTaken: "There is already a dish with that name here."
        }
    }
}

/// What removing a dish took, to put back with Undo.
struct DishRemoval: Equatable, Sendable {
    var dish: Dish
    var lines: [MealDish]
    var faces: [MealDishRating]
    /// Its recipe (and any on a dish merged into it), which go with it.
    var recipes: [RecipeRemoval] = []
    /// The planned dinners that named it, which keep their words but no longer link.
    var plans: [MealPlan] = []
}

extension AppDatabase {
    // MARK: Dishes on a meal

    /// Replaces a meal's dish lines with `drafts`, in order, and writes the meal's title,
    /// face and illustration from them. A line for a dish the meal already had keeps its
    /// id, and so everyone's own faces. No drafts leaves the meal titled by its slot.
    static func writeDishes(_ drafts: [DishLineDraft], entry: inout JournalEntry, householdId: Household.ID, db: Database, now: Date) throws {
        guard drafts.count <= DishName.perMeal else { throw DishError.tooManyDishes(limit: DishName.perMeal) }
        let kitchen = DishKitchen.of(entry)
        var dishes: [Dish] = []
        for draft in drafts {
            let dish = try resolveDish(draft, kitchen: kitchen, householdId: householdId, db: db, now: now)
            // The same dish twice is one line.
            if !dishes.contains(where: { $0.id == dish.id }) { dishes.append(dish) }
        }
        let existing = try MealDish.filter(Column("entryId") == entry.id).fetchAll(db)
        var kept: Set<MealDish.ID> = []
        for (index, dish) in dishes.enumerated() {
            let rating = drafts.first { $0.dishId == dish.id || DishName.key($0.name) == dish.key }?.rating
            if var line = existing.first(where: { $0.dishId == dish.id && !kept.contains($0.id) }) {
                kept.insert(line.id)
                let before = line
                line.sortOrder = index
                line.rating = rating
                if line != before { try line.update(db) }
            } else {
                let line = MealDish(entryId: entry.id, dishId: dish.id, sortOrder: index, rating: rating)
                try line.insert(db)
                kept.insert(line.id)
            }
        }
        for line in existing where !kept.contains(line.id) {
            _ = try line.delete(db)
        }
        try DishTidy.writeCopies(of: &entry, db: db)
    }

    /// The dish a line names, in the meal's kitchen: the one picked when it belongs there,
    /// else the one of that name, else a new one.
    private static func resolveDish(_ draft: DishLineDraft, kitchen: DishKitchen, householdId: Household.ID, db: Database, now: Date) throws -> Dish {
        let name = DishName.cleaned(draft.name)
        if let id = draft.dishId, let picked = try DishTidy.live(id, db: db), picked.householdId == householdId, picked.kitchen == kitchen {
            return picked
        }
        guard !DishName.key(name).isEmpty else { throw DishError.emptyName }
        guard name.count <= DishName.limit else { throw DishError.nameTooLong(limit: DishName.limit) }
        return try DishTidy.findOrMake(name: name, kitchen: kitchen, householdId: householdId, emoji: nil, tint: nil, db: db, now: now)
    }

    /// Moves a meal's dish lines to the dishes of the same names in its kitchen, after the
    /// meal changed restaurant or where it came from. Dishes left with no meals go, unless
    /// they are favourites.
    static func moveDishes(of entry: JournalEntry, householdId: Household.ID, db: Database, now: Date) throws {
        let kitchen = DishKitchen.of(entry)
        let lines = try MealDish.filter(Column("entryId") == entry.id).fetchAll(db)
        var left: Set<Dish.ID> = []
        for var line in lines {
            guard let dish = try DishTidy.live(line.dishId, db: db), dish.kitchen != kitchen else { continue }
            let moved = try DishTidy.findOrMake(name: dish.name, kitchen: kitchen, householdId: householdId, emoji: dish.emoji, tint: dish.tint, db: db, now: now)
            if lines.contains(where: { $0.dishId == moved.id }) {
                _ = try line.delete(db)
            } else {
                line.dishId = moved.id
                try line.update(db)
            }
            left.insert(dish.id)
        }
        for id in left { try DishTidy.dropIfUnused(id, db: db) }
    }

    // MARK: Changing a dish

    /// Renames a dish everywhere: every meal's line follows, and their titles with it.
    /// A name another dish of the same kitchen has throws `nameTaken`, to offer a merge.
    func renameDish(id: Dish.ID, to rawName: String) throws {
        let name = DishName.cleaned(rawName)
        guard !DishName.key(name).isEmpty else { throw DishError.emptyName }
        guard name.count <= DishName.limit else { throw DishError.nameTooLong(limit: DishName.limit) }
        try writer.write { db in
            guard var dish = try DishTidy.live(id, db: db) else { throw DishError.dishNotFound }
            if let other = try DishTidy.named(name, kitchen: dish.kitchen, householdId: dish.householdId, db: db), other.id != dish.id {
                throw DishError.nameTaken(other.id)
            }
            try DishTidy.rename(&dish, to: name, db: db)
        }
    }

    /// Merges `id` into `survivor`, both of one kitchen: every line and face moves to the
    /// survivor, and the merged dish stays only as a pointer to it.
    func mergeDish(id: Dish.ID, into survivor: Dish.ID) throws {
        try writer.write { db in
            try DishTidy.merge(id, into: survivor, db: db)
        }
    }

    func setFavorite(dishId: Dish.ID, _ favorite: Bool) throws {
        try writer.write { db in
            guard var dish = try DishTidy.live(dishId, db: db) else { throw DishError.dishNotFound }
            dish.favorite = favorite
            try dish.update(db)
        }
    }

    /// Takes a dish off every meal and removes it. The meals stay, titled by their other
    /// dishes or their slot. Returns what Undo puts back.
    @discardableResult
    func removeDish(id: Dish.ID) throws -> DishRemoval {
        try writer.write { db in
            guard let dish = try Dish.fetchOne(db, id: id) else { throw DishError.dishNotFound }
            let lines = try MealDish.filter(Column("dishId") == id).fetchAll(db)
            let faces = try MealDishRating.filter(lines.map(\.id).contains(Column("mealDishId"))).fetchAll(db)
            let dishIds = [id] + (try RecipeTidy.mergedInto(id, db: db))
            let recipes = try Recipe.filter(dishIds.contains(Column("dishId"))).fetchAll(db)
            let recipeRemovals = try recipes.map { try RecipeTidy.removal(of: $0, db: db) }
            let plans = try MealPlan.filter(Column("householdId") == dish.householdId && dishIds.contains(Column("dishId"))).fetchAll(db)
            for line in lines { _ = try line.delete(db) }
            for recipe in recipes { try RecipeTidy.delete(recipe, db: db) }
            for var plan in plans {
                plan.dishId = nil
                try plan.update(db)
            }
            _ = try dish.delete(db)
            for entryId in Set(lines.map(\.entryId)) {
                guard var entry = try JournalEntry.fetchOne(db, id: entryId) else { continue }
                try DishTidy.writeCopies(of: &entry, db: db)
            }
            return DishRemoval(dish: dish, lines: lines, faces: faces, recipes: recipeRemovals, plans: plans)
        }
    }

    /// Puts back what `removeDish` took, on the meals that are still there.
    func restore(_ removal: DishRemoval) throws {
        try writer.write { db in
            try removal.dish.upsert(db)
            for line in removal.lines {
                guard try JournalEntry.exists(db, id: line.entryId) else { continue }
                try line.upsert(db)
            }
            for face in removal.faces {
                guard try MealDish.exists(db, id: face.mealDishId) else { continue }
                try face.upsert(db)
            }
            for recipe in removal.recipes { try RecipeTidy.restore(recipe, db: db) }
            for plan in removal.plans {
                // Only a dinner that is still planned, with the same words, links again.
                guard var current = try MealPlan.fetchOne(db, id: plan.id), current.dishId == nil, DishName.key(current.title) == DishName.key(plan.title) else { continue }
                current.dishId = plan.dishId
                try current.update(db)
            }
            try DishTidy.rewriteCopies(ofMealsWith: [removal.dish.id], db: db)
        }
    }

    // MARK: Faces

    /// The table's face for one dish on a meal.
    func setTableFace(lineId: MealDish.ID, _ rating: MealRating?) throws {
        try writer.write { db in
            guard var line = try MealDish.fetchOne(db, id: lineId) else { throw DishError.dishNotFound }
            line.rating = rating
            try line.update(db)
            guard var entry = try JournalEntry.fetchOne(db, id: line.entryId) else { return }
            try DishTidy.writeCopies(of: &entry, db: db)
        }
    }

    /// A person's own face for a dish on a meal; nil goes back to the table's.
    func setPersonFace(lineId: MealDish.ID, personId: Person.ID, _ rating: MealRating?) throws {
        try writer.write { db in
            guard let line = try MealDish.fetchOne(db, id: lineId) else { throw DishError.dishNotFound }
            let face = MealDishRating(mealDishId: lineId, personId: personId, rating: rating ?? .meh)
            if rating != nil { try face.upsert(db) } else { _ = try MealDishRating.deleteOne(db, id: face.id) }
            guard var entry = try JournalEntry.fetchOne(db, id: line.entryId) else { return }
            try DishTidy.writeCopies(of: &entry, db: db)
        }
    }

    // MARK: Tidying after sync

    /// Gives meals an older build logged their dish line, merges dishes two devices made
    /// with one name, and points lines at the dishes theirs were merged into. Safe to run
    /// any time; does nothing when all is tidy.
    func tidyDishes(now: Date = .now) throws {
        try writer.write { db in
            try DishTidy.run(db, now: now)
        }
    }

    /// Whether `tidyDishes` has anything to do, read without writing.
    func dishesNeedTidying() throws -> Bool {
        try writer.read(DishTidy.needed)
    }
}

/// The rules that keep dishes consistent, shared by the upgrade, saving a meal and tidying
/// after sync.
enum DishTidy {
    /// A dish by id, following merges to the one that survives; nil when there is none.
    static func live(_ id: Dish.ID, db: Database) throws -> Dish? {
        var seen: Set<Dish.ID> = []
        var current = try Dish.fetchOne(db, id: id)
        while let dish = current, let next = dish.mergedInto, !seen.contains(dish.id) {
            seen.insert(dish.id)
            current = try Dish.fetchOne(db, id: next)
        }
        return current
    }

    /// The live dish of that name in the kitchen, the oldest when there are two.
    static func named(_ name: String, kitchen: DishKitchen, householdId: Household.ID, db: Database) throws -> Dish? {
        let key = DishName.key(name)
        return try candidates(kitchen: kitchen, householdId: householdId, db: db).first { $0.key == key }
    }

    private static func candidates(kitchen: DishKitchen, householdId: Household.ID, db: Database) throws -> [Dish] {
        try Dish
            .filter(Dish.Columns.householdId == householdId && Column("kitchen") == kitchen.kind && Column("mergedInto") == nil)
            .filter(kitchen.placeId == nil ? Column("placeId") == nil : Column("placeId") == kitchen.placeId)
            .order(Column("createdAt"), Column("id"))
            .fetchAll(db)
    }

    static func findOrMake(name: String, kitchen: DishKitchen, householdId: Household.ID, emoji: String?, tint: Int?, db: Database, now: Date) throws -> Dish {
        if let existing = try named(name, kitchen: kitchen, householdId: householdId, db: db) { return existing }
        var id = Dish.id(householdId: householdId, kitchen: kitchen, name: name)
        // The derived id is taken when a dish first named so was renamed since.
        if try Dish.exists(db, id: id) { id = .new() }
        let dish = Dish(
            id: id,
            householdId: householdId,
            name: name,
            emoji: emoji ?? DishIllustration.suggestEmoji(for: name) ?? DishIllustration.fallbackEmoji,
            tint: tint ?? DishIllustration.suggestTint(for: name),
            kitchenKind: kitchen.kind,
            placeId: kitchen.placeId,
            createdAt: now
        )
        try dish.insert(db)
        return dish
    }

    /// Removes a dish nobody eats any more, unless it is a favourite or has a recipe.
    static func dropIfUnused(_ id: Dish.ID, db: Database) throws {
        guard let dish = try Dish.fetchOne(db, id: id), !dish.favorite, dish.mergedInto == nil else { return }
        guard try MealDish.filter(Column("dishId") == id).fetchCount(db) == 0 else { return }
        guard try RecipeTidy.recipe(ofLive: id, db: db) == nil else { return }
        _ = try dish.delete(db)
    }

    /// Renames a dish: every meal's title written from it follows, and every dinner
    /// planned from it under its old name.
    static func rename(_ dish: inout Dish, to name: String, db: Database) throws {
        let oldName = dish.name
        let illustrated = DishIllustration.suggestEmoji(for: dish.name) == dish.emoji
        dish.name = name
        if illustrated {
            dish.emoji = DishIllustration.suggestEmoji(for: name) ?? dish.emoji
        }
        try dish.update(db)
        try rewriteCopies(ofMealsWith: [dish.id], db: db)
        try PlannedDish.rename(plansOf: Set([dish.id] + (try RecipeTidy.mergedInto(dish.id, db: db))), from: oldName, to: dish, db: db)
    }

    static func merge(_ id: Dish.ID, into survivorId: Dish.ID, db: Database) throws {
        guard id != survivorId, var merged = try live(id, db: db), var survivor = try live(survivorId, db: db), merged.id != survivor.id else {
            throw DishError.dishNotFound
        }
        let lines = try MealDish.filter(Column("dishId") == merged.id).fetchAll(db)
        for var line in lines {
            if let twin = try MealDish.filter(Column("entryId") == line.entryId && Column("dishId") == survivor.id).fetchOne(db) {
                // The meal had both: keep the survivor's line, with any face only the other had.
                for face in try MealDishRating.filter(Column("mealDishId") == line.id).fetchAll(db) {
                    let moved = MealDishRating(mealDishId: twin.id, personId: face.personId, rating: face.rating)
                    if try !MealDishRating.exists(db, id: moved.id) { try moved.insert(db) }
                }
                if twin.rating == nil, let rating = line.rating {
                    var twin = twin
                    twin.rating = rating
                    try twin.update(db)
                }
                _ = try line.delete(db)
            } else {
                line.dishId = survivor.id
                try line.update(db)
            }
        }
        if merged.favorite, !survivor.favorite {
            survivor.favorite = true
            try survivor.update(db)
        }
        merged.mergedInto = survivor.id
        merged.favorite = false
        try merged.update(db)
        try rewriteCopies(ofMealsWith: [survivor.id], db: db)
        // Dinners planned from the merged dish name the survivor now. Its recipe stays where
        // it is: the survivor's own recipe wins, else readers find it through the merge.
        try PlannedDish.rename(plansOf: [merged.id], from: merged.name, to: survivor, db: db)
    }

    // MARK: Copies

    /// Writes a meal's title, face and illustration from its dishes. A meal with no dishes
    /// keeps what it has, but one titled by a dish it lost goes back to its slot's name.
    static func writeCopies(of entry: inout JournalEntry, db: Database) throws {
        let lines = try MealDish.filter(Column("entryId") == entry.id).order(Column("sortOrder"), Column("id")).fetchAll(db)
        let before = entry
        if lines.isEmpty {
            entry.title = entry.slot
            entry.emoji = DishIllustration.suggestEmoji(for: entry.slot) ?? DishIllustration.fallbackEmoji
            entry.tint = DishIllustration.suggestTint(for: entry.slot)
        } else {
            var dishes: [Dish] = []
            for line in lines {
                if let dish = try live(line.dishId, db: db) { dishes.append(dish) }
            }
            // A line whose dish hasn't arrived yet leaves the copies as they are.
            guard dishes.count == lines.count else { return }
            let faces = try MealDishRating.filter(lines.map(\.id).contains(Column("mealDishId"))).fetchAll(db)
            entry.title = MealCopies.title(dishes: dishes.map(\.name), slot: entry.slot)
            entry.rating = MealCopies.face(tableFaces: lines.map(\.rating), personFaces: faces.map(\.rating))
            entry.emoji = dishes[0].emoji
            entry.tint = dishes[0].tint
        }
        if entry != before { try entry.update(db) }
    }

    /// After an edit that didn't name dishes: a meal that has them is titled by them.
    static func rewriteCopiesIfDishes(of entry: inout JournalEntry, db: Database) throws {
        guard try MealDish.filter(Column("entryId") == entry.id).fetchCount(db) > 0 else { return }
        try writeCopies(of: &entry, db: db)
    }

    static func rewriteCopies(ofMealsWith dishIds: Set<Dish.ID>, db: Database) throws {
        let entryIds = try MealDish.filter(dishIds.contains(Column("dishId"))).fetchAll(db).map(\.entryId)
        for id in Set(entryIds) {
            guard var entry = try JournalEntry.fetchOne(db, id: id) else { continue }
            try writeCopies(of: &entry, db: db)
        }
    }

    // MARK: Adopting and tidying

    /// Meals with a typed name and no dish lines: from before dishes, or logged since by an
    /// older build. A title that is a meal's name ("Dinner") is no dish.
    ///
    /// A meal whose dish lines iCloud already sent, waiting in the sync engine's metadata
    /// for a build that knows them (one that was older until this update), isn't one: the
    /// engine puts those lines in when it starts.
    private static func unadopted(_ db: Database) throws -> [(entry: JournalEntry, householdId: Household.ID)] {
        let waiting = try db.tableExists("sqlitedata_icloud_metadata")
            ? """
              AND NOT EXISTS (SELECT 1 FROM sqlitedata_icloud_metadata m
                  WHERE m.recordType = 'mealDish' AND m.parentRecordPrimaryKey = e.id AND NOT m._isDeleted)
              """
            : ""
        let rows = try Row.fetchAll(db, sql: """
            SELECT e.*, j.householdId AS householdId, j.slots AS journalSlots FROM journalEntry e
            JOIN journal j ON j.id = e.journalId
            WHERE NOT EXISTS (SELECT 1 FROM mealDish d WHERE d.entryId = e.id)
            \(waiting)
            ORDER BY e.eatenAt, e.id
            """)
        let slotNames = Set(MealSlot.known.map { DishName.key($0.name) })
        return try rows.compactMap { row in
            let entry = try JournalEntry(row: row)
            let journalSlots = (try? JSONDecoder().decode([String].self, from: Data((row["journalSlots"] as String? ?? "[]").utf8))) ?? []
            let key = DishName.key(entry.title)
            guard !key.isEmpty, !slotNames.contains(key), !journalSlots.map(DishName.key).contains(key) else { return nil }
            return (entry, row["householdId"])
        }
    }

    /// One dish line for every meal that needs one, with the ids every device would pick.
    static func adoptMeals(_ db: Database, now: Date) throws {
        for (entry, householdId) in try unadopted(db) {
            let kitchen = DishKitchen.of(entry)
            let name = String(DishName.cleaned(entry.title).prefix(DishName.limit))
            let dish = try findOrMake(name: name, kitchen: kitchen, householdId: householdId, emoji: entry.emoji, tint: entry.tint, db: db, now: entry.createdAt)
            let line = MealDish(id: MealDish.adoptedId(entryId: entry.id), entryId: entry.id, dishId: dish.id, sortOrder: 0, rating: entry.rating)
            try line.upsert(db)
        }
    }

    /// Live dishes that share a name and a kitchen, grouped, oldest first.
    private static func twins(_ db: Database) throws -> [[Dish]] {
        let dishes = try Dish.filter(Column("mergedInto") == nil).order(Column("createdAt"), Column("id")).fetchAll(db)
        let groups = Dictionary(grouping: dishes) { "\($0.householdId)|\($0.kitchen.idPart)|\($0.key)" }
        return groups.values.filter { $0.count > 1 }.map { $0.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) } }
    }

    /// Lines that still name a merged dish: they arrived after the merge.
    private static func strayLines(_ db: Database) throws -> [MealDish] {
        try MealDish.fetchAll(db, sql: """
            SELECT l.* FROM mealDish l JOIN dish d ON d.id = l.dishId WHERE d.mergedInto IS NOT NULL
            """)
    }

    static func needed(_ db: Database) throws -> Bool {
        try !unadopted(db).isEmpty || !twins(db).isEmpty || !strayLines(db).isEmpty
    }

    static func run(_ db: Database, now: Date) throws {
        try adoptMeals(db, now: now)
        for group in try twins(db) {
            for twin in group.dropFirst() { try merge(twin.id, into: group[0].id, db: db) }
        }
        for line in try strayLines(db) {
            guard let survivor = try live(line.dishId, db: db) else { continue }
            if try MealDish.filter(Column("entryId") == line.entryId && Column("dishId") == survivor.id).fetchCount(db) > 0 {
                _ = try line.delete(db)
            } else {
                var line = line
                line.dishId = survivor.id
                try line.update(db)
            }
            guard var entry = try JournalEntry.fetchOne(db, id: line.entryId) else { continue }
            try writeCopies(of: &entry, db: db)
        }
    }
}
