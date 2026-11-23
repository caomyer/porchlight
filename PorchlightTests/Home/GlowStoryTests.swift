import Foundation
import Testing
@testable import Porchlight

/// Glow's story, below the screens: what the stars were for, the words for a trend, an
/// earlier week, "Lately" by day, what was cashed in, a reward's pace, and which cash-in a
/// shared screen still owes a celebration.
@Suite("Glow's story")
struct GlowStoryTests {
    private var calendar: Calendar { HomeLogicTests.calendar }
    private let james: Person.ID = 1
    private let mia: Person.ID = 2

    private func day(_ raw: String) -> DayKey { DayKey(rawValue: raw) }

    private var people: [Person] {
        [
            Person(id: james, householdId: 1, name: "James", color: .blue, sortOrder: 0, createdAt: .distantPast),
            Person(id: mia, householdId: 1, name: "Mia", color: .coral, sortOrder: 1, createdAt: .distantPast),
        ]
    }

    /// 2026-11-01 is a Sunday, the first day of the household's week here.
    private func at(_ raw: String, hour: Int = 9) -> Date {
        day(raw).startDate(in: calendar).addingTimeInterval(Double(hour) * 3600)
    }

    private func walk(_ log: CareLog.ID, _ raw: String, by person: Person.ID, hour: Int = 9) -> StarEarning {
        StarEarning(
            source: .care(routineId: 10, logId: log), personId: person, stars: 2, day: day(raw),
            at: at(raw, hour: hour), recordedAt: at(raw, hour: hour), title: "Walk Yo-Yo", emoji: "🦮"
        )
    }

    private func chore(_ id: Chore.ID, _ title: String, _ raw: String, by person: Person.ID, stars: Int = 1, hour: Int = 12) -> StarEarning {
        StarEarning(
            source: .chore(choreId: id, completionId: ChoreCompletion.id(choreId: id, day: day(raw))), personId: person, stars: stars,
            day: day(raw), at: at(raw, hour: hour), recordedAt: at(raw, hour: hour), title: title, emoji: "🧺"
        )
    }

    private func reward(_ id: Reward.ID = 7, target: Int, owner: Person.ID? = nil, start: String = "2026-10-01") -> Reward {
        Reward(id: id, householdId: 1, title: "Movie night", emoji: "🍿", targetStars: target, ownerId: owner, startDay: start, archived: false, sortOrder: 0, createdAt: .distantPast)
    }

    // MARK: What the stars were for

    @Test("The week's stars by task: each thing done once, with who did it and how often, most stars first")
    func tasks() {
        let week = HomeWeek(containing: day("2026-11-04"), calendar: calendar)
        let earnings = [
            walk(1, "2026-11-02", by: mia), walk(2, "2026-11-03", by: mia),
            // One walk taken together: one time, two stars, both named.
            walk(3, "2026-11-04", by: james), walk(3, "2026-11-04", by: mia),
            chore(5, "Laundry", "2026-11-03", by: james),
            chore(6, "Trash", "2026-11-02", by: james), chore(6, "Trash", "2026-11-03", by: james),
            // Last week's walk is not this week's story.
            walk(9, "2026-10-28", by: james),
        ]
        let tasks = GlowStory.tasks(earnings, in: week, people: people)
        #expect(tasks.map(\.title) == ["Walk Yo-Yo", "Trash", "Laundry"])
        #expect(tasks[0].times == 3 && tasks[0].stars == 6)
        #expect(tasks[0].helpers == [.init(personId: james, times: 1), .init(personId: mia, times: 3)])
        #expect(tasks[1].times == 2 && tasks[1].stars == 2)
        let names: (Person.ID) -> String = { $0 == self.james ? "you" : "Mia" }
        #expect(GlowWords.taskDetail(tasks[0], name: names) == "3 times · you 1, Mia 3")
        #expect(GlowWords.taskDetail(tasks[1], name: names) == "twice · you")
        #expect(GlowWords.taskDetail(tasks[2], name: names) == "once · you")
    }

    @Test("One person's tasks are only theirs, with their own credit for a walk taken together")
    func tasksOfOnePerson() {
        let week = HomeWeek(containing: day("2026-11-04"), calendar: calendar)
        let earnings = [
            walk(1, "2026-11-02", by: mia), walk(3, "2026-11-04", by: james), walk(3, "2026-11-04", by: mia),
            chore(5, "Laundry", "2026-11-03", by: james),
        ]
        let mine = GlowStory.tasks(earnings, in: week, people: people, person: mia)
        #expect(mine.map(\.title) == ["Walk Yo-Yo"])
        #expect(mine[0].times == 2 && mine[0].stars == 4 && mine[0].helpers.isEmpty)
        #expect(GlowWords.taskDetail(mine[0]) { _ in "" } == "twice")
        #expect(GlowWords.taskLine(GlowStory.tasks(earnings, in: week, people: people, person: james)) == "🦮 Walk Yo-Yo · 🧺 Laundry")
        #expect(GlowWords.taskLine(mine) == "🦮 Walk Yo-Yo ×2")
    }

