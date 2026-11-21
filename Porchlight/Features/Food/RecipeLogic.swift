import Foundation

// The rules and words of recipes, without any view or database (docs/design/dishes.md,
// "Recipes"). Pure, covered by RecipeLogicTests.

/// What a recipe may hold.
enum RecipeLimits {
    static let lines = 80
    static let lineLength = 200
    static let notes = 2_000
    static let link = 2_000
    static let photos = 6
    static let serves = 1...99
}

/// Ingredients and steps are plain lines. Pasted from a website or a note, they come with
/// bullets, numbers and blank lines; these go, so each line is one ingredient or one step.
enum RecipeText {
    /// The text's lines, trimmed, without blank ones.
    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Lines as they are stored: one per line, nothing blank.
    static func stored(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Pasted text as lines, without the bullets and numbering it came with:
    /// "• 2 lb chicken", "1. Brown the chicken", "Step 2: Simmer" become their words.
    static func pasted(_ text: String) -> [String] {
        lines(text).map(withoutMarker).filter { !$0.isEmpty }
    }

    private static func withoutMarker(_ line: String) -> String {
        var rest = Substring(line)
        // "Step 3:", "Step 3." or "step 4 - "
        if let afterStep = stepMarkerEnd(rest) {
            rest = rest[afterStep...]
        } else if let first = rest.first, "•·-*–▪◦".contains(first) {
            rest = rest.dropFirst()
        } else if let end = rest.firstIndex(where: { !$0.isNumber }), end > rest.startIndex,
                  [".", ")"].contains(rest[end]), rest.index(after: end) < rest.endIndex, rest[rest.index(after: end)] == " " {
            // "1. ", "12) ", but not "2 lb" or "1.5 cups".
            rest = rest[rest.index(after: end)...]
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// Where "Step 3:" (or "step 4 -", "Step 2.") ends, if the line starts with one.
    private static func stepMarkerEnd(_ line: Substring) -> Substring.Index? {
        guard line.lowercased().hasPrefix("step ") else { return nil }
        var index = line.index(line.startIndex, offsetBy: 5)
        let digits = index
        while index < line.endIndex, line[index].isNumber { index = line.index(after: index) }
        guard index > digits else { return nil }
        while index < line.endIndex, line[index] == " " { index = line.index(after: index) }
        guard index < line.endIndex, [":", ".", "-", ")"].contains(line[index]) else { return nil }
        return line.index(after: index)
    }

    /// A link as stored: a web address, with "https://" added when it was left off; nil
    /// for nothing typed, and `invalid` for what isn't one.
    static func link(_ raw: String) -> Result<String?, RecipeError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }
        guard trimmed.count <= RecipeLimits.link, !trimmed.contains(where: \.isWhitespace) else { return .failure(.invalidLink) }
        let full = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let host = url.host(), host.contains("."), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return .failure(.invalidLink)
        }
        return .success(full)
    }
}

/// An ingredient line as a grocery item: what to buy, without how much.
/// "2 lb chicken thighs" is "Chicken thighs", "1 thumb of ginger" is "Ginger",
/// "1 can coconut milk" is "Coconut milk".
enum Ingredient {
    private static let units: Set<String> = [
        "lb", "lbs", "pound", "pounds", "oz", "ounce", "ounces", "g", "gram", "grams", "kg", "kilo", "kilos",
        "ml", "l", "liter", "liters", "litre", "litres", "cup", "cups", "tbsp", "tbsps", "tablespoon", "tablespoons",
        "tsp", "tsps", "teaspoon", "teaspoons", "can", "cans", "tin", "tins", "jar", "jars", "clove", "cloves",
        "thumb", "thumbs", "pinch", "pinches", "bunch", "bunches", "handful", "handfuls", "slice", "slices",
        "piece", "pieces", "stick", "sticks", "sprig", "sprigs", "head", "heads", "pack", "packs", "packet", "packets",
        "bag", "bags", "box", "boxes", "bottle", "bottles", "dash", "dashes", "knob", "large", "medium", "small",
    ]

    static func groceryName(_ line: String) -> String {
        var words = line.split(separator: " ").map(String.init)
        // A leading amount: "2", "1.5", "1/2", "½", "2-3", "a", "an", "a few".
        while let first = words.first, isAmount(first) { words.removeFirst() }
        while let first = words.first, units.contains(first.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))) {
            words.removeFirst()
        }
        if words.first?.lowercased() == "of" { words.removeFirst() }
        // What follows a comma is how to cut it: "1 onion, diced".
        var name = words.joined(separator: " ")
        if let comma = name.firstIndex(of: ","), comma > name.startIndex { name = String(name[..<comma]) }
        name = name.trimmingCharacters(in: .whitespaces)
        guard let first = name.first else { return line.trimmingCharacters(in: .whitespaces) }
        return first.uppercased() + name.dropFirst()
    }

    private static func isAmount(_ word: String) -> Bool {
        let lowered = word.lowercased()
        if ["a", "an", "few", "some", "x"].contains(lowered) { return true }
        let amount = CharacterSet(charactersIn: "0123456789./-½⅓⅔¼¾⅛xX")
        return !word.isEmpty && word.unicodeScalars.allSatisfy(amount.contains) && word.contains(where: { $0.isNumber || "½⅓⅔¼¾⅛".contains($0) })
    }
}

