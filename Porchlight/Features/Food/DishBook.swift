import Foundation

/// Everything the dish screens ask of the diary, read from one snapshot: a dish's history
/// and faces, a restaurant's dishes, suggestions while typing, and search
/// (docs/design/dishes.md). Pure, covered by DishBookTests.
struct DishBook: Sendable {
    let snapshot: FoodSnapshot
    private let dishesById: [Dish.ID: Dish]
    private let entriesById: [JournalEntry.ID: JournalEntry]
    /// Every line, by the live dish it names.
    private let linesByDish: [Dish.ID: [MealDish]]

    init(_ snapshot: FoodSnapshot) {
        self.snapshot = snapshot
        let dishesById = Dictionary(snapshot.dishes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.dishesById = dishesById
        entriesById = Dictionary(snapshot.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func live(_ id: Dish.ID) -> Dish.ID? {
            var seen: Set<Dish.ID> = []
            var current = dishesById[id]
            while let dish = current, let next = dish.mergedInto, seen.insert(dish.id).inserted { current = dishesById[next] }
            return current?.id
        }
        var linesByDish: [Dish.ID: [MealDish]] = [:]
        for line in snapshot.lines.values.joined() {
            if let id = live(line.dishId) { linesByDish[id, default: []].append(line) }
        }
        self.linesByDish = linesByDish
    }

    // MARK: Dishes

    /// The dish by id, following merges; nil for one that is gone or hasn't arrived.
    func dish(_ id: Dish.ID) -> Dish? {
        var seen: Set<Dish.ID> = []
        var current = dishesById[id]
        while let dish = current, let next = dish.mergedInto, seen.insert(dish.id).inserted { current = dishesById[next] }
        return current
    }

    /// Dishes that are shown: not merged into another.
    var liveDishes: [Dish] { snapshot.dishes.filter { $0.mergedInto == nil } }

    /// A meal's dishes in order, each with its line; lines whose dish hasn't arrived are left out.
    func dishes(of entry: JournalEntry) -> [(line: MealDish, dish: Dish)] {
        (snapshot.lines[entry.id] ?? []).compactMap { line in dish(line.dishId).map { (line, $0) } }
    }

    // MARK: History

    /// One meal a dish was on.
    struct Time: Identifiable, Equatable, Sendable {
        var entry: JournalEntry
        var line: MealDish
        /// Each eater's face for it: their own, else the table's.
        var faces: [Person.ID: MealRating]
        var id: MealDish.ID { line.id }
    }

    /// Every meal the dish was on, newest first.
    func times(of dishId: Dish.ID) -> [Time] {
        (linesByDish[dishId] ?? []).compactMap { line -> Time? in
            guard let entry = entriesById[line.entryId] else { return nil }
            return Time(entry: entry, line: line, faces: faces(of: line, entry: entry))
        }
        .sorted { ($0.entry.eatenAt, $0.entry.id) > ($1.entry.eatenAt, $1.entry.id) }
    }

    /// Each eater's face for a line: their own, else the table's.
    func faces(of line: MealDish, entry: JournalEntry) -> [Person.ID: MealRating] {
        var faces: [Person.ID: MealRating] = [:]
        if let rating = line.rating {
            for person in snapshot.eaters[entry.id] ?? [] { faces[person] = rating }
        }
        for face in snapshot.faces[line.id] ?? [] where (snapshot.eaters[entry.id] ?? []).contains(face.personId) {
            faces[face.personId] = face.rating
        }
        return faces
    }

    /// People who gave their own face on a line, different from the table's.
    func ownFaces(of line: MealDish) -> [MealDishRating] {
        snapshot.faces[line.id] ?? []
    }

    /// Which time this is, counting from the first: 1 for a new dish.
    func ordinal(of line: MealDish) -> Int {
        guard let dish = dish(line.dishId), let entry = entriesById[line.entryId] else { return 1 }
        return times(of: dish.id).filter { ($0.entry.eatenAt, $0.entry.id) <= (entry.eatenAt, entry.id) }.count
    }

    struct Summary: Equatable, Sendable {
        var count: Int
        var first: JournalEntry?
        var last: JournalEntry?
        /// The face given most, by anyone, the latest winning a tie.
        var face: MealRating?
    }

    func summary(of dishId: Dish.ID) -> Summary {
        let times = times(of: dishId)
        let faces = times.reversed().flatMap { time in time.faces.values.sorted { $0.rawValue < $1.rawValue } }
        return Summary(count: times.count, first: times.last?.entry, last: times.first?.entry, face: UsualFace.of(faces)?.rating)
    }

    /// Each person's usual face for a dish, for people who live here now, in household order.
    func usualFaces(of dishId: Dish.ID) -> [(person: Person, face: UsualFace)] {
        let times = times(of: dishId).reversed()
        return snapshot.people.compactMap { person in
            UsualFace.of(times.compactMap { $0.faces[person.id] }).map { (person, $0) }
        }
    }

    /// The same name in other kitchens, most eaten first.
    func alsoHad(_ dish: Dish) -> [Dish] {
        liveDishes
            .filter { $0.id != dish.id && $0.key == dish.key }
            .sorted { summary(of: $0.id).count > summary(of: $1.id).count }
    }

    // MARK: Places

    struct PlaceSummary: Equatable, Sendable {
        var visits: Int
        var last: JournalEntry?
        /// Last time's dishes, in the meal's order.
        var lastDishes: [Dish]
        /// Every dish of the place, best face first, then most had.
        var dishes: [Dish]
    }

    func summary(of placeId: FoodPlace.ID) -> PlaceSummary {
        let meals = snapshot.entries.filter { $0.placeId == placeId }.sorted { ($0.eatenAt, $0.id) > ($1.eatenAt, $1.id) }
        let last = meals.first
        return PlaceSummary(
            visits: meals.count,
            last: last,
            lastDishes: last.map { dishes(of: $0).map(\.dish) } ?? [],
            dishes: ranked(liveDishes.filter { $0.kitchen == .place(placeId) && !(linesByDish[$0.id] ?? []).isEmpty })
        )
    }

    /// Best face first, then most had, then most recent.
    func ranked(_ dishes: [Dish]) -> [Dish] {
        let keys = Dictionary(uniqueKeysWithValues: dishes.map { dish in
            let summary = summary(of: dish.id)
            return (dish.id, (face: summary.face?.rawValue ?? 0, count: summary.count, last: summary.last?.eatenAt ?? .distantPast))
        })
        return dishes.sorted { a, b in
            let x = keys[a.id]!, y = keys[b.id]!
            if x.face != y.face { return x.face > y.face }
            if x.count != y.count { return x.count > y.count }
            if x.last != y.last { return x.last > y.last }
            return a.name < b.name
        }
    }

    /// "Last time here": the dishes of the latest other meal at the place.
    func lastTime(at placeId: FoodPlace.ID, excluding entryId: JournalEntry.ID? = nil) -> (entry: JournalEntry, dishes: [Dish])? {
        snapshot.entries
            .filter { $0.placeId == placeId && $0.id != entryId }
            .sorted { ($0.eatenAt, $0.id) > ($1.eatenAt, $1.id) }
            .lazy
            .map { (entry: $0, dishes: dishes(of: $0).map(\.dish)) }
            .first { !$0.dishes.isEmpty }
    }

    // MARK: Suggestions

    struct Suggestion: Identifiable, Equatable, Sendable {
        var dish: Dish
        /// In the kitchen the meal is in.
        var isHere: Bool
        var count: Int
        var last: JournalEntry?
        var face: MealRating?
        var id: Dish.ID { dish.id }
    }

    /// Dishes whose name starts a word with what was typed: the meal's own kitchen first,
    /// most had first; then the same words elsewhere. Home dishes count as "here" for a
    /// home-cooked meal. Dishes already on the meal are left out.
    func suggestions(for text: String, kitchen: DishKitchen, excluding: Set<Dish.ID> = [], limit: Int = 5) -> [Suggestion] {
        let query = DishName.key(text)
        guard !query.isEmpty else { return [] }
        let matches = liveDishes.filter { dish in
            !excluding.contains(dish.id) && Self.matches(query, dish.key) && !(linesByDish[dish.id] ?? []).isEmpty
        }
        let all = matches.map { dish in
            let summary = summary(of: dish.id)
            return Suggestion(dish: dish, isHere: dish.kitchen == kitchen, count: summary.count, last: summary.last, face: summary.face)
        }
        let here = all.filter(\.isHere).sorted(by: Self.mostHad)
        // Elsewhere, one per name: the most had.
        var seen = Set(here.map(\.dish.key)).union(excluding.compactMap { dish($0)?.key })
        let elsewhere = all.filter { !$0.isHere }.sorted(by: Self.mostHad).filter { seen.insert($0.dish.key).inserted }
        return Array((here + elsewhere).prefix(limit))
    }

    private static func mostHad(_ a: Suggestion, _ b: Suggestion) -> Bool {
        if a.count != b.count { return a.count > b.count }
        return (a.last?.eatenAt ?? .distantPast) > (b.last?.eatenAt ?? .distantPast)
    }

    /// Every word of the query starts a word of the name ("bun c" matches "bun cha").
    static func matches(_ query: String, _ name: String) -> Bool {
        let words = name.split(separator: " ")
        return query.split(separator: " ").allSatisfy { part in words.contains { $0.hasPrefix(part) } }
    }

    // MARK: Lists and search

    var favorites: [Dish] { ranked(liveDishes.filter(\.favorite)) }

    /// Home dishes that were had, most had first.
    var homeDishes: [Dish] { byCount(liveDishes.filter { $0.kitchen == .home }) }

    /// Each restaurant with dishes, most visited first, with its dishes ranked.
    var placesWithDishes: [(place: FoodPlace, dishes: [Dish])] {
        snapshot.places.compactMap { place in
            let dishes = ranked(liveDishes.filter { $0.kitchen == .place(place.id) && !(linesByDish[$0.id] ?? []).isEmpty })
            return dishes.isEmpty ? nil : (place, dishes)
        }
        .sorted { summary(of: $0.place.id).visits > summary(of: $1.place.id).visits }
    }

    /// Dishes from work or unnamed places.
    var elsewhereDishes: [Dish] { byCount(liveDishes.filter { $0.kitchen == .elsewhere }) }

    /// Every dish that was had, most had first.
    var mostHad: [Dish] { byCount(liveDishes) }

    private func byCount(_ dishes: [Dish]) -> [Dish] {
        dishes
            .map { ($0, summary(of: $0.id)) }
            .filter { $0.1.count > 0 }
            .sorted { a, b in
                if a.1.count != b.1.count { return a.1.count > b.1.count }
                return (a.1.last?.eatenAt ?? .distantPast) > (b.1.last?.eatenAt ?? .distantPast)
            }
            .map(\.0)
    }

    /// Dishes and places whose names match every word typed.
    func search(_ text: String) -> (dishes: [Dish], places: [FoodPlace]) {
        let query = DishName.key(text)
        guard !query.isEmpty else { return ([], []) }
        let dishes = byCount(liveDishes.filter { Self.matches(query, $0.key) })
        let places = snapshot.places.filter { Self.matches(query, DishName.key($0.name)) }
        return (dishes, places)
    }
}
