#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// Glow on the phone, the whole page and one person's page, hosted in the unit bundle
/// (`HostedScreen`) with the sample household, in light, dark, at the largest text and both
/// together. What needs a tap through real navigation (opening a person, cashing in, the
/// pager's arrows) stays with `PhoneGlowTests`.
@Suite("Glow on the phone, the whole pages")
@MainActor
struct PocketGlowScreenTests {
    struct House {
        let db: AppDatabase
        let model: AppModel
        let home: HomeStore
        let me: Person
        let other: Person
    }

    /// The sample household, or a bare one with chores and no reward when `samples` is false.
    private func house(samples: Bool = true) throws -> House {
        let db = try AppDatabase.inMemory(installId: "glow")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        let snapshot = try db.snapshot()
        let seeded = try #require(snapshot.household)
        if samples {
            try CompanionSamples.seed(db, household: seeded, people: snapshot.people)
            try HomeSamples.seed(db, household: seeded, people: snapshot.people)
        } else {
            _ = try db.saveChore(ChoreDraft(title: "Laundry", emoji: "🧺", ownerId: nil, recurrence: .daily, anchorDay: DayKey(CompanionClock.now(), calendar: seeded.calendar), timeHint: nil, stars: 1), householdId: seeded.id)
        }
        return House(db: db, model: AppModel(database: db), home: HomeStore(database: db), me: snapshot.people[0], other: snapshot.people[1])
    }

    private func glow(_ house: House, look: HostedScreen.Look, shot: String, weeksBack: Int = 0) async throws -> HostedScreen {
        let hosted = try await HostedScreen.host(
            PocketGlowScreen(weeksBack: weeksBack).environment(house.model).environment(house.home).environment(\.me, house.me), look: look
        )
        try hosted.saveShot("\(shot)-\(look.name)")
        return hosted
    }

    @Test(
        "Glow tells the week: the total with my share, everyone side by side, what the stars were for and what just happened",
        arguments: ["light", "dark", "largest", "largest-dark"]
    )
    func page(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await glow(try house(), look: look, shot: "glow-story")
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        let total = try #require(page.elements.first { $0.label.contains("this week") && $0.label.contains("from you") }, "the week's total and my share:\n\(page.listing)")
        #expect(total.frame.width > 0)
        #expect(page.elements.contains { $0.label == "Stars each day" }, "the week's strip:\n\(page.listing)")
        for name in ["You", "Mia"] {
            let row = try #require(page.elements.first { $0.isButton && $0.label.hasPrefix("\(name), ") }, "\(name) opens to their week:\n\(page.listing)")
            #expect(row.label.contains("this week"), "the row says its stars: \(row.label)")
            #expect(row.frame.height >= 44, "a row is a full touch target: \(row.frame)")
        }
        #expect(page.elements.contains { $0.label.hasPrefix("Where the stars came from") }, "the stars by task:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.contains(" times · ") || $0.label.contains("twice · ") || $0.label.contains("once · ") }, "a task says how often and who:\n\(page.listing)")
        #expect(page.elements.contains { $0.label == "Lately" }, "what just happened:\n\(page.listing)")
        #expect(page.elements.contains { $0.label == "TODAY" || $0.label == "Today" }, "Lately is told by day:\n\(page.listing)")
        #expect(page.elements.contains { $0.isButton && $0.label == "Cash in Fancy coffee run" }, "a reached reward can be cashed in:\n\(page.listing)")
        for word in ["most", "winner", "leader", "behind", "ahead"] {
            #expect(!page.elements.contains { $0.label.localizedCaseInsensitiveContains(word) }, "no ranking word (\(word)):\n\(page.listing)")
        }
    }

