#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The phone's Lists, Glow and Pitch in, each a whole page hosted in the unit bundle
/// (`HostedScreen`) with the sample household's chores, rewards and lists, in light, dark,
/// at the largest text and both together. `PhoneTabsTests` launched the app twice to
/// photograph these in two looks; it keeps one launch (`testLooks`) for what only the real
/// tabs show, and its journeys for the rest (adding to a list, cashing in, adding a chore).
///
/// The sample is built around the real day, so nothing here asserts a date or a count:
/// only what is on each page and that it fits.
@Suite("The phone's Lists, Glow and Pitch in, the whole pages")
@MainActor
struct PocketTabsScreenTests {
    private func page(_ kind: String, _ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "tabs")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        let snapshot = try db.snapshot()
        let seeded = try #require(snapshot.household)
        try CompanionSamples.seed(db, household: seeded, people: snapshot.people)
        try HomeSamples.seed(db, household: seeded, people: snapshot.people)
        let model = AppModel(database: db)
        let home = HomeStore(database: db)
        let companions = CompanionStore(database: db)
        let toasts = ToastCenter()
        let me = snapshot.people[0]
        let hosted: HostedScreen
        switch kind {
        case "glow":
            hosted = try await HostedScreen.host(PocketGlowScreen().environment(model).environment(home).environment(\.me, me), look: look)
        case "pitch-in":
            hosted = try await HostedScreen.host(
                PocketPitchIn(logging: PocketLogging(companions: companions, home: home, toasts: toasts, me: me.id))
                    .environment(model).environment(home).environment(companions).environment(toasts).environment(\.me, me),
                look: look
            )
        default:
            hosted = try await HostedScreen.host(
                PocketListsScreen().environment(model).environment(home).environment(toasts).environment(\.me, me), look: look
            )
        }
        try hosted.saveShot("\(kind)-\(look.name)")
        return hosted
    }

    @Test(
        "Lists, Glow and Pitch in each fit across the screen and show what they are for, in each look",
        arguments: ["lists", "glow", "pitch-in"], ["light", "dark", "largest", "largest-dark"]
    )
    func fits(kind: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await page(kind, look)
        #expect(page.elements.count >= 6, "the page was read (\(kind), \(look)):\n\(page.listing)")
        // The lists' own row of chips (Groceries, House, This week's dinners) scrolls sideways,
        // so its later chips are past the edge by design; everything else must fit.
        let chipRow = page.elements.first { $0.isButton && $0.label.hasPrefix("Groceries ·") }?.frame.minY
        let offSides = page.offSides.filter { element in chipRow.map { abs(element.frame.minY - $0) >= 1 } ?? true }
        #expect(offSides.isEmpty, "nothing runs off either side (\(kind), \(look)): \(offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        switch kind {
        case "glow":
            #expect(page.elements.contains { $0.label.hasPrefix("Saving for") }, "what everyone is saving for:\n\(page.listing)")
            let cashIn = try #require(page.elements.first { $0.isButton && $0.label == "Cash in Fancy coffee run" }, "a reward that is reached:\n\(page.listing)")
            #expect(cashIn.frame.width > 0 && cashIn.frame.maxX <= HostedScreen.size.width, "the cash-in button is whole: \(cashIn.frame)")
        case "pitch-in":
            #expect(page.elements.contains { $0.label.hasPrefix("Pitch in") }, "the page's title:\n\(page.listing)")
            #expect(page.elements.contains { $0.isButton && $0.label.hasPrefix("Check off ") }, "a chore to check off:\n\(page.listing)")
        default:
            #expect(page.elements.contains { $0.label.hasPrefix("Groceries") }, "the grocery list:\n\(page.listing)")
            #expect(page.elements.contains { $0.label.localizedCaseInsensitiveContains("produce") }, "its aisles:\n\(page.listing)")
        }
    }
}
#endif
