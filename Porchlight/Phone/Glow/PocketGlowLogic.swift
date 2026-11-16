import Foundation

/// Glow from one person's side, worked out from the wall's star ledger (`GlowSummary`,
/// `RewardProgress`). Pure, covered by PocketGlowTests.
enum PocketGlowLogic {
    /// My numbers: stars this week and all time.
    struct Mine: Equatable {
        var weekStars: Int
        var lifetimeStars: Int
    }

    static func mine(_ summary: GlowSummary, me: Person.ID) -> Mine {
        let glow = summary.people.first { $0.id == me }
        return Mine(weekStars: glow?.weekStars ?? 0, lifetimeStars: glow?.lifetimeStars ?? 0)
    }

    /// What I'm saving toward: the household's shared goals first, then my own treats,
    /// each with what it has earned in its current round.
    static func rewards(_ rewards: [Reward], me: Person.ID, earned: (Reward) -> Int) -> [ChoreBoard.RewardStatus] {
        rewards
            .filter { !$0.archived && ($0.ownerId == nil || $0.ownerId == me) }
            .sorted { ($0.ownerId == nil ? 0 : 1, $0.sortOrder) < ($1.ownerId == nil ? 0 : 1, $1.sortOrder) }
            .map { ChoreBoard.RewardStatus(reward: $0, earned: earned($0)) }
    }

    /// Who earned a reward's current round, most stars first (ties in household order):
    /// everyone who pitched in for a shared goal, the owner for a treat.
    static func earners(of reward: Reward, earnings: [StarEarning], redemptions: [RewardRedemption], people: [Person]) -> [Person] {
        let start = DayKey(rawValue: reward.startDay)
        let cutoff = redemptions
            .filter { $0.rewardId == reward.id && $0.dayKey == start }
            .map(\.redeemedAt)
            .max() ?? .distantPast
        let round = earnings.filter { $0.day > start || ($0.day == start && $0.recordedAt >= cutoff) }
        var stars: [Person.ID: Int] = [:]
        for earning in round {
            guard let person = earning.personId, reward.ownerId == nil || reward.ownerId == person else { continue }
            stars[person, default: 0] += earning.stars
        }
        let order = Dictionary(uniqueKeysWithValues: people.enumerated().map { ($0.element.id, $0.offset) })
        return people
            .filter { (stars[$0.id] ?? 0) > 0 }
            .sorted { (-(stars[$0.id] ?? 0), order[$0.id] ?? 0) < (-(stars[$1.id] ?? 0), order[$1.id] ?? 0) }
    }

    /// What cashing in a reward spends, in words a reader who just saw "20 of 20" follows:
    /// the reward's price, who earned it, and, when the round earned more than the price,
    /// that the extra goes too. Cashing in spends the whole round (`cashInReward` records
    /// every star earned since the last cash-in) and starts the count again from zero.
    static func cashInMessage(_ status: ChoreBoard.RewardStatus, earners: [Person], me: Person.ID?) -> String {
        let price = status.reward.targetStars
        let who = names(earners, me: me)
        let extra = status.earned - price
        let spent = extra > 0
            ? "It costs \(StarWords.count(price)), and \(who) earned \(status.earned), so the \(extra) extra \(StarWords.noun(extra)) \(extra == 1 ? "goes" : "go") with it."
            : "\(StarWords.count(price)) from \(who)."
        return spent + " Then it starts again from zero."
    }

    /// "James, Mia and Ava", with me as "you".
    static func names(_ people: [Person], me: Person.ID?) -> String {
        let names = people.map { $0.id == me ? "you" : $0.name }
        guard !names.isEmpty else { return "everyone" }
        return ListFormatter.localizedString(byJoining: names)
    }
}
