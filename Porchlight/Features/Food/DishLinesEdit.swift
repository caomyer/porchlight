import Foundation

/// The dishes of a meal while Snap or Edit has it open (docs/design/dishes.md, "The
/// editor"): an ordered list of dish lines, each with the table's face, and the text being
/// typed for the next one. Text left in the field when the meal saves is its last dish, so
/// typing a name and tapping Save is enough. Pure, covered by DishLinesEditTests.
struct DishLinesEdit: Equatable, Sendable {
    struct Line: Identifiable, Equatable, Sendable {
        let id: UUID
        var name: String
        /// The dish picked from a suggestion or a chip, or the one the meal already had.
        var dishId: Dish.ID?
        var rating: MealRating?
        /// The line was on the meal when the edit began.
        var wasSaved: Bool

        init(name: String, dishId: Dish.ID? = nil, rating: MealRating? = nil, wasSaved: Bool = false) {
            id = UUID()
            self.name = name
            self.dishId = dishId
            self.rating = rating
            self.wasSaved = wasSaved
        }

        var key: String { DishName.key(name) }
    }

    var lines: [Line] = []
    /// The field for the next dish.
    var text = ""

    init(lines: [Line] = []) {
        self.lines = lines
    }

    /// A saved meal's dishes, in order, with the table's faces.
    init(_ dishes: [(line: MealDish, dish: Dish)]) {
        lines = dishes.map { Line(name: $0.dish.name, dishId: $0.dish.id, rating: $0.line.rating, wasSaved: true) }
    }

    /// Whether the meal names no dish at all, counting what is typed.
    var isEmpty: Bool { lines.isEmpty && DishName.key(text).isEmpty }

    var isFull: Bool { lines.count >= DishName.perMeal }

    /// The keys of the dishes already on the meal, to leave out of suggestions and chips.
    var keys: Set<String> { Set(lines.map(\.key)) }

    var dishIds: Set<Dish.ID> { Set(lines.compactMap(\.dishId)) }

    /// Adds a dish by name, or a picked one. The same dish twice, a blank name, or a
    /// thirteenth dish adds nothing. Returns whether it was added.
    @discardableResult
    mutating func add(_ rawName: String, dishId: Dish.ID? = nil) -> Bool {
        let name = DishName.cleaned(rawName)
        guard !DishName.key(name).isEmpty, !isFull, !keys.contains(DishName.key(name)) else { return false }
        if let dishId, dishIds.contains(dishId) { return false }
        lines.append(Line(name: String(name.prefix(DishName.limit)), dishId: dishId))
        return true
    }

    /// Adds what is typed as a dish and clears the field.
    @discardableResult
    mutating func commitText() -> Bool {
        let added = add(text)
        if added || DishName.key(text).isEmpty || keys.contains(DishName.key(text)) { text = "" }
        return added
    }

    mutating func remove(_ id: Line.ID) {
        lines.removeAll { $0.id == id }
    }

    /// Moves a line up (negative) or down (positive) by `offset`, staying in the list.
    mutating func move(_ id: Line.ID, by offset: Int) {
        guard let from = lines.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + offset, 0), lines.count - 1)
        guard to != from else { return }
        let line = lines.remove(at: from)
        lines.insert(line, at: to)
    }

    mutating func setRating(_ id: Line.ID, _ rating: MealRating?) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].rating = rating
    }

    /// The meal's dishes to save, in order, with the text still in the field as the last.
    var drafts: [DishLineDraft] {
        var edit = self
        edit.commitText()
        return edit.lines.map { DishLineDraft(name: $0.name, dishId: $0.dishId, rating: $0.rating) }
    }
}

/// Which kitchen a meal's dishes belong to while its form is open, and how the form says
/// it. A named restaurant wins, then home, else elsewhere (`DishKitchen.of`); a restaurant
/// typed but never eaten at yet has no dishes to suggest.
struct DishFormKitchen: Equatable, Sendable {
    var kitchen: DishKitchen
    /// "from Pho Saigon House", "home-cooked", "from elsewhere".
    var words: String

    static func of(sources: MealSources, place: PlaceDraft?, known: FoodPlace?) -> DishFormKitchen {
        let kinds = Set(sources.kinds)
        if kinds.contains(where: \.hasPlace), let place, !DishName.key(place.name).isEmpty {
            // A restaurant new to the diary matches no dish: a kitchen of its own, still empty.
            return DishFormKitchen(kitchen: .place(known?.id ?? .new()), words: "from \(DishName.cleaned(place.name))")
        }
        if kinds.contains(.home) { return DishFormKitchen(kitchen: .home, words: "home-cooked") }
        return DishFormKitchen(kitchen: .elsewhere, words: "from elsewhere")
    }
}