    // MARK: Words

    @Test("A trend is told against the same stretch of last week, and a slower week is only told the number it follows")
    func trendWords() {
        #expect(GlowWords.trend(stars: 14, before: 11, isThisWeek: true) == "3 more than this time last week")
        #expect(GlowWords.trend(stars: 11, before: 11, isThisWeek: true) == "Right on pace with last week")
        #expect(GlowWords.trend(stars: 4, before: 11, isThisWeek: true) == "This time last week: 11")
        #expect(GlowWords.trend(stars: 4, before: 0, isThisWeek: true) == "A bright start")
        #expect(GlowWords.trend(stars: 0, before: 0, isThisWeek: true) == nil)
        #expect(GlowWords.trend(stars: 17, before: 12, isThisWeek: false) == "5 more than the week before")
        #expect(GlowWords.trend(stars: 12, before: 12, isThisWeek: false) == "The same as the week before")
        #expect(GlowWords.trend(stars: 9, before: 12, isThisWeek: false) == "The week before: 12")
    }

    @Test("A person's row says what they did and how it sits beside their own last week, never beside anyone else")
    func personWords() {
        func glow(week: Int, before: Int, chores: Int, care: Int) -> GlowSummary.PersonGlow {
            GlowSummary.PersonGlow(
                person: people[0], weekStars: week, lastWeekStars: before, lastWeekSoFar: before, byDay: [],
                choresDone: chores, careGiven: care, lifetimeStars: 0, favorite: nil
            )
        }
        #expect(GlowWords.personLine(glow(week: 6, before: 6, chores: 2, care: 2), isThisWeek: true) == "🐾 2 times caring · 🧹 2 chores · Same as last week")
        #expect(GlowWords.personLine(glow(week: 8, before: 5, chores: 0, care: 4), isThisWeek: true) == "🐾 4 times caring · Up 3 on last week")
        #expect(GlowWords.personLine(glow(week: 1, before: 5, chores: 1, care: 0), isThisWeek: true) == "🧹 1 chore · This time last week: 5")
        #expect(GlowWords.personLine(glow(week: 0, before: 0, chores: 0, care: 0), isThisWeek: true) == "Nothing yet this week")
        #expect(GlowWords.personLine(glow(week: 0, before: 0, chores: 0, care: 0), isThisWeek: false) == "Nothing that week")
        #expect(GlowWords.personLine(glow(week: 2, before: 4, chores: 0, care: 1), isThisWeek: false) == "🐾 1 time caring · The week before: 4")
        #expect(GlowWords.personLine(glow(week: 6, before: 6, chores: 2, care: 2), isThisWeek: true, emoji: false) == "2 times caring · 2 chores · Same as last week")
        #expect(GlowWords.didLine(glow(week: 6, before: 6, chores: 2, care: 2), isThisWeek: true, emoji: false) == "2 times caring · 2 chores")
        for line in [GlowWords.personLine(glow(week: 8, before: 5, chores: 0, care: 4), isThisWeek: true), GlowWords.trend(stars: 4, before: 11, isThisWeek: true) ?? ""] {
            for word in ["most", "best", "winner", "leader", "behind", "ahead", "beat"] {
                #expect(!line.localizedCaseInsensitiveContains(word), "no ranking word in: \(line)")
            }
        }
    }

    @Test("The total says the household's stars and my share, in the star words")
    func totalWords() {
        #expect(GlowWords.total(stars: 14, mine: 6, isThisWeek: true) == "stars this week · 6 from you")
        #expect(GlowWords.total(stars: 1, mine: 1, isThisWeek: true) == "star this week · 1 from you")
        #expect(GlowWords.total(stars: 0, mine: 0, isThisWeek: true) == "stars this week")
        #expect(GlowWords.total(stars: 17, mine: nil, isThisWeek: false) == "stars that week")
    }

    // MARK: Earlier weeks

