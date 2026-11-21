#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The phone's Food diary on this week, last week and an empty week, hosted in the unit
/// bundle (`HostedScreen`) with the sample diary, in light, dark, at the largest text and
/// both together: the week pager sits on the week's card, says which week it is, offers
/// the way back, and nothing runs off the screen. `PhoneFoodTests.testChangingWeeks` keeps
/// the one journey only the real app shows: tapping back, opening a meal and coming back
/// to the same week, filling a past slot, and returning to this week.
///
/// The sample diary is built around the real day (the last thirteen days, and a meal a year
/// ago, so three weeks back is empty), so nothing here asserts a date or a count.
@Suite("The phone's Food diary, other weeks")
@MainActor
struct PocketFoodScreenTests {
    private func diary(weeksBack: Int, _ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "food-weeks")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        let snapshot = try db.snapshot()
        try FoodSamples.seed(db, household: try #require(snapshot.household), people: snapshot.people)
        let screen = PocketFoodScreen(weeksBack: weeksBack)
            .environment(AppModel(database: db))
            .environment(FoodStore(database: db))
            .environment(ToastCenter())
            .environment(PhotoImages(database: db))
            .environment(\.me, snapshot.people[0])
        let hosted = try await HostedScreen.host(screen, look: look)
        try hosted.saveShot("food-week-\(weeksBack)-\(look.name)")
        return hosted
    }

    @Test(
        "The pager names the week, offers back and forward as far as there are weeks, and nothing runs off either side",
        arguments: [0, 1, 3], ["light", "dark", "largest", "largest-dark"]
    )
    func pager(weeksBack: Int, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await diary(weeksBack: weeksBack, look)
        #expect(page.elements.count >= 10, "the page was read (\(weeksBack), \(look)):\n\(page.listing)")
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(weeksBack), \(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        let name = try #require(page.element(beginningWith: PocketFood.weekName(weeksBack: weeksBack)), "the week's name:\n\(page.listing)")
        let back = try #require(page.elements.first { $0.isButton && $0.label == "Previous week" }, "back, to the year-ago meal's week:\n\(page.listing)")
        let forward = page.elements.first { $0.isButton && $0.label == "Next week" }
        let home = page.elements.first { $0.isButton && $0.label == "Back to this week" }
        #expect(back.frame.width >= 44 && back.frame.height >= 44, "back is a whole target: \(back.frame)")
        #expect(back.frame.maxX <= name.frame.minX + 1, "back is before the name: \(back.frame), \(name.frame)")
        if weeksBack == 0 {
            #expect(forward == nil, "nothing after today")
            #expect(home == nil)
        } else {
            let forward = try #require(forward, "forward:\n\(page.listing)")
            #expect(forward.frame.minX >= name.frame.maxX - 1, "forward is after the name: \(name.frame), \(forward.frame)")
            #expect(home != nil, "the way back to this week:\n\(page.listing)")
            #expect(abs(back.frame.midY - forward.frame.midY) < 1, "the chevrons sit level")
        }
        let grid = page.elements.filter { $0.isButton && $0.label.contains(", not logged") || $0.label.contains(": ") && $0.isButton }
        if let firstSlot = grid.first {
            #expect(name.frame.maxY <= firstSlot.frame.minY + 1, "the pager is above the week's slots: \(name.frame), \(firstSlot.frame)")
        }
        if weeksBack == 3 {
            #expect(page.element(beginningWith: "Nothing logged") != nil, "an empty week says so:\n\(page.listing)")
            #expect(page.element(beginningWith: "Practice turkey") == nil, "no \"On this day\" away from this week")
        }
    }
}
#endif