enum RecipeError: Error, Equatable, LocalizedError {
    case emptyName
    case nameTooLong(limit: Int)
    case notAHomeDish
    case recipeNotFound
    case tooManyLines(limit: Int)
    case lineTooLong(limit: Int)
    case notesTooLong(limit: Int)
    case invalidLink
    case invalidServes
    case tooManyPhotos(limit: Int)
    /// The name is another home dish's, which has its own recipe.
    case nameTaken(Dish.ID)

    var errorDescription: String? {
        switch self {
        case .emptyName: "Please name the recipe."
        case let .nameTooLong(limit): "Recipe names can be at most \(limit) characters."
        case .notAHomeDish: "Only a dish we cook at home can have a recipe."
        case .recipeNotFound: "That recipe was removed."
        case let .tooManyLines(limit): "Ingredients and steps can be at most \(limit) lines each."
        case let .lineTooLong(limit): "A line can be at most \(limit) characters."
        case let .notesTooLong(limit): "Notes can be at most \(limit) characters."
        case .invalidLink: "That doesn't look like a web address."
        case .invalidServes: "Serves is a number from 1 to 99."
        case let .tooManyPhotos(limit): "A recipe can have at most \(limit) photos."
        case .nameTaken: "There is already a recipe with that name."
        }
    }
}

/// The words recipes are shown with.
enum RecipeWords {
    /// Over the bank: "No recipes yet", "1 recipe", "4 recipes".
    static func count(_ count: Int) -> String {
        switch count {
        case ...0: "No recipes yet"
        case 1: "1 recipe"
        default: "\(count) recipes"
        }
    }

    /// "cooked once", "cooked twice", "cooked 6 times", or "not cooked yet".
    static func cooked(_ times: Int) -> String {
        switch times {
        case ...0: "not cooked yet"
        case 1: "cooked once"
        case 2: "cooked twice"
        default: "cooked \(times) times"
        }
    }

    /// "last Nov 2", or "last Nov 2, 2025" from another year.
    static func last(_ date: Date, now: Date, calendar: Calendar) -> String {
        let style = Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day()
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return "last " + date.formatted(sameYear ? style : style.year())
    }

    /// "cooked 6 times, last on Nov 2", the dish page's line for a home dish with a recipe.
    static func cookedLine(times: Int, last: Date?, now: Date, calendar: Calendar) -> String {
        guard times > 0, let last else { return "Not cooked yet" }
        let style = Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day()
        let when = last.formatted(calendar.isDate(last, equalTo: now, toGranularity: .year) ? style : style.year())
        return "Cooked " + cooked(times).dropFirst("cooked ".count) + ", last on " + when
    }

    /// A recipe's line in the bank: whose, where it came from, how often it was cooked:
    /// "Mia's · cooked 6 times · last Nov 2", "From a link · cooked twice · last Oct 26",
    /// "📷 Card photo · not cooked yet".
    static func bankLine(addedBy: String?, hasLink: Bool, hasCard: Bool, times: Int, last: Date?, now: Date, calendar: Calendar) -> String {
        var parts: [String] = []
        if let addedBy { parts.append(addedBy.possessive) }
        else if hasLink { parts.append("From a link") }
        else if hasCard { parts.append("📷 Card photo") }
        parts.append(cooked(times))
        if times > 0, let last { parts.append(self.last(last, now: now, calendar: calendar)) }
        return parts.joined(separator: " · ")
    }

    /// How many a recipe feeds, for its page: "serves 4".
    static func serves(_ count: Int?) -> String? {
        count.map { "serves \($0)" }
    }

    /// What adding ingredients to groceries says: "3 items added to groceries" and their names.
    static func addedToGroceries(_ names: [String]) -> (title: String, detail: String) {
        let count = names.count
        let title = count == 1 ? "1 item added to groceries" : "\(count) items added to groceries"
        return (title, ListFormat.join(names.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() }))
    }

    /// What the remove sheet says will go, and what stays.
    static func removeSheet(dishName: String, meals: Int, plannedDinners: Int) -> String {
        var stays = "\(dishName) stays a dish"
        if meals > 0 { stays += ", with its \(meals == 1 ? "1 meal" : "\(meals) meals") and faces" }
        if plannedDinners > 0 { stays += plannedDinners == 1 ? ", and its planned dinner stays" : ", and its \(plannedDinners) planned dinners stay" }
        return "Its ingredients, steps, notes and card photos go from every device. " + stays + "."
    }
}
