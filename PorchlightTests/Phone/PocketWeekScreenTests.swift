#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// A companion's week, the whole screen, hosted in the unit bundle with the sample
/// companion in an in-memory database (`HostedScreen`): the working example of a whole
/// screen's layout checked, and its review shots drawn, without launching the app.
///
/// The facts are the ones `PhoneWeekTests.testWeekLooks` checks by scrolling the real page
/// in each look, for walks and for meals: the routine tabs and the log button are whole
/// across the screen, the trail fits, and nothing runs off either side. That took the UI
/// test six to twelve minutes; it keeps one launch now, for what only the real page shows
/// (the tabs and the log button within reach by scrolling at the largest size, water too).
///
/// With `TEST_RUNNER_PORCHLIGHT_SCREEN_SHOTS=<folder>` set for `xcodebuild test`, each
/// look's whole page is written there as a PNG, as `WidgetRenderTests` does for widgets.
///
/// The sample is built around `CompanionClock`'s "now", which is pinned to one Wednesday
/// morning while the app hosts the unit tests (`CompanionClock.unitTestsNow`), so the
/// screen and its shots are the same whenever the suite runs. Even so, nothing here
/// asserts a time, a count or a day's name: only where things sit.
@Suite("A companion's week, the whole screen")
@MainActor
struct PocketWeekScreenTests {
    private func week(_ look: HostedScreen.Look, routine: String = "Walk") async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "screen")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        let snapshot = try db.snapshot()
        try CompanionSamples.seed(db, household: try #require(snapshot.household), people: snapshot.people)
        let store = CompanionStore(database: db)
        let toasts = ToastCenter()
        let me = snapshot.people[0]
        let screen = PocketCompanionWeek(
            companionId: try #require(store.companions.first).id,
            logging: PocketLogging(companions: store, home: HomeStore(database: db), toasts: toasts, me: me.id)
        )
        .environment(store)
        .environment(toasts)
        .environment(\.me, me)
        // The page opens on the first routine; another is picked as a tap on its tab would.
        let hosted = try await HostedScreen.host(screen, look: look, activating: routine == "Walk" ? nil : routine)
        try hosted.saveShot("week-\(routine.lowercased())-\(look.name)")
        return hosted
    }

    @Test(
        "Nothing runs off either side, and the tabs, the log button and the trail are whole, for walks and for meals in every look",
        arguments: ["Walk", "Feed"], ["light", "dark", "largest", "largest-dark"]
    )
    func fitsAcross(routine: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let screen = try await week(look, routine: routine)
        let width = HostedScreen.size.width
        #expect(screen.elements.count > 30, "the screen was read: \(screen.elements.count) elements")
        for element in screen.elements {
            #expect(element.frame.minX >= 0 && element.frame.maxX <= width, "\(element.label.prefix(40)) is whole across the screen in \(look): \(element.frame)")
            #expect(element.frame.width > 0 && element.frame.height > 0, "\(element.label.prefix(40)) has a size in \(look)")
        }
        let walk = try #require(screen.element(beginningWith: "Walk"))
        let feed = try #require(screen.element(beginningWith: "Feed"))
        let log = try #require(screen.elements.first { $0.isButton && $0.label.hasPrefix(routine == "Walk" ? "Log a walk" : "Log a meal") }, "the log button:\n\(screen.listing)")
        #expect(log.frame.width > width / 2, "the log button is a full button: \(log.frame)")
        #expect(screen.elements.contains { $0.label.hasPrefix(routine == "Walk" ? "Walk diary" : "Meal diary") }, "the routine's own diary:\n\(screen.listing)")
        let title = try #require(screen.element(beginningWith: "Yo-Yo's week"))
        #expect(!walk.frame.intersects(feed.frame), "the routine tabs don't cover each other: \(walk.frame), \(feed.frame)")
        #expect(title.frame.maxY <= walk.frame.minY && walk.frame.maxY <= log.frame.minY, "the title, then the tabs, then the log button")
        let slots = routine == "Walk" ? ["Morning walk, ", "Evening walk, "] : ["Breakfast, ", "Dinner, "]
        let dots = screen.elements.filter { element in element.isButton && slots.contains { element.label.hasPrefix($0) } }
        #expect(dots.count == 14, "a week of two slots a day: \(dots.count)\n\(screen.listing)")
        for (first, second) in zip(dots, dots.dropFirst()) where abs(first.frame.minY - second.frame.minY) < 1 {
            #expect(first.frame.maxX <= second.frame.minX + 1, "the trail's dots sit side by side: \(first.frame), \(second.frame)")
        }
        #expect(screen.image.size.width == width && screen.image.size.height >= HostedScreen.size.height)
    }

    @Test("At the largest text the tabs stack and the page grows longer, never wider")
    func largestStacks() async throws {
        let usual = try await week(.light)
        let largest = try await week(.largest)
        let walk = try #require(usual.element(beginningWith: "Walk"))
        let feed = try #require(usual.element(beginningWith: "Feed"))
        #expect(abs(walk.frame.minY - feed.frame.minY) < 1, "side by side at the usual size")
        let bigWalk = try #require(largest.element(beginningWith: "Walk"))
        let bigFeed = try #require(largest.element(beginningWith: "Feed"))
        #expect(bigFeed.frame.minY >= bigWalk.frame.maxY, "one under the other at the largest")
        #expect(largest.image.size.height > usual.image.size.height)
    }
}
#endif
