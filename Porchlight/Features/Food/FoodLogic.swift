import Foundation

// Pure food diary logic: slots, emoji suggestions, weekly stats and memories.
// Everything here is deterministic and covered by PorchlightTests/Food.

// MARK: - Slots

/// What the app knows about a slot name. Custom slot names still work; they just
/// get a neutral emoji and are never guessed from the clock.
struct MealSlot: Equatable, Sendable {
    let name: String
    let emoji: String
    /// Minutes after midnight when this slot usually starts and ends (end exclusive).
    let window: Range<Int>?
    /// Breakfast, lunch and dinner are the main meals shown on Today; snacks are extra.
    let isMain: Bool

    static let breakfast = MealSlot(name: "Breakfast", emoji: "🌅", window: 4 * 60 ..< 10 * 60 + 30, isMain: true)
    static let lunch = MealSlot(name: "Lunch", emoji: "☀️", window: 10 * 60 + 30 ..< 15 * 60, isMain: true)
    static let snack = MealSlot(name: "Snack", emoji: "🍪", window: 15 * 60 ..< 17 * 60, isMain: false)
    static let dinner = MealSlot(name: "Dinner", emoji: "🌙", window: 17 * 60 ..< 22 * 60, isMain: true)

    /// The slots a new food diary can use, in display order.
    static let known: [MealSlot] = [.breakfast, .lunch, .dinner, .snack]
    /// The slots a new food diary starts with.
    static let defaultNames = ["Breakfast", "Lunch", "Dinner"]

    static func named(_ name: String) -> MealSlot {
        known.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? MealSlot(name: name, emoji: "🍽️", window: nil, isMain: true)
    }

    /// A typical time for this slot, used for sample data and as the guess fallback.
    var typicalMinute: Int? {
        window.map { ($0.lowerBound + $0.upperBound) / 2 }
    }

    /// The slot a meal eaten at `date` most likely belongs to, among `enabled` slot names.
    /// Late-night eating counts as a snack; if the matching slot is not enabled, the
    /// enabled slot with the closest typical time wins.
    /// A slot's usual time on a day, e.g. dinner at 6:30pm.
    static func usualTime(of slot: String, on day: DayKey, calendar: Calendar) -> Date {
        let start = day.startDate(in: calendar)
        let minute = named(slot).typicalMinute ?? 12 * 60
        return calendar.date(byAdding: .minute, value: minute, to: start) ?? start
    }

    /// Suggestions under a meal's time: now and a little earlier (kept only on
    /// today), and the slot's usual time.
    static func timeSuggestions(slot: String, day: DayKey, calendar: Calendar) -> [(title: String, time: LogTime)] {
        var suggestions = Array(LogTime.recentSuggestions(justNow: "Now").prefix(3))
        if named(slot).window != nil {
            suggestions.append(("Usual \(slot.lowercased())", .at(usualTime(of: slot, on: day, calendar: calendar))))
        }
        return suggestions
    }

    static func guess(at date: Date, calendar: Calendar, enabled: [String]) -> String? {
        guard !enabled.isEmpty else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 12) * 60 + (parts.minute ?? 0)
        let slots = enabled.map(named)
        let matching = known.first { $0.window?.contains(minute) == true } ?? .snack
        if let hit = slots.first(where: { $0.name == matching.name }) { return hit.name }
        let timed = slots.filter { $0.typicalMinute != nil }
        guard !timed.isEmpty else { return slots[0].name }
        func distance(_ slot: MealSlot) -> Int {
            let delta = abs((slot.typicalMinute ?? 0) - minute)
            return min(delta, 24 * 60 - delta)
        }
        return timed.min { distance($0) < distance($1) }?.name
    }
}

// MARK: - Illustrations

