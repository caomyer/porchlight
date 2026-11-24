import Foundation

// The week's story on Glow, worked out once for the phone and the wall: which week,
// what the stars were for, what just happened, what was cashed in, how far a reward is.
// Pure, covered by GlowStoryTests.

// MARK: - Weeks

/// Glow's weeks are the household's own (`HomeWeek`), counted back from the one holding today.
enum GlowWeeks {
    static func week(weeksBack: Int, today: DayKey, calendar: Calendar) -> HomeWeek {
        HomeWeek(containing: today.adding(days: -7 * max(weeksBack, 0), calendar: calendar), calendar: calendar)
    }

    /// How far back it goes: to the week of the first star anyone earned, and no further.
    static func limit(firstDay: DayKey?, today: DayKey, calendar: Calendar) -> Int {
        guard let firstDay, firstDay < today else { return 0 }
        let first = HomeWeek(containing: firstDay, calendar: calendar).first.startDate(in: calendar)
        let this = HomeWeek(containing: today, calendar: calendar).first.startDate(in: calendar)
        let days = calendar.dateComponents([.day], from: first, to: this).day ?? 0
        return max(0, (days + 3) / 7)
    }

    /// The day a week is read up to: today in this week, its last day in an earlier one,
    /// so an earlier week is compared whole with the week before it.
    static func readThrough(_ week: HomeWeek, today: DayKey) -> DayKey {
        min(today, week.last)
    }

    /// The earliest day a week's page reads: the week before it, for the trend.
    static func loadFrom(_ week: HomeWeek, calendar: Calendar) -> DayKey {
        week.first.adding(days: -7, calendar: calendar)
    }
}

// MARK: - What the stars were for

/// One thing done during a week, however often: "Walk Yo-Yo, 6 times, +12".
struct GlowTask: Equatable, Identifiable {
    struct Helper: Equatable {
        var personId: Person.ID
        var times: Int
    }

    var id: String
    var emoji: String
    var title: String
    /// How often it was done. Care done together is one time.
    var times: Int
    /// The stars it earned: each time once for the household, a person's own credit for theirs.
    var stars: Int
    /// Who did it and how often, in household order. Empty for one person's own list.
    var helpers: [Helper]
}

