import Foundation

// Pure rules behind the Home screens. No database or UI here, so it is easy to test.

// MARK: - Recurrence

enum ChoreSchedule {
    /// Whether the chore's pattern lands on `day`. One-off chores land on their due day only.
    static func occurs(_ chore: Chore, on day: DayKey, calendar: Calendar) -> Bool {
        chore.recurrence.occurs(on: day, start: chore.anchor, calendar: calendar)
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

    /// "every day", "Mon, Wed", "monthly on the 3rd", or "due Fri" for a one-off.
    /// A repeating chore that hasn't started yet says when it starts.
    static func describe(_ chore: Chore, today: DayKey, calendar: Calendar) -> String {
        if chore.recurrence.isOnce { return Recurrence.describeDue(chore.anchor, today: today, calendar: calendar) }
        let pattern = chore.recurrence.describe(start: chore.anchor, calendar: calendar)
        guard chore.anchor > today else { return pattern }
        return pattern + ", from " + chore.anchor.formatted(.dateTime.month(.abbreviated).day(), calendar: calendar)
    }
}

// MARK: - Board

/// A companion routine's slot today, on the board next to the chores: "Walk Yo-Yo, morning".
struct CareTask: Equatable, Identifiable {
    var companionId: Companion.ID
    var companionName: String
    var routine: CareRoutine
    var slot: CareSlot

    var id: String { "care-\(routine.id)-\(slot.index)" }
    var isDone: Bool { slot.isDone }
    /// "Walk Yo-Yo", or "Walk Yo-Yo · morning" when the routine comes around more than once a day.
    var title: String {
        let base = "\(routine.title) \(companionName)"
        guard routine.slotsPerDay > 1, !slot.window.isAllDay else { return base }
        return base + " · " + slot.window.label.lowercased()
    }
}

/// The chore board for one day: a column per person, plus "Anyone" for shared chores and
/// companion care, which anyone can pitch in on.
struct ChoreBoard: Equatable {
    struct Task: Equatable, Identifiable {
        var chore: Chore
        var completion: ChoreCompletion?
        var id: Chore.ID { chore.id }
        var isDone: Bool { completion != nil }
    }

    struct RewardStatus: Equatable, Identifiable {
        var reward: Reward
        var earned: Int
        var id: Reward.ID { reward.id }
        var fraction: Double { reward.targetStars > 0 ? min(Double(earned) / Double(reward.targetStars), 1) : 0 }
        var isReached: Bool { earned >= reward.targetStars }
    }