/// Picks an emoji and a tablecloth tint for a dish from its title.
enum DishIllustration {
    /// Keyword groups in priority order: the first group with a matching word wins,
    /// so "avocado toast" is an avocado and "chicken curry" is a curry.
    private static let table: [(keywords: [String], emoji: String, tint: Int)] = [
        (["turkey", "thanksgiving"], "🦃", 0xF1CFA0),
        (["avocado", "guac"], "🥑", 0xD7E5C2),
        (["pancake", "crepe"], "🥞", 0xF3D9A4),
        (["waffle"], "🧇", 0xF3D9A4),
        (["bagel"], "🥯", 0xE6D3B8),
        (["croissant", "pastry"], "🥐", 0xF1DDB4),
        (["granola", "cereal", "oatmeal", "oats", "porridge", "yogurt", "muesli"], "🥣", 0xE9DCC4),
        (["egg", "omelet", "omelette", "frittata", "shakshuka"], "🍳", 0xF5E2A6),
        (["sushi", "sashimi", "maki", "nigiri", "poke"], "🍣", 0xE5D0DA),
        (["bento"], "🍱", 0xD9E2EE),
        (["pho", "ramen", "udon", "soba", "noodle", "noodles", "lo mein", "pad thai", "dan dan"], "🍜", 0xF0D5B8),
        (["pasta", "spaghetti", "pesto", "linguine", "penne", "lasagna", "carbonara", "mac"], "🍝", 0xE8C9B5),
        (["curry", "tikka", "masala", "dal", "korma"], "🍛", 0xF1C78F),
        (["taco", "tacos"], "🌮", 0xF2C6A8),
        (["burrito", "quesadilla", "enchilada"], "🌯", 0xF2D3B0),
        (["falafel", "wrap", "gyro", "shawarma", "kebab", "pita"], "🥙", 0xDCE6CF),
        (["pizza"], "🍕", 0xF4C3B4),
        (["burger", "cheeseburger"], "🍔", 0xF0D0A8),
        (["hot dog", "hotdog"], "🌭", 0xF0D0A8),
        (["banh mi", "sandwich", "sub", "panini", "blt", "club"], "🥪", 0xE8D7C2),
        (["salmon", "miso", "fish", "cod", "tuna", "trout"], "🍲", 0xCBDDE6),
        (["shrimp", "prawn", "tempura"], "🍤", 0xF1D9C0),
        (["dumpling", "dumplings", "gyoza", "bao", "dim sum"], "🥟", 0xEFDCC4),
        (["soup", "stew", "chili", "chowder", "broth"], "🍲", 0xEED2B7),
        (["salad", "cobb", "caesar", "slaw"], "🥗", 0xCFE3C4),
        (["steak", "beef", "brisket", "ribs"], "🥩", 0xEBC7BB),
        (["chicken", "wings", "drumstick"], "🍗", 0xF1D4AC),
        (["rice", "risotto", "bibimbap", "paella", "fried rice"], "🍚", 0xEDE3CF),
        (["fries", "chips"], "🍟", 0xF3DDA5),
        (["toast", "bread", "sourdough"], "🍞", 0xEBD9BC),
        (["cheese"], "🧀", 0xF4E2A6),
        (["cake", "cupcake", "brownie", "pie"], "🍰", 0xF2D6D8),
        (["cookie", "cookies", "biscuit"], "🍪", 0xEBD7BD),
        (["ice cream", "gelato", "sundae"], "🍨", 0xF2DCE2),
        (["smoothie", "shake", "juice"], "🥤", 0xE5D6EA),
        (["popcorn"], "🍿", 0xF3E3B5),
        (["fruit", "apple", "berries", "berry"], "🍎", 0xF2CFC6),
        (["banana"], "🍌", 0xF4E6A8),
    ]

    static let fallbackEmoji = "🍽️"
    /// Tablecloth tints for dishes the table does not know, chosen by a stable hash.
    static let tints: [Int] = [0xF3D9A4, 0xCFE3C4, 0xE8C9B5, 0xD9E2EE, 0xF2C6A8, 0xE5D0DA, 0xCBDDE6, 0xEADFCB]

    /// The emoji for a title, or nil when nothing matches.
    static func suggestEmoji(for title: String) -> String? {
        match(title)?.emoji
    }

    /// The tint for a title, falling back to a stable color from the palette.
    static func suggestTint(for title: String) -> Int {
        if let hit = match(title) { return hit.tint }
        let words = normalized(title)
        let hash = words.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return tints[hash % tints.count]
    }

