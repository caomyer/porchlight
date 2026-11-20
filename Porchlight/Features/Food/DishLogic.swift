import Foundation

// The rules of dishes that need no database: names, kitchens, the meal's title and face
// written from its dishes, and the summaries a dish's page shows
// (docs/design/dishes.md). Pure, covered by DishLogicTests.

/// What makes two dish names the same dish: case, accents, punctuation and spacing don't
/// count, so "Phở tái", "pho tai " and "Pho Tai!" are one.
enum DishName {
    static let limit = 60
    /// Dishes one meal can name.
    static let perMeal = 12

    static func key(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            // Folding keeps "đ" and "ø"; spell them the way people type them.
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "ø", with: "o")
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// The name as typed, trimmed and with its runs of spaces made single.
    static func cleaned(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Where a dish comes from. A dish belongs to one kitchen: ours, one restaurant, or
/// "elsewhere" (work, or a place nobody named).
enum DishKitchen: Hashable, Sendable {
    case home
    case place(FoodPlace.ID)
    case elsewhere

    /// The kitchen of a meal's dishes: the restaurant it names, else home when it was
    /// home-cooked, else elsewhere.
    static func of(sources: Set<MealSource>, placeId: FoodPlace.ID?) -> DishKitchen {
        if let placeId, sources.contains(where: \.hasPlace) { return .place(placeId) }
        if sources.contains(.home) { return .home }
        return .elsewhere
    }

    static func of(_ entry: JournalEntry) -> DishKitchen {
        of(sources: Set(entry.sources.kinds), placeId: entry.placeId)
    }

    /// Stored as `dish.kitchen`.
    var kind: String {
        switch self {
        case .home: "home"
        case .place: "place"
        case .elsewhere: "elsewhere"
        }
    }

    var placeId: FoodPlace.ID? {
        if case let .place(id) = self { id } else { nil }
    }

    /// Read back from a dish row. An unknown kind, from a newer build, reads as elsewhere.
    init(kind: String, placeId: FoodPlace.ID?) {
        switch kind {
        case "home": self = .home
        case "place": self = placeId.map(DishKitchen.place) ?? .elsewhere
        default: self = .elsewhere
        }
    }

    /// The part of a derived dish id that names the kitchen.
    var idPart: String {
        switch self {
        case .home: "home"
        case let .place(id): "place:\(id)"
        case .elsewhere: "elsewhere"
        }
    }
}

/// The copies a meal keeps of its dishes, for older builds and for every place that shows a
/// meal by one name and one face.
enum MealCopies {
    /// "Pho tai, spring rolls, bun cha": the first name as written, the rest lowercased
    /// unless they look like proper names, cut to the title limit. No dishes: the slot.
    static func title(dishes names: [String], slot: String) -> String {
        guard let first = names.first else { return slot }
        let rest = names.dropFirst().map { name in
            name.split(separator: " ").contains { $0.count > 1 && $0.allSatisfy(\.isUppercase) } ? name : lowercasedFirst(name)
        }
        let joined = ([first] + rest).joined(separator: ", ")
        guard joined.count > AppDatabase.dishTitleLimit else { return joined }
        return String(joined.prefix(AppDatabase.dishTitleLimit - 1)).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "…"
    }

    private static func lowercasedFirst(_ name: String) -> String {
        guard let first = name.first, first.isUppercase else { return name }
        // "Thai iced tea" stays as is: only a capital followed by lowercase is softened.
        let second = name.dropFirst().first
        guard second.map({ $0.isLowercase }) ?? true else { return name }
        return first.lowercased() + name.dropFirst()
    }

    /// The meal's face: the best any of its dishes got, from the table or from anyone; nil
    /// when nobody rated anything.
    static func face(tableFaces: [MealRating?], personFaces: [MealRating]) -> MealRating? {
        (tableFaces.compactMap { $0 } + personFaces).max { $0.rawValue < $1.rawValue }
    }
}

/// A person's usual face for a dish: the one they gave most, the latest winning a tie.
struct UsualFace: Equatable, Sendable {
    var rating: MealRating
    /// Times they gave it, and times they rated the dish at all.
    var count: Int
    var of: Int

    /// `faces` oldest first.
    static func of(_ faces: [MealRating]) -> UsualFace? {
        guard !faces.isEmpty else { return nil }
        var counts: [MealRating: Int] = [:]
        var last: [MealRating: Int] = [:]
        for (index, face) in faces.enumerated() {
            counts[face, default: 0] += 1
            last[face] = index
        }
        let best = counts.keys.max { a, b in
            (counts[a]!, last[a]!) < (counts[b]!, last[b]!)
        }!
        return UsualFace(rating: best, count: counts[best]!, of: faces.count)
    }
}
