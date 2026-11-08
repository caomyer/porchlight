import Foundation

// Pure rules behind the Home screens. No database or UI here, so it is easy to test.

// MARK: - Recurrence

enum ChoreSchedule {
    /// Whole days from `from` to `to` (negative when `to` is earlier). DST-safe.
    static func days(from: DayKey, to: DayKey, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: from.startDate(in: calendar), to: to.startDate(in: calendar)).day ?? 0
    }

    /// Whether the chore's pattern lands on `day`. One-off chores land on their due day only.
    static func occurs(_ chore: Chore, on day: DayKey, calendar: Calendar) -> Bool {
        switch chore.recurrence {
        case .once:
            return day == chore.anchor
        case .daily:
            return day >= chore.anchor
        case let .weekdays(weekdays):
            guard day >= chore.anchor else { return false }
            return weekdays.contains(calendar.component(.weekday, from: day.startDate(in: calendar)))
        case let .everyNDays(n):
            let offset = days(from: chore.anchor, to: day, calendar: calendar)
            return offset >= 0 && offset % max(n, 1) == 0
        }
    }

    /// Whether the chore belongs on the board for `day`.
    ///
    /// Repeating chores show on the days they occur. A one-off chore is a to-do: it shows every
    /// day until it is done (early or overdue), then only on the day it was done.
    static func isOnBoard(_ chore: Chore, on day: DayKey, completions: [ChoreCompletion], calendar: Calendar) -> Bool {
        guard !chore.archived else { return false }
        if chore.recurrence.isOnce {
            let done = completions.first { $0.choreId == chore.id }
            return done.map { $0.dayKey == day } ?? true
        }
        return occurs(chore, on: day, calendar: calendar)
    }

    /// The small line under a chore's title: its time hint, or a description of when it is due.
    static func subtitle(for chore: Chore, today: DayKey, calendar: Calendar) -> String {
        if let hint = chore.timeHint, !hint.isEmpty { return hint }
        return describe(chore, today: today, calendar: calendar)
    }

    static func describe(_ chore: Chore, today: DayKey, calendar: Calendar) -> String {
        switch chore.recurrence {
        case .daily:
            return "every day"
        case let .weekdays(days):
            return describe(weekdays: days, calendar: calendar)
        case let .everyNDays(n):
            return n == 1 ? "every day" : n == 7 ? "every week" : "every \(n) days"
        case .once:
            let offset = days(from: today, to: chore.anchor, calendar: calendar)
            switch offset {
            case ..<0: return "overdue"
            case 0: return "due today"
            case 1: return "due tomorrow"
            case 2...6: return "due " + chore.anchor.formatted(.dateTime.weekday(.wide), calendar: calendar)
            default: return "due " + chore.anchor.formatted(.dateTime.month(.abbreviated).day(), calendar: calendar)
            }
        }
    }

    /// "weekdays", "weekends", or "Mon, Wed, Fri" in the calendar's week order.
    static func describe(weekdays days: Set<Int>, calendar: Calendar) -> String {
        if days.count == 7 { return "every day" }
        if days == [2, 3, 4, 5, 6] { return "weekdays" }
        if days == [1, 7] { return "weekends" }
        let symbols = calendar.shortWeekdaySymbols
        return orderedWeekdays(calendar: calendar)
            .filter(days.contains)
            .map { symbols[$0 - 1] }
            .joined(separator: ", ")
    }

    /// Weekday numbers in display order, starting on the calendar's first weekday.
    static func orderedWeekdays(calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

// MARK: - Board

/// The chore board for one day: a column per person, plus "Anyone" for shared chores.
struct ChoreBoard: Equatable {
    struct Task: Equatable, Identifiable {
        var chore: Chore
        var completion: ChoreCompletion?
        var id: Int64 { chore.id ?? -1 }
        var isDone: Bool { completion != nil }
    }

    struct RewardStatus: Equatable, Identifiable {
        var reward: Reward
        var earned: Int
        var id: Int64 { reward.id ?? -1 }
        var fraction: Double { reward.targetStars > 0 ? min(Double(earned) / Double(reward.targetStars), 1) : 0 }
        var isReached: Bool { earned >= reward.targetStars }
    }

    struct Column: Equatable, Identifiable {
        var owner: Owner
        var tasks: [Task]
        /// Stars earned this week: by this person, or on shared chores for "Anyone".
        var weekStars: Int
        var rewards: [RewardStatus]
        var doneCount: Int { tasks.filter(\.isDone).count }
        var id: String {
            switch owner {
            case let .person(id): "person-\(id)"
            case .everyone: "anyone"
            }
        }
    }

    var columns: [Column]

    init(
        people: [Person],
        chores: [Chore],
        completions: [ChoreCompletion],
        rewards: [Reward],
        today: DayKey,
        calendar: Calendar
    ) {
        let week = HomeWeek(containing: today, calendar: calendar)
        let byChoreToday = Dictionary(
            completions.filter { $0.dayKey == today }.map { ($0.choreId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sharedChoreIds = Set(chores.filter { $0.ownerId == nil }.compactMap(\.id))
        let weekCompletions = completions.filter { week.contains($0.dayKey) }
        let active = chores.filter { ChoreSchedule.isOnBoard($0, on: today, completions: completions, calendar: calendar) }
        let activeRewards = rewards.filter { !$0.archived }

        func tasks(for ownerId: Int64?) -> [Task] {
            active.filter { $0.ownerId == ownerId }.map { Task(chore: $0, completion: byChoreToday[$0.id ?? -1]) }
        }
        func statuses(for ownerId: Int64?) -> [RewardStatus] {
            activeRewards.filter { $0.ownerId == ownerId }.map {
                RewardStatus(reward: $0, earned: RewardProgress.earned(for: $0, completions: completions))
            }
        }

        var columns = people.compactMap { person -> Column? in
            guard let id = person.id else { return nil }
            return Column(
                owner: .person(id),
                tasks: tasks(for: id),
                weekStars: weekCompletions.filter { $0.personId == id }.map(\.stars).reduce(0, +),
                rewards: statuses(for: id)
            )
        }
        let anyone = Column(
            owner: .everyone,
            tasks: tasks(for: nil),
            weekStars: weekCompletions.filter { sharedChoreIds.contains($0.choreId) }.map(\.stars).reduce(0, +),
            rewards: statuses(for: nil)
        )
        // "Anyone" only earns a column when there is something shared to show.
        if !anyone.tasks.isEmpty || !anyone.rewards.isEmpty {
            columns.append(anyone)
        }
        self.columns = columns
    }
}

/// The household week containing a day, as day keys.
struct HomeWeek: Equatable {
    var days: [DayKey]

    init(containing day: DayKey, calendar: Calendar) {
        days = calendar.weekDays(containing: day.startDate(in: calendar)).map { DayKey($0, calendar: calendar) }
    }

    var first: DayKey { days.first ?? DayKey(rawValue: "") }
    var last: DayKey { days.last ?? DayKey(rawValue: "") }
    func contains(_ day: DayKey) -> Bool { day >= first && day <= last }
}

/// Stars per person for a set of completions.
enum StarTotals {
    static func byPerson(_ completions: [ChoreCompletion], in week: HomeWeek) -> [Int64: Int] {
        completions
            .filter { week.contains($0.dayKey) }
            .reduce(into: [:]) { totals, completion in
                guard let person = completion.personId else { return }
                totals[person, default: 0] += completion.stars
            }
    }
}

enum RewardProgress {
    /// Stars earned toward a reward since it started: by its owner, or by everyone for a shared goal.
    static func earned(for reward: Reward, completions: [ChoreCompletion]) -> Int {
        completions
            .filter { $0.day >= reward.startDay && (reward.ownerId == nil || $0.personId == reward.ownerId) }
            .map(\.stars)
            .reduce(0, +)
    }
}

/// One cell of the week overview grid.
enum WeekMark: Equatable {
    /// Not scheduled that day.
    case none
    /// Scheduled and not done (yet, or missed when in the past).
    case open
    /// Done, by this person (nil if they were removed).
    case done(personId: Int64?)

    static func mark(for chore: Chore, on day: DayKey, completions: [ChoreCompletion], calendar: Calendar) -> WeekMark {
        let mine = completions.filter { $0.choreId == chore.id }
        if let done = mine.first(where: { $0.dayKey == day }) {
            return .done(personId: done.personId)
        }
        // A one-off chore already done another day isn't due anymore.
        if chore.recurrence.isOnce, !mine.isEmpty { return .none }
        return ChoreSchedule.occurs(chore, on: day, calendar: calendar) ? .open : .none
    }
}

// MARK: - Groceries

enum GrocerySections {
    /// Standard aisles in store-walk order. Custom sections sort after these, then "Other".
    static let standard = ["Produce", "Bakery", "Dairy", "Meat & fish", "Frozen", "Pantry", "Drinks", "Household"]
    static let other = "Other"

    /// Multi-word phrases win over single words ("peanut butter" is not dairy).
    private static let phrases: [(String, String)] = [
        ("peanut butter", "Pantry"), ("almond butter", "Pantry"), ("coconut milk", "Pantry"),
        ("ice cream", "Frozen"), ("frozen peas", "Frozen"), ("paper towel", "Household"),
        ("toilet paper", "Household"), ("dish soap", "Household"), ("olive oil", "Pantry"),
        ("sour cream", "Dairy"), ("cream cheese", "Dairy"), ("sparkling water", "Drinks"),
        ("oat milk", "Dairy"), ("almond milk", "Dairy"), ("soy milk", "Dairy"), ("tomato paste", "Pantry"),
        ("black pepper", "Pantry"), ("chicken stock", "Pantry"), ("chicken broth", "Pantry"),
    ]

    private static let words: [String: String] = {
        var table: [String: String] = [:]
        func add(_ section: String, _ list: String) {
            for word in list.split(separator: " ") { table[String(word)] = section }
        }
        add("Produce", """
            apple avocado banana basil berry blueberry strawberry raspberry broccoli cabbage carrot celery cilantro \
            cucumber garlic ginger grape herb kale leek lemon lettuce lime mango mint mushroom onion orange parsley \
            pear pepper potato scallion shallot spinach squash tomato zucchini fruit vegetable veggie salad arugula \
            peach plum cherry melon watermelon pineapple corn asparagus beet chard fennel jalapeno radish thyme rosemary
            """)
        add("Bakery", "bread bagel baguette bun roll croissant tortilla pita muffin sourdough brioche")
        add("Dairy", "milk cheese butter yogurt yoghurt cream egg parmesan mozzarella cheddar feta ricotta kefir ghee")
        add("Meat & fish", """
            chicken beef pork bacon sausage turkey ham lamb steak mince fish salmon tuna shrimp prawn cod tofu tempeh
            """)
        add("Frozen", "frozen pizza dumpling")
        add("Pantry", """
            rice pasta noodle flour sugar salt oil vinegar miso soy sauce bean lentil chickpea oat oats cereal granola \
            honey jam spice cumin paprika cinnamon stock broth nut almond walnut peanut cracker chip \
            cookie chocolate coffee tea vanilla yeast syrup mustard ketchup mayo tahini quinoa couscous
            """)
        add("Drinks", "juice soda water beer wine seltzer kombucha lemonade")
        add("Household", """
            candle soap detergent sponge bag foil wrap battery bulb towel tissue napkin shampoo toothpaste \
            cleaner trash bleach
            """)
        return table
    }()

    /// A best guess at the aisle for a new grocery item.
    static func guess(_ title: String) -> String {
        let text = title.lowercased()
        if let match = phrases.first(where: { text.contains($0.0) }) {
            return match.1
        }
        let tokens = text.split { !$0.isLetter && $0 != "-" }.map(String.init)
        for token in tokens {
            for candidate in [token, singular(token)] {
                if let section = words[candidate] { return section }
            }
        }
        return other
    }

    private static func singular(_ word: String) -> String {
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") || word.hasSuffix("shes") || word.hasSuffix("ches") { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    /// Where to break sections into two columns so the taller one is as short as possible.
    /// Each section costs its items plus about two rows for its label.
    static func columnSplit(_ counts: [Int]) -> Int {
        guard counts.count > 1 else { return counts.count }
        let costs = counts.map { $0 + 2 }
        let total = costs.reduce(0, +)
        var best = 1
        var bestHeight = Int.max
        var left = 0
        for index in 1..<costs.count {
            left += costs[index - 1]
            let height = max(left, total - left)
            if height < bestHeight {
                bestHeight = height
                best = index
            }
        }
        return best
    }

    /// Sections in display order: standard aisles, then custom ones alphabetically, then "Other".
    static func ordered(_ sections: some Sequence<String>) -> [String] {
        let unique = Set(sections)
        let custom = unique.subtracting(standard).subtracting([other]).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return standard.filter(unique.contains) + custom + (unique.contains(other) ? [other] : [])
    }
}

// MARK: - Meals

enum MealEmoji {
    private static let table: [(keys: [String], emoji: String)] = [
        (["taco"], "🌮"), (["burrito", "wrap"], "🌯"), (["sushi"], "🍣"),
        (["ramen", "noodle", "pho", "udon", "dan dan", "lo mein", "pad thai"], "🍜"),
        (["pasta", "spaghetti", "pesto", "lasagna", "carbonara", "mac"], "🍝"),
        (["pizza"], "🍕"), (["burger"], "🍔"), (["curry", "dal", "dahl"], "🍛"),
        (["salmon", "fish", "cod", "tuna"], "🐟"), (["shrimp", "prawn"], "🍤"),
        (["soup", "stew", "miso", "chili", "hot pot"], "🍲"), (["salad", "bowl"], "🥗"),
        (["steak", "beef"], "🥩"), (["chicken", "wings"], "🍗"), (["bbq", "barbecue", "grill", "ribs"], "🍖"),
        (["pancake", "brunch", "waffle"], "🥞"), (["egg", "omelet", "frittata", "shakshuka"], "🍳"),
        (["dumpling", "gyoza", "bao"], "🥟"), (["sandwich", "panini", "sub"], "🥪"),
        (["fried rice", "rice", "risotto", "paella"], "🍚"), (["cake", "birthday"], "🎂"),
        (["pie", "quiche"], "🥧"), (["takeout", "take-out", "leftover"], "🥡"),
        (["out", "restaurant", "date night"], "🍽️"), (["tofu", "vegan", "veggie"], "🥦"),
    ]

    /// Emoji offered in the meal editor after the guessed one.
    static let palette = ["🍝", "🌮", "🍜", "🍣", "🍕", "🍲", "🥗", "🍛", "🐟", "🍗", "🥩", "🍔", "🥞", "🍳", "🥟", "🥡", "🎂", "🍽️"]

    /// A fitting emoji for a dinner title, or nil when nothing matches.
    static func guess(_ title: String) -> String? {
        let text = " " + title.lowercased().replacingOccurrences(of: "'", with: "") + " "
        return table.first { entry in
            entry.keys.contains { key in
                // Match whole words or word prefixes ("tacos", "noodles").
                text.range(of: "(?<![a-z])\(NSRegularExpression.escapedPattern(for: key))", options: .regularExpression) != nil
            }
        }?.emoji
    }
}

// MARK: - Night

/// The hours Ambient mode dims to a night clock. Minutes from midnight; may cross midnight.
struct NightWindow: Equatable, Sendable {
    var start: Int
    var end: Int

    static let `default` = NightWindow(start: 22 * 60, end: 6 * 60 + 30)

    func contains(minuteOfDay minute: Int) -> Bool {
        if start == end { return false }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return contains(minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}

/// Device preferences for Ambient mode (UserDefaults keys, like `DisplaySettings`).
enum AmbientSettings {
    static let nightEnabledKey = "ambient.nightEnabled"
    static let nightStartKey = "ambient.nightStart"
    static let nightEndKey = "ambient.nightEnd"
    /// Seconds each photo stays up.
    static let slideSeconds: Double = 20
}

// MARK: - Text

enum HomeText {
    /// Keeps the first character of an emoji field (a whole grapheme, so flags and families survive).
    static func emoji(_ raw: String?) -> String? {
        guard let first = raw?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first)
    }
}

extension DayKey {
    /// Formats this day in the calendar's own time zone and locale (not the device's).
    func formatted(_ style: Date.FormatStyle, calendar: Calendar) -> String {
        var style = style
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = calendar.locale ?? .current
        return startDate(in: calendar).formatted(style)
    }
}
