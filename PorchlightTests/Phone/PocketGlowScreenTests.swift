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

    private func glow(_ house: House, look: HostedScreen.Look, shot: String) async throws -> HostedScreen {
        let hosted = try await HostedScreen.host(
            PocketGlowScreen().environment(house.model).environment(house.home).environment(\.me, house.me), look: look
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
        let page = try await HostedScreen.host(
            NavigationStack { PocketGlowPerson(personId: house.other.id) { _ in } }
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
}
#endif