    @Test("Weeks are the household's own, counted back to the week of the first star and no further")
    func weeks() {
        let today = day("2026-11-18") // a Wednesday
        #expect(GlowWeeks.week(weeksBack: 0, today: today, calendar: calendar).first == day("2026-11-15"))
        let earlier = GlowWeeks.week(weeksBack: 2, today: today, calendar: calendar)
        #expect(earlier.first == day("2026-11-01") && earlier.last == day("2026-11-07"))
        #expect(GlowWeeks.limit(firstDay: nil, today: today, calendar: calendar) == 0)
        #expect(GlowWeeks.limit(firstDay: day("2026-11-16"), today: today, calendar: calendar) == 0)
        #expect(GlowWeeks.limit(firstDay: day("2026-11-14"), today: today, calendar: calendar) == 1)
        // Across the end of daylight saving time (Nov 1), still whole weeks.
        #expect(GlowWeeks.limit(firstDay: day("2026-10-20"), today: today, calendar: calendar) == 4)
        #expect(GlowWeeks.readThrough(earlier, today: today) == day("2026-11-07"))
        #expect(GlowWeeks.readThrough(GlowWeeks.week(weeksBack: 0, today: today, calendar: calendar), today: today) == today)
        #expect(GlowWeeks.loadFrom(earlier, calendar: calendar) == day("2026-10-25"))
    }

    @Test("An earlier week is read whole: its own stars, the whole week before for its trend, and only its own happenings")
    func earlierWeek() {
        let today = day("2026-11-18")
        let week = GlowWeeks.week(weeksBack: 1, today: today, calendar: calendar) // Nov 8 to 14
        let earnings = [
            walk(1, "2026-11-02", by: mia), walk(2, "2026-11-06", by: mia), walk(3, "2026-11-07", by: james),
            walk(4, "2026-11-09", by: mia), walk(5, "2026-11-13", by: james),
            walk(6, "2026-11-16", by: james),
        ]
        let cashIn = RewardRedemption(id: 1, rewardId: 7, personId: nil, stars: 15, day: "2026-11-09", redeemedAt: at("2026-11-09", hour: 18))
        let later = RewardRedemption(id: 2, rewardId: 7, personId: nil, stars: 15, day: "2026-11-17", redeemedAt: at("2026-11-17", hour: 18))
        let summary = GlowSummary(
            people: people, earnings: earnings, redemptions: [later, cashIn], rewards: [reward(target: 15)], lifetime: [:],
            week: week, today: GlowWeeks.readThrough(week, today: today), calendar: calendar, feedWithinWeek: true
        )
        #expect(summary.weekStars == 4)
        // The whole week before, Saturday's walk included: an earlier week is not cut at a weekday.
        #expect(summary.lastWeekSoFar == 6)
        #expect(summary.people[1].lastWeekSoFar == 4)
        #expect(summary.feed.map(\.day) == [day("2026-11-13"), day("2026-11-09"), day("2026-11-09")])
        #expect(summary.feed.filter(\.isCashIn).count == 1)
        #expect(GlowStory.cashedIn([later, cashIn], rewards: [reward(target: 15)], in: week).map(\.day) == [day("2026-11-09")])
        #expect(GlowStory.tasks(earnings, in: week, people: people).first?.times == 2)
    }

    // MARK: Lately, and what was cashed in

    @Test("Lately is told by day, newest first, in the words for a day")
    func lately() {
        let today = day("2026-11-18")
        let summary = GlowSummary(
            people: people,
            earnings: [walk(1, "2026-11-18", by: james, hour: 7), walk(2, "2026-11-17", by: mia, hour: 8), walk(3, "2026-11-17", by: james, hour: 18), walk(4, "2026-11-14", by: mia), walk(5, "2026-11-05", by: mia)],
            redemptions: [], rewards: [], lifetime: [:], week: HomeWeek(containing: today, calendar: calendar), today: today, calendar: calendar
        )
        let days = GlowStory.lately(summary.feed, today: today, calendar: calendar)
        #expect(days.map(\.title) == ["Today", "Yesterday", "Saturday", "Nov 5"])
        #expect(days[1].items.map(\.personId) == [james, mia])
    }

    @Test("Rewards cashed in stay as a history, newest first, with a reward that is gone still named")
    func cashedIn() {
        let first = RewardRedemption(id: 1, rewardId: 7, personId: nil, stars: 15, day: "2026-11-09", redeemedAt: at("2026-11-09"))
        let second = RewardRedemption(id: 2, rewardId: 99, personId: james, stars: 20, day: "2026-11-12", redeemedAt: at("2026-11-12"))
        let history = GlowStory.cashedIn([first, second], rewards: [reward(target: 15)])
        #expect(history.map(\.title) == ["A reward", "Movie night"])
        #expect(history[1].emoji == "🍿" && history[1].personId == nil && history[1].stars == 15)
        #expect(GlowWords.cashedInDetail(history[1], who: "everyone", today: day("2026-11-18"), calendar: calendar) == "Nov 9 · everyone · 15 stars")
    }