    @Test(
        "A person's page is their own week: beside their last week, their days, what they did, their own treat",
        arguments: ["light", "dark", "largest", "largest-dark"]
    )
    func person(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let house = try house()
        let weeksBack = 0
        let page = try await HostedScreen.host(
            // Bare, as every hosted page is: the navigation bar it is pushed under is the
            // journey's to check (`PhoneTabsTests.testGlowWeekPersonAndLookingBack`), and on
            // iOS 27 a hosted bar reports pieces beyond the window's sides.
            PocketGlowPerson(personId: house.other.id, weeksBack: .constant(weeksBack)) { _ in }
                .environment(house.model).environment(house.home).environment(\.me, house.me),
            look: look
        )
        try page.saveShot("glow-person-\(look.name)")
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        #expect(page.elements.contains { $0.label.hasPrefix("Mia") }, "whose page it is:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.contains("this week") && $0.label.contains("last week") }, "this week beside last week:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.contains("all time") }, "all time:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.hasPrefix("Mia's week") }, "her days:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.hasPrefix("What Mia did") }, "what she did:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.hasPrefix("Mia's own treat") }, "her own treat:\n\(page.listing)")
        #expect(!page.elements.contains { $0.isButton && $0.label.hasPrefix("Cash in") }, "someone else's treat is theirs to cash in:\n\(page.listing)")
    }

    @Test(
        "An earlier week tells what was earned and enjoyed then, and says that saving is about now",
        arguments: ["light", "largest-dark"]
    )
    func earlierWeek(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await glow(try house(), look: look, shot: "glow-last-week", weeksBack: 1)
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        #expect(page.elements.contains { $0.label.hasPrefix("Last week, ") }, "the pager names the week:\n\(page.listing)")
        #expect(page.elements.contains { $0.isButton && $0.label == "Back to this week" }, "a way back:\n\(page.listing)")
        #expect(page.elements.contains { $0.isButton && $0.label == "Next week" }, "a step forward:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.contains("that week") }, "the labels say that week:\n\(page.listing)")
        #expect(!page.elements.contains { $0.label.contains("this time last week") }, "an earlier week is compared whole:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.hasPrefix("Saving for") && $0.label.contains("now") }, "saving is about now:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.hasPrefix("That week") }, "what happened that week:\n\(page.listing)")
        #expect(!page.elements.contains { $0.label == "TODAY" }, "nothing of today on an earlier week:\n\(page.listing)")
    }

    @Test("This week has a way back, as far as the first star, and what was cashed in stays as a history")
    func lookingBack() async throws {
        let house = try house()
        let page = try await glow(house, look: .light, shot: "glow-pager")
        #expect(page.elements.contains { $0.isButton && $0.label == "Previous week" }, "a way back:\n\(page.listing)")
        #expect(!page.elements.contains { $0.isButton && $0.label == "Next week" }, "nothing after this week:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.hasPrefix("Cashed in") }, "what was cashed in:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.hasPrefix("Ice cream trip") }, "the treat already enjoyed:\n\(page.listing)")
        // The samples go back about five weeks; the pager goes no further than the first star.
        let first = try #require(house.home.snapshot.firstStarDay)
        let limit = GlowWeeks.limit(firstDay: first, today: house.home.today, calendar: house.home.calendar)
        #expect(limit >= 3 && limit <= 6, "back to the first star: \(limit) weeks from \(first)")
        let furthest = try await glow(house, look: .light, shot: "glow-first-week", weeksBack: 40)
        #expect(!furthest.elements.contains { $0.isButton && $0.label == "Previous week" }, "the first week is the last step back:\n\(furthest.listing)")
        #expect(furthest.elements.contains { $0.label.hasPrefix("\(limit) weeks ago, ") }, "asked for further, it shows the first week:\n\(furthest.listing)")
    }