enum GlowStory {
    /// A week's stars by task, most stars first. For the household each thing done counts
    /// once, with everyone who helped named; for `person` only what they did.
    static func tasks(_ earnings: [StarEarning], in week: HomeWeek, people: [Person], person: Person.ID? = nil) -> [GlowTask] {
        let inWeek = earnings.filter { week.contains($0.day) && (person == nil || $0.personId == person) }
        let order = Dictionary(people.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(grouping: inWeek, by: key).map { id, group -> GlowTask in
            let deeds = person == nil ? group.counted : group
            var times: [Person.ID: Int] = [:]
            for earning in group {
                if let who = earning.personId { times[who, default: 0] += 1 }
            }
            let helpers = person == nil
                ? times.sorted { (order[$0.key] ?? .max, $0.key) < (order[$1.key] ?? .max, $1.key) }.map { GlowTask.Helper(personId: $0.key, times: $0.value) }
                : []
            let latest = group.max { ($0.at, $0.id) < ($1.at, $1.id) }
            return GlowTask(
                id: id, emoji: latest?.emoji ?? "⭐", title: latest?.title ?? "",
                times: deeds.count, stars: deeds.map(\.stars).reduce(0, +), helpers: helpers
            )
        }
        .sorted { (-$0.stars, $0.title, $0.id) < (-$1.stars, $1.title, $1.id) }
    }

    /// What was done, whoever did it and whichever day: a chore, or a companion's routine.
    private static func key(_ earning: StarEarning) -> String {
        switch earning.source {
        case let .chore(choreId, _): "chore-\(choreId)"
        case let .care(routineId, _): "care-\(routineId)"
        }
    }

    // MARK: Lately

    /// One day of "Lately", newest day first.
    struct LatelyDay: Equatable, Identifiable {
        var day: DayKey
        var title: String
        var items: [GlowSummary.FeedItem]
        var id: DayKey { day }
    }

    static func lately(_ feed: [GlowSummary.FeedItem], today: DayKey, calendar: Calendar) -> [LatelyDay] {
        var days: [LatelyDay] = []
        for item in feed {
            if days.last?.day == item.day {
                days[days.count - 1].items.append(item)
            } else {
                days.append(LatelyDay(day: item.day, title: GlowWords.day(item.day, today: today, calendar: calendar), items: [item]))
            }
        }
        return days
    }

    // MARK: Cashed in

    /// A reward the household already enjoyed.
    struct CashedIn: Equatable, Identifiable {
        var id: RewardRedemption.ID
        var emoji: String
        var title: String
        var day: DayKey
        /// Whose treat it was; nil when everyone's.
        var personId: Person.ID?
        var stars: Int
    }

    /// Rewards cashed in, newest first: all of them, or those of one week.
    static func cashedIn(_ redemptions: [RewardRedemption], rewards: [Reward], in week: HomeWeek? = nil) -> [CashedIn] {
        let byId = Dictionary(rewards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return redemptions
            .filter { redemption in week.map { $0.contains(redemption.dayKey) } ?? true }
            .sorted { ($0.redeemedAt, $0.id.description) > ($1.redeemedAt, $1.id.description) }
            .map { redemption in
                let reward = byId[redemption.rewardId]
                return CashedIn(
                    id: redemption.id, emoji: reward?.emoji ?? "🎉", title: reward?.title ?? "A reward",
                    day: redemption.dayKey, personId: redemption.personId, stars: redemption.stars
                )
            }
    }
}

// MARK: - Pace

/// How far a reward is at the household's recent pace. It says nothing rather than guess.
enum RewardPace {
    /// The days the pace is read from, ending today.
    static let window = 14
    /// Fewer days with a star than this in the window is too little to go on.
    static let enoughDays = 3
    /// Further than this is not worth saying.
    static let furthest = 84

    /// Days until the reward is reached at the last two weeks' average, or nil when it is
    /// reached, when there is too little to go on, or when it is too far to be worth saying.
    static func daysAway(_ reward: Reward, earned: Int, earnings: [StarEarning], today: DayKey, calendar: Calendar) -> Int? {
        let remaining = reward.targetStars - earned
        guard remaining > 0 else { return nil }
        let from = today.adding(days: -(window - 1), calendar: calendar)
        let pool = (reward.ownerId == nil ? earnings.counted : earnings.filter { $0.personId == reward.ownerId })
            .filter { $0.day >= from && $0.day <= today }
        guard Set(pool.map(\.day)).count >= enoughDays else { return nil }
        let stars = pool.map(\.stars).reduce(0, +)
        guard stars > 0 else { return nil }
        let days = Int((Double(remaining) * Double(window) / Double(stars)).rounded(.up))
        return days <= furthest ? max(days, 1) : nil
    }

    /// "about 3 days away at this pace", "about 2 weeks away at this pace".
    static func words(_ days: Int) -> String {
        let span: String
        switch days {
        case ...1: span = "a day"
        case 2...13: span = "\(days) days"
        default:
            let weeks = Int((Double(days) / 7).rounded())
            span = "\(weeks) weeks"
        }
        return "about \(span) away at this pace"
    }
}

// MARK: - Reward ideas

/// Something to save for in one tap, when the household has nothing yet. Each is an
/// ordinary shared reward afterwards: its name, its price and whose it is can be changed.
enum RewardIdeas {
    static let all: [RewardDraft] = [
        RewardDraft(title: "Movie night", emoji: "🍿", targetStars: 20, ownerId: nil),
        RewardDraft(title: "Takeout pick", emoji: "🍜", targetStars: 15, ownerId: nil),
        RewardDraft(title: "Ice cream run", emoji: "🍦", targetStars: 10, ownerId: nil),
    ]
}

// MARK: - A cash-in made elsewhere

/// Which cash-in a shared screen still owes a celebration: one made on another device
/// since this screen last celebrated, while it is still news.
enum CashInNews {
    /// A cash-in older than this is history, not news.
    static let fresh: TimeInterval = 7 * 24 * 3600

    /// The newest cash-in to celebrate, or nil. `through` is the newest this screen has
    /// already marked; nil means it has never looked, so nothing is owed and the caller
    /// marks what is there.
    static func toCelebrate(_ redemptions: [RewardRedemption], through: Date?, thisDevice: Device.ID?, now: Date) -> RewardRedemption? {
        guard let through else { return nil }
        return redemptions
            .filter { $0.redeemedAt > through && $0.redeemedAt <= now && now.timeIntervalSince($0.redeemedAt) <= fresh }
            .filter { $0.deviceId != nil && $0.deviceId != thisDevice }
            .max { ($0.redeemedAt, $0.id.description) < ($1.redeemedAt, $1.id.description) }
    }

    /// The mark to keep once everything there has been seen.
    static func newest(_ redemptions: [RewardRedemption]) -> Date {
        redemptions.map(\.redeemedAt).max() ?? .distantPast
    }
}

// MARK: - Words

/// Glow's sentences, the same on the phone and the wall. Star counts go through `StarWords`.
enum GlowWords {
    /// A week's stars against the same stretch of the week before. Never a ranking, and a
    /// slower week is only told the number it follows.
    static func trend(stars: Int, before: Int, isThisWeek: Bool) -> String? {
        guard stars > 0 || before > 0 else { return nil }
        let change = stars - before
        if isThisWeek {
            if before == 0 { return "A bright start" }
            if change > 0 { return "\(change) more than this time last week" }
            if change == 0 { return "Right on pace with last week" }
            return "This time last week: \(before)"
        }
        if before == 0 { return "A bright start" }
        if change > 0 { return "\(change) more than the week before" }
        if change == 0 { return "The same as the week before" }
        return "The week before: \(before)"
    }

    /// One person against their own week before, short enough for a row: "Up 3 on last
    /// week". A slower week is only told the number it follows.
    static func ownTrend(stars: Int, before: Int, isThisWeek: Bool) -> String? {
        guard before > 0 else { return nil }
        let other = isThisWeek ? "last week" : "the week before"
        let change = stars - before
        if change > 0 { return "Up \(change) on \(other)" }
        if change == 0 { return "Same as \(other)" }
        return isThisWeek ? "This time last week: \(before)" : "The week before: \(before)"
    }

    /// "4 times caring", "2 chores": what one person did, by kind. The wall's light cards
    /// lead each with its emoji; the phone, dark half the time, leaves the dark paw print out.
    static func did(chores: Int, care: Int, emoji: Bool = true) -> [String] {
        var parts: [String] = []
        if care > 0 { parts.append((emoji ? "🐾 " : "") + "\(care) \(care == 1 ? "time caring" : "times caring")") }
        if chores > 0 { parts.append((emoji ? "🧹 " : "") + "\(chores) \(chores == 1 ? "chore" : "chores")") }
        return parts
    }

    /// What one person did, in one line: "9 times caring · 5 chores", or that there is nothing.
    static func didLine(_ glow: GlowSummary.PersonGlow, isThisWeek: Bool, emoji: Bool = true) -> String {
        let parts = did(chores: glow.choresDone, care: glow.careGiven, emoji: emoji)
        return parts.isEmpty ? (isThisWeek ? "Nothing yet this week" : "Nothing that week") : parts.joined(separator: " · ")
    }

    /// A person's row said whole: what they did, then their own trend.
    static func personLine(_ glow: GlowSummary.PersonGlow, isThisWeek: Bool, emoji: Bool = true) -> String {
        let did = didLine(glow, isThisWeek: isThisWeek, emoji: emoji)
        guard let trend = glow.trend(isThisWeek: isThisWeek) else { return did }
        return "\(did) · \(trend)"
    }

    /// "once", "twice", "6 times".
    static func times(_ count: Int) -> String {
        switch count {
        case 1: "once"
        case 2: "twice"
        default: "\(count) times"
        }
    }

    /// "6 times · Mia 4, you 2", "once · you": how often, and who.
    static func taskDetail(_ task: GlowTask, name: (Person.ID) -> String) -> String {
        guard !task.helpers.isEmpty else { return times(task.times) }
        let who = task.helpers.count == 1
            ? name(task.helpers[0].personId)
            : task.helpers.map { "\(name($0.personId)) \($0.times)" }.joined(separator: ", ")
        return "\(times(task.times)) · \(who)"
    }

    /// "🦮 Walk Yo-Yo ×4 · 🗑️ Take out recycling": a person's tasks on one line, the wall's card.
    static func taskLine(_ tasks: [GlowTask], limit: Int = 3) -> String {
        tasks.prefix(limit).map { "\($0.emoji) \($0.title)" + ($0.times > 1 ? " ×\($0.times)" : "") }.joined(separator: " · ")
    }

    /// A day in "Lately" and "Cashed in": "Today", "Yesterday", "Saturday", then "Nov 9".
    static func day(_ day: DayKey, today: DayKey, calendar: Calendar) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1, calendar: calendar) { return "Yesterday" }
        if day < today, day > today.adding(days: -7, calendar: calendar) {
            return day.formatted(.dateTime.weekday(.wide), calendar: calendar)
        }
        return day.formatted(.dateTime.month(.abbreviated).day(), calendar: calendar)
    }

    /// "Nov 9 · everyone · 15 stars".
    static func cashedInDetail(_ item: GlowStory.CashedIn, who: String, today: DayKey, calendar: Calendar) -> String {
        [day(item.day, today: today, calendar: calendar), who, StarWords.count(item.stars)].joined(separator: " · ")
    }

    /// The hero's small line: "stars this week · 6 from you".
    static func total(stars: Int, mine: Int?, isThisWeek: Bool) -> String {
        let when = isThisWeek ? "this week" : "that week"
        let base = "\(StarWords.noun(stars)) \(when)"
        guard let mine, stars > 0 else { return base }
        return "\(base) · \(mine) from you"
    }
}