    struct Column: Equatable, Identifiable {
        var owner: Owner
        var tasks: [Task]
        /// Companion care due today (the "Anyone" column only).
        var care: [CareTask] = []
        /// Stars earned this week: by this person, or on shared chores and care for "Anyone".
        var weekStars: Int
        var rewards: [RewardStatus]
        var doneCount: Int { tasks.filter(\.isDone).count + care.filter(\.isDone).count }
        var totalCount: Int { tasks.count + care.count }
        var isEmpty: Bool { tasks.isEmpty && care.isEmpty }
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
        earnings: [StarEarning],
        redemptions: [RewardRedemption] = [],
        care: [CareTask] = [],
        rewards: [Reward],
        today: DayKey,
        calendar: Calendar
    ) {
        let week = HomeWeek(containing: today, calendar: calendar)
        let byChoreToday = Dictionary(
            completions.filter { $0.dayKey == today }.map { ($0.choreId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sharedChoreIds = Set(chores.filter { $0.ownerId == nil }.map(\.id))
        let weekEarnings = earnings.filter { week.contains($0.day) }
        let active = chores.filter { ChoreSchedule.isOnBoard($0, on: today, completions: completions, calendar: calendar) }
        let activeRewards = rewards.filter { !$0.archived }

        func tasks(for ownerId: Person.ID?) -> [Task] {
            active.filter { $0.ownerId == ownerId }.map { Task(chore: $0, completion: byChoreToday[$0.id]) }
        }
        func statuses(for ownerId: Person.ID?) -> [RewardStatus] {
            activeRewards.filter { $0.ownerId == ownerId }.map {
                RewardStatus(reward: $0, earned: RewardProgress.earned(for: $0, earnings: earnings, redemptions: redemptions))
            }
        }

        var columns = people.map { person -> Column in
            let id = person.id
            return Column(
                owner: .person(id),
                tasks: tasks(for: id),
                weekStars: weekEarnings.filter { $0.personId == id }.map(\.stars).reduce(0, +),
                rewards: statuses(for: id)
            )
        }
        let anyone = Column(
            owner: .everyone,
            tasks: tasks(for: nil),
            care: care,
            weekStars: weekEarnings.counted.filter { earning in
                switch earning.source {
                case let .chore(choreId, _): sharedChoreIds.contains(choreId)
                case .care: true
                }
            }.map(\.stars).reduce(0, +),
            rewards: statuses(for: nil)
        )
        // "Anyone" only earns a column when there is something shared to show.
        if !anyone.isEmpty || !anyone.rewards.isEmpty {
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

/// Stars per person, from the ledger.
enum StarTotals {
    static func byPerson(_ earnings: [StarEarning], in week: HomeWeek) -> [Person.ID: Int] {
        earnings
            .filter { week.contains($0.day) }
            .reduce(into: [:]) { totals, earning in
                guard let person = earning.personId else { return }
                totals[person, default: 0] += earning.stars
            }
    }
}

enum RewardProgress {
    /// Stars earned toward a reward since it (re)started: by its owner, or by everyone for a
    /// shared goal. When it was cashed in on its start day, only stars after that count.
    static func earned(for reward: Reward, earnings: [StarEarning], redemptions: [RewardRedemption] = []) -> Int {
        let start = DayKey(rawValue: reward.startDay)
        let cutoff = redemptions
            .filter { $0.rewardId == reward.id && $0.dayKey == start }
            .map(\.redeemedAt)
            .max() ?? .distantPast
        // A shared goal counts each thing done once, however many helped.
        let pool = reward.ownerId == nil ? earnings.counted : earnings.filter { $0.personId == reward.ownerId }
        return pool
            .filter { $0.day > start || ($0.day == start && $0.recordedAt >= cutoff) }
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
    /// Done, by this person (nil only in rows from before people were archived).
    case done(personId: Person.ID?)

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

    /// Grocery items under their sections, in display order; items keep their list order.
    static func group(_ items: [ListItem]) -> [(name: String, items: [ListItem])] {
        let grouped = Dictionary(grouping: items) { $0.section ?? other }
        return ordered(grouped.keys).map { ($0, grouped[$0] ?? []) }
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
    static let showKey = "ambient.show"
    /// Seconds each photo stays up.
    static let slideSeconds: Double = 20
}

/// What the photo frame shows (Settings > Photo frame > Show).
enum FrameShow: String, CaseIterable {
    /// The household's photos (plus meal photos), shuffled, each with a slow drift.
    case photos
    /// A still painted sky that follows the time of day. The low-power choice.
    case porchView
}

/// The porch view's sky for each part of the day. Night is the dim clock, set separately.
enum PorchSky: CaseIterable, Equatable {
    case morning, day, dusk, evening

    /// Morning 5-11, Day 11-4, Dusk 4-7, Evening from 7 until morning.
    static func at(minuteOfDay minute: Int) -> PorchSky {
        switch minute {
        case 5 * 60 ..< 11 * 60: .morning
        case 11 * 60 ..< 16 * 60: .day
        case 16 * 60 ..< 19 * 60: .dusk
        default: .evening
        }
    }

    static func at(_ date: Date, calendar: Calendar) -> PorchSky {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return at(minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}

/// Deals items in a random order, each once before any repeats, like a shuffled deck.
///
/// Items added mid-round join the next round; removed ones are skipped. A new round
/// never opens with the item the last one ended on, so nothing shows twice in a row.
struct ShuffleDeck<Item: Hashable> {
    private var remaining: [Item] = []
    private(set) var last: Item?

    mutating func next(from items: [Item]) -> Item? {
        var generator = SystemRandomNumberGenerator()
        return next(from: items, using: &generator)
    }

    mutating func next(from items: [Item], using generator: inout some RandomNumberGenerator) -> Item? {
        guard !items.isEmpty else { return nil }
        let present = Set(items)
        remaining.removeAll { !present.contains($0) }
        if remaining.isEmpty {
            remaining = items.shuffled(using: &generator)
            // Deals from the end, so the end must not repeat the last item shown.
            if remaining.count > 1, remaining.last == last {
                remaining.swapAt(0, remaining.count - 1)
            }
        }
        let item = remaining.removeLast()
        last = item
        return item
    }
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

// MARK: - Glow

/// Everyone's contribution to the household, as the Glow page shows it: stars this week
/// (and last), what they came from, and what's been happening lately.
struct GlowSummary: Equatable {
    struct PersonGlow: Equatable, Identifiable {
        var person: Person
        var weekStars: Int
        var lastWeekStars: Int
        /// Their stars last week up to the same weekday, for a fair comparison mid-week.
        var lastWeekSoFar: Int
        /// Stars per day of the week, in week order.
        var byDay: [Int]
        /// How many things they did this week, split by kind.
        var choresDone: Int
        var careGiven: Int
        var lifetimeStars: Int
        /// What they did most this week, e.g. ("🦮", "Walk · Yo-Yo", 5).
        var favorite: Favorite?
        var id: Person.ID { person.id }
    }

    struct Favorite: Equatable {
        var emoji: String
        var title: String
        var count: Int
    }

    /// One line in "Lately": stars earned, or a reward cashed in.
    struct FeedItem: Equatable, Identifiable {
        var id: String
        /// The day it counts for (a chore caught up on later still belongs to its day).
        var day: DayKey
        var at: Date
        var emoji: String
        var personId: Person.ID?
        var text: String
        var stars: Int?
        var isCashIn: Bool
    }

    var people: [PersonGlow]
    var weekStars: Int
    var lastWeekStars: Int
    /// Last week's stars up to the same weekday as today, for a fair comparison mid-week.
    var lastWeekSoFar: Int
    /// This week's earnings, oldest first: each one is a spark around the porch light.
    var sparks: [StarEarning]
    var feed: [FeedItem]

    init(
        people: [Person],
        earnings: [StarEarning],
        redemptions: [RewardRedemption],
        rewards: [Reward],
        lifetime: [Person.ID: Int],
        week: HomeWeek,
        today: DayKey,
        calendar: Calendar,
        feedLimit: Int = 12,
        feedWithinWeek: Bool = false
    ) {
        let lastWeek = HomeWeek(containing: week.first.adding(days: -1, calendar: calendar), calendar: calendar)
        let thisWeek = earnings.filter { week.contains($0.day) }
        let previous = earnings.filter { lastWeek.contains($0.day) }
        let sameDayLastWeek = today.adding(days: -7, calendar: calendar)
        self.people = people.map { person in
            let id = person.id
            let mine = thisWeek.filter { $0.personId == id }
            let counts = Dictionary(grouping: mine, by: \.title).mapValues(\.count)
            let favorite = counts.max { ($0.value, $1.key) < ($1.value, $0.key) }.flatMap { title, count -> Favorite? in
                guard count > 1, let emoji = mine.first(where: { $0.title == title })?.emoji else { return nil }
                return Favorite(emoji: emoji, title: title, count: count)
            }
            return PersonGlow(
                person: person,
                weekStars: mine.map(\.stars).reduce(0, +),
                lastWeekStars: previous.filter { $0.personId == id }.map(\.stars).reduce(0, +),
                lastWeekSoFar: previous.filter { $0.personId == id && $0.day <= sameDayLastWeek }.map(\.stars).reduce(0, +),
                byDay: week.days.map { day in mine.filter { $0.day == day }.map(\.stars).reduce(0, +) },
                choresDone: mine.filter { !$0.isCare }.count,
                careGiven: mine.filter(\.isCare).count,
                lifetimeStars: lifetime[id] ?? 0,
                favorite: favorite
            )
        }
        // The porch light counts each thing done once; people's cards credit every helper.
        weekStars = thisWeek.counted.map(\.stars).reduce(0, +)
        lastWeekStars = previous.counted.map(\.stars).reduce(0, +)
        lastWeekSoFar = previous.counted.filter { $0.day <= sameDayLastWeek }.map(\.stars).reduce(0, +)
        sparks = thisWeek.counted

        let titles = Dictionary(rewards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // "Lately" is everything, newest first; an earlier week's page keeps to its week.
        let earned = (feedWithinWeek ? thisWeek : earnings).map { earning in
            FeedItem(
                id: earning.id, day: earning.day, at: earning.at, emoji: earning.emoji, personId: earning.personId,
                text: earning.title, stars: earning.stars, isCashIn: false
            )
        }
        let cashIns = redemptions.filter { !feedWithinWeek || week.contains($0.dayKey) }.map { redemption in
            let reward = titles[redemption.rewardId]
            return FeedItem(
                id: "cash-\(redemption.id)", day: redemption.dayKey, at: redemption.redeemedAt, emoji: reward?.emoji ?? "🎉",
                personId: redemption.personId,
                text: "Cashed in " + (reward?.title ?? "a reward") + (redemption.personId == nil ? " together" : ""),
                stars: nil, isCashIn: true
            )
        }
        feed = Array((earned + cashIns).sorted { ($0.day, $0.at, $0.id) > ($1.day, $1.at, $1.id) }.prefix(feedLimit))
    }
}