    @Test(
        "With chores and nothing to save for, Glow offers three rewards in one tap and your own",
        arguments: ["light", "largest-dark"]
    )
    func rewardIdeas(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let house = try house(samples: false)
        let page = try await glow(house, look: look, shot: "glow-no-reward")
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        #expect(page.elements.contains { $0.label.hasPrefix("Something to save for") }, "what the card is for:\n\(page.listing)")
        let ideas = page.elements.filter { $0.isButton && $0.label.hasPrefix("Save for ") }
        #expect(ideas.map(\.label) == ["Save for Movie night, 20 stars", "Save for Takeout pick, 15 stars", "Save for Ice cream run, 10 stars"], "three ideas:\n\(page.listing)")
        #expect(ideas.allSatisfy { $0.frame.height >= 44 }, "each a full touch target: \(ideas.map(\.frame))")
        #expect(page.elements.contains { $0.isButton && $0.label == "Your own reward" }, "or your own:\n\(page.listing)")
        // One tap, and the household is saving for it.
        let picked = try await HostedScreen.host(
            PocketGlowScreen().environment(house.model).environment(house.home).environment(\.me, house.me), look: look, activating: "Save for Takeout pick"
        )
        #expect(picked.elements.contains { $0.label.hasPrefix("Saving for") }, "the saving card:\n\(picked.listing)")
        #expect(picked.elements.contains { $0.label.contains("Takeout pick") }, "the reward picked:\n\(picked.listing)")
        #expect(!picked.elements.contains { $0.label.hasPrefix("Something to save for") }, "the ideas step aside:\n\(picked.listing)")
        let saved = try #require(house.home.snapshot.rewards.first)
        #expect(saved.title == "Takeout pick" && saved.targetStars == 15 && saved.ownerId == nil && !saved.archived)
    }

    @Test("A reward still being saved for says how far it is at the household's pace, once there is enough to go on")
    func pace() async throws {
        let house = try house(samples: false)
        let calendar = house.home.calendar
        let today = house.home.today
        let chore = try #require(house.home.snapshot.chores.first)
        _ = try house.db.saveReward(RewardDraft(title: "Movie night", emoji: "🍿", targetStars: 20, ownerId: nil), householdId: chore.householdId, today: today.adding(days: -20, calendar: calendar))
        // Two days with a star: too little to go on.
        for back in [1, 3] {
            try house.db.toggleChore(id: chore.id, day: today.adding(days: -back, calendar: calendar), personId: house.me.id, now: today.adding(days: -back, calendar: calendar).startDate(in: calendar))
        }
        var page = try await glow(house, look: .light, shot: "glow-no-pace")
        #expect(!page.elements.contains { $0.label.contains("at this pace") }, "silent with too little to go on:\n\(page.listing)")
        // Seven days with a star in the last two weeks: 7 of 20 earned, half a star a day.
        for back in [5, 7, 9, 11, 13] {
            try house.db.toggleChore(id: chore.id, day: today.adding(days: -back, calendar: calendar), personId: house.me.id, now: today.adding(days: -back, calendar: calendar).startDate(in: calendar))
        }
        page = try await glow(house, look: .light, shot: "glow-pace")
        #expect(page.elements.contains { $0.label.contains("about 4 weeks away at this pace") }, "13 stars to go at half a star a day:\n\(page.listing)")
    }

    @Test("Stars from before the usual window are read when an earlier week is asked for")
    func readsFurtherBack() async throws {
        let house = try house()
        let calendar = house.home.calendar
        // Past every sample, so nothing but the pager's own asking loads it.
        let week = GlowWeeks.week(weeksBack: 30, today: house.home.today, calendar: calendar)
        let from = GlowWeeks.loadFrom(week, calendar: calendar)
        let old = try house.db.saveChore(
            ChoreDraft(title: "Old chore", emoji: "🧺", ownerId: house.me.id, recurrence: .daily, anchorDay: from, timeHint: nil, stars: 2),
            householdId: try #require(house.home.householdId)
        )
        try house.db.toggleChore(id: old.id, day: week.first, personId: house.me.id, now: week.first.startDate(in: calendar))
        try house.db.toggleChore(id: old.id, day: from, personId: house.me.id, now: from.startDate(in: calendar))
        let home = HomeStore(database: house.db)
        #expect(!home.snapshot.earnings.contains { week.contains($0.day) }, "not read until asked for")
        var weeksBack = 0
        let pager = GlowPager(home: home, weeksBack: Binding(get: { weeksBack }, set: { weeksBack = $0 }))
        #expect(pager.limit == 31, "back to the week of the first star: \(pager.limit)")
        pager.page.go(30)
        #expect(weeksBack == 30)
        #expect(home.snapshot.earnings.contains { week.contains($0.day) }, "that week's stars are read")
        #expect(home.snapshot.earnings.contains { $0.day == from }, "and the week before it, for the trend")
    }
}
#endif