    private static func match(_ title: String) -> (emoji: String, tint: Int)? {
        let text = " " + normalized(title) + " "
        for entry in table {
            for keyword in entry.keywords where containsWord(keyword, in: text) {
                return (entry.emoji, entry.tint)
            }
        }
        return nil
    }

    /// Lowercased letters and spaces only, so punctuation never blocks a match.
    static func normalized(_ title: String) -> String {
        let lowered = title.lowercased()
        let mapped = lowered.unicodeScalars.map { CharacterSet.letters.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Matches whole words, also allowing a plural "s"/"es" ("pancakes" matches "pancake").
    private static func containsWord(_ keyword: String, in paddedText: String) -> Bool {
        [" \(keyword) ", " \(keyword)s ", " \(keyword)es "].contains { paddedText.contains($0) }
    }
}

// MARK: - Week stats

/// A theme that shows up a lot in a week ("Noodle week").
struct DishTheme: Equatable, Sendable {
    let name: String
    let emoji: String
    let keywords: [String]

    static let all: [DishTheme] = [
        DishTheme(name: "Noodle", emoji: "🍜", keywords: ["noodle", "pho", "ramen", "udon", "soba", "pasta", "spaghetti", "pesto", "lasagna", "linguine", "penne", "lo mein", "pad thai", "dan dan", "carbonara"]),
        DishTheme(name: "Taco", emoji: "🌮", keywords: ["taco", "burrito", "quesadilla", "nacho", "enchilada"]),
        DishTheme(name: "Pizza", emoji: "🍕", keywords: ["pizza"]),
        DishTheme(name: "Sushi", emoji: "🍣", keywords: ["sushi", "sashimi", "poke", "maki", "nigiri"]),
        DishTheme(name: "Curry", emoji: "🍛", keywords: ["curry", "tikka", "masala", "dal", "korma"]),
        DishTheme(name: "Salad", emoji: "🥗", keywords: ["salad", "cobb", "caesar"]),
        DishTheme(name: "Soup", emoji: "🍲", keywords: ["soup", "stew", "chili", "chowder"]),
        DishTheme(name: "Egg", emoji: "🍳", keywords: ["egg", "omelet", "omelette", "frittata"]),
    ]

    func matches(_ title: String) -> Bool {
        let text = " " + DishIllustration.normalized(title) + " "
        return keywords.contains { [" \($0) ", " \($0)s ", " \($0)es "].contains(where: text.contains) }
    }
}

/// The numbers on the "This week" card.
struct WeekStats: Equatable, Sendable {
    var homeCooked = 0
    var delivery = 0
    var dineOut = 0
    var company = 0
    /// The most frequent theme with at least 3 meals, and the dishes behind it.
    var theme: DishTheme?
    var themeDishes: [String] = []
    /// Dishes eaten for the first time this week, best rated first.
    var newDishes: [JournalEntry] = []
    var total: Int { homeCooked + delivery + dineOut + company }

    /// Stats for the entries of `days` (the week), with `history` as everything logged before it.
    static func make(week entries: [JournalEntry], history: [JournalEntry]) -> WeekStats {
        var stats = WeekStats()
        stats.homeCooked = entries.filter { $0.source == .home }.count
        stats.delivery = entries.filter { $0.source == .delivery }.count
        stats.dineOut = entries.filter { $0.source == .dineOut }.count
        stats.company = entries.filter { $0.source == .company }.count

        let chronological = entries.sorted { ($0.day, $0.eatenAt) < ($1.day, $1.eatenAt) }
        let themed = DishTheme.all
            .map { theme in (theme, chronological.filter { theme.matches($0.title) }) }
            .filter { $0.1.count >= 3 }
            .max { $0.1.count < $1.1.count }
        if let (theme, dishes) = themed {
            stats.theme = theme
            stats.themeDishes = dishes.map(\.title)
        }

        let seen = Set(history.map { DishIllustration.normalized($0.title) })
        var firsts: [String: JournalEntry] = [:]
        for entry in chronological where !seen.contains(DishIllustration.normalized(entry.title)) {
            let key = DishIllustration.normalized(entry.title)
            if let existing = firsts[key], (existing.rating?.rawValue ?? 0) >= (entry.rating?.rawValue ?? 0) { continue }
            firsts[key] = entry
        }
        stats.newDishes = firsts.values.sorted {
            ($0.rating?.rawValue ?? 0, $1.day) > ($1.rating?.rawValue ?? 0, $0.day)
        }
        return stats
    }

    /// "Pho, pesto pasta and dan dan noodles": the theme's dishes as a sentence.
    var themeSentence: String {
        var names: [String] = []
        for dish in themeDishes where !names.contains(where: { $0.caseInsensitiveCompare(dish) == .orderedSame }) {
            names.append(names.isEmpty ? dish : dish.lowercased())
        }
        let shown = Array(names.prefix(3))
        let more = names.count - shown.count
        var sentence = ListFormat.join(shown)
        if more > 0 { sentence += " + \(more) more" }
        return sentence
    }
}

enum ListFormat {
    /// "a", "a and b", "a, b and c".
    static func join(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

// MARK: - Streak

enum DiaryStreak {
    /// Consecutive days with something in the diary (a meal or ink), ending today.
    /// An empty today does not break the streak yet; it is counted from yesterday.
    static func length(activeDays: Set<DayKey>, today: DayKey, calendar: Calendar) -> Int {
        var day = activeDays.contains(today) ? today : today.adding(days: -1, calendar: calendar)
        var count = 0
        while activeDays.contains(day) {
            count += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return count
    }

    /// Main slots of `days` before today with no entry ("2 meals slipped by unsnapped").
    static func missedSlots(entries: [JournalEntry], days: [DayKey], today: DayKey, slots: [String]) -> Int {
        let main = slots.filter { MealSlot.named($0).isMain }
        let logged = Set(entries.map { "\($0.day)|\($0.slot)" })
        return days.filter { $0 < today }.reduce(0) { total, day in
            total + main.filter { !logged.contains("\(day.rawValue)|\($0)") }.count
        }
    }
}

// MARK: - On this day

/// A meal from the past worth remembering today.
struct FoodMemory: Equatable, Sendable {
    let entry: JournalEntry
    let monthsAgo: Int

    /// "A year ago", "2 years ago", "3 months ago", "A month ago".
    var whenText: String {
        if monthsAgo % 12 == 0 {
            let years = monthsAgo / 12
            return years == 1 ? "A year ago" : "\(years) years ago"
        }
        return monthsAgo == 1 ? "A month ago" : "\(monthsAgo) months ago"
    }

    /// Looks for meals on this date a year ago (then 2-3 years ago), and otherwise on
    /// the same day of the closest earlier month (11 months ago down to 1).
    /// `withPhotos` names the meals that have photos, which make better memories.
    static func find(in entries: [JournalEntry], withPhotos: Set<JournalEntry.ID> = [], today: DayKey, calendar: Calendar) -> FoodMemory? {
        let byDay = Dictionary(grouping: entries, by: \.day)
        let start = today.startDate(in: calendar)
        for months in [12, 24, 36] + Array((1...11).reversed()) {
            guard let date = calendar.date(byAdding: .month, value: -months, to: start) else { continue }
            let key = DayKey(date, calendar: calendar)
            if let candidates = byDay[key.rawValue], let best = candidates.max(by: { memorable($0, $1, withPhotos: withPhotos) }) {
                return FoodMemory(entry: best, monthsAgo: months)
            }
        }
        return nil
    }

    /// Photos beat illustrations, then higher ratings, then later meals.
    private static func memorable(_ a: JournalEntry, _ b: JournalEntry, withPhotos: Set<JournalEntry.ID>) -> Bool {
        let left = (withPhotos.contains(a.id) ? 1 : 0, a.rating?.rawValue ?? 0, a.eatenAt)
        let right = (withPhotos.contains(b.id) ? 1 : 0, b.rating?.rawValue ?? 0, b.eatenAt)
        return left < right
    }
}