    // MARK: Pace

    @Test("A reward's pace is the last two weeks' average, and silent when there is too little to go on")
    func pace() {
        let today = day("2026-11-18")
        // 14 stars over the 14 days ending today, on seven different days: a star a day.
        let steady = (0..<7).map { walk(CareLog.ID.number($0 + 1), today.adding(days: -2 * $0, calendar: calendar).rawValue, by: mia) }
        let shared = reward(target: 20)
        #expect(RewardPace.daysAway(shared, earned: 14, earnings: steady, today: today, calendar: calendar) == 6)
        #expect(RewardPace.words(6) == "about 6 days away at this pace")
        #expect(RewardPace.words(1) == "about a day away at this pace")
        #expect(RewardPace.words(21) == "about 3 weeks away at this pace")
        // Reached: nothing to wait for.
        #expect(RewardPace.daysAway(shared, earned: 20, earnings: steady, today: today, calendar: calendar) == nil)
        // Two days with a star are not a pace.
        #expect(RewardPace.daysAway(shared, earned: 4, earnings: Array(steady.prefix(2)), today: today, calendar: calendar) == nil)
        // Stars from before the two weeks say nothing about now.
        let old = (0..<7).map { walk(CareLog.ID.number($0 + 1), day("2026-10-20").adding(days: -$0, calendar: calendar).rawValue, by: mia) }
        #expect(RewardPace.daysAway(shared, earned: 14, earnings: old, today: today, calendar: calendar) == nil)
        // A treat goes at its owner's pace alone: Mia's walks do not bring James's treat closer.
        #expect(RewardPace.daysAway(reward(target: 20, owner: james), earned: 0, earnings: steady, today: today, calendar: calendar) == nil)
        #expect(RewardPace.daysAway(reward(target: 20, owner: mia), earned: 14, earnings: steady, today: today, calendar: calendar) == 6)
        // Too far to be worth saying.
        #expect(RewardPace.daysAway(reward(target: 500), earned: 0, earnings: steady, today: today, calendar: calendar) == nil)
    }

    @Test("The reward ideas are ordinary shared rewards the database accepts")
    func ideas() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        #expect(RewardIdeas.all.count == 3)
        for idea in RewardIdeas.all {
            let saved = try db.saveReward(idea, householdId: household.id, today: day("2026-11-18"))
            #expect(saved.ownerId == nil && saved.targetStars == idea.targetStars && saved.emoji == idea.emoji)
        }
    }

    // MARK: A cash-in made elsewhere

    @Test("A shared screen celebrates a cash-in made on another device once, while it is news")
    func cashInNews() {
        let now = at("2026-11-18", hour: 20)
        func cashIn(_ id: RewardRedemption.ID, hoursAgo: Double, device: Device.ID?) -> RewardRedemption {
            RewardRedemption(id: id, rewardId: 7, personId: nil, stars: 15, day: "2026-11-18", redeemedAt: now.addingTimeInterval(-hoursAgo * 3600), deviceId: device)
        }
        let phone: Device.ID = 2
        let wall: Device.ID = 1
        let onPhone = cashIn(1, hoursAgo: 2, device: phone)
        let through = now.addingTimeInterval(-24 * 3600)
        #expect(CashInNews.toCelebrate([onPhone], through: through, thisDevice: wall, now: now)?.id == onPhone.id)
        // Never looked before: nothing is owed for what was already there.
        #expect(CashInNews.toCelebrate([onPhone], through: nil, thisDevice: wall, now: now) == nil)
        // Already celebrated, or made here: not again.
        #expect(CashInNews.toCelebrate([onPhone], through: CashInNews.newest([onPhone]), thisDevice: wall, now: now) == nil)
        #expect(CashInNews.toCelebrate([cashIn(3, hoursAgo: 1, device: wall)], through: through, thisDevice: wall, now: now) == nil)
        // Two since the last look: the newest one.
        #expect(CashInNews.toCelebrate([onPhone, cashIn(4, hoursAgo: 1, device: phone)], through: through, thisDevice: wall, now: now)?.id == 4)
        // Last month's is history.
        #expect(CashInNews.toCelebrate([cashIn(5, hoursAgo: 24 * 20, device: phone)], through: .distantPast, thisDevice: wall, now: now) == nil)
    }
}
