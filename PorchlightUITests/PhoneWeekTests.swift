import XCTest

/// A companion's week on the phone, in parity with the wall's companion page: the paw
/// trail's dots do what the wall's do, every routine (walks, meals, water) has its own
/// trail and diary, and the page holds up in the night look, at the largest text size
/// and for a first week. Runs only on an iPhone (`scripts/test.sh --phone`).
///
/// Time is pinned to 5:20 pm today, like PhoneTests: this morning's walk is done, the
/// evening walk and dinner are open, and the sample skipped the morning walk four days
/// ago and yesterday's dinner.
@MainActor
final class PhoneWeekTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    override func tearDown() {
        MainActor.assumeIsolated { XCUIDevice.shared.appearance = .light }
        super.tearDown()
    }

    private static var evening: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02dT17:20", parts.year!, parts.month!, parts.day!)
    }

    private static let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.evening, "-me", "James"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        waitUntilResponsive(app)
        return app
    }

    private func openWeek(_ app: XCUIApplication, of name: String = "Yo-Yo") {
        let card = app.buttons["week-\(name)"]
        reveal(card, in: app)
        card.tap()
        XCTAssertTrue(element(app, beginningWith: "\(name)'s week").waitForExistence(timeout: 10), "Tapping a card opens its week")
    }

    /// A trail dot, scrolled into view.
    private func dot(_ app: XCUIApplication, _ routine: String, day: Int, slot: Int) -> XCUIElement {
        let dot = app.buttons["trail-\(routine)-\(day)-\(slot)"]
        XCTAssertTrue(dot.waitForExistence(timeout: 5), "\(routine) day \(day) slot \(slot) is a button")
        reveal(dot, in: app)
        return dot
    }

    /// Swipes a sheet away by its title and waits for it to go.
    private func closeSheet(_ title: XCUIElement) {
        title.swipeDown(velocity: .fast)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10), "The sheet closes")
    }

    // MARK: The paw trail

    /// Mirrors the wall's trail: a logged dot opens its walk to fix, a missed one logs it
    /// for its own day, and one still open today starts a new walk.
    func testTappingThePawTrail() {
        let app = launch()
        openWeek(app)

        let morning = dot(app, "Walk", day: 6, slot: 0)
        XCTAssertTrue(morning.label.hasPrefix("Morning walk, "), morning.label)
        snapshot("week-10-trail")
        morning.tap()
        let edit = app.staticTexts["Edit walk"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "A logged dot opens its walk to fix")
        XCTAssertTrue(app.staticTexts["Fix who, when or how it went"].exists)
        snapshot("week-11-trail-edit")
        closeSheet(edit)

        let missed = dot(app, "Walk", day: 2, slot: 0)
        XCTAssertTrue(missed.label.hasSuffix("missed"), missed.label)
        missed.tap()
        let slot = app.staticTexts["YO-YO · MORNING WALK"]
        XCTAssertTrue(slot.waitForExistence(timeout: 5), "A missed dot logs that morning's walk")
        snapshot("week-12-trail-missed")
        closeSheet(slot)

        let evening = dot(app, "Walk", day: 6, slot: 1)
        XCTAssertTrue(evening.label.hasSuffix("to do"), evening.label)
        evening.tap()
        let new = app.staticTexts["Log a walk"]
        XCTAssertTrue(new.waitForExistence(timeout: 5), "Tonight's open dot starts a walk")
        closeSheet(new)
    }

    // MARK: Every routine

    /// Meals have their own trail and diary: yesterday's skipped dinner shows in both, and
    /// a dinner logged from the trail appears in both.
    func testAMealInTheDiaryAndTheTrail() {
        let app = launch()
        openWeek(app)
        let feed = app.buttons["routine-Feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 5), "Each routine has its week")
        feed.tap()
        XCTAssertTrue(feed.isSelected)
        XCTAssertTrue(element(app, beginningWith: "Meal diary").waitForExistence(timeout: 5))
        XCTAssertTrue(dot(app, "Feed", day: 5, slot: 1).label.hasSuffix("missed"), "Yesterday's dinner was skipped")
        snapshot("week-20-meals")

        let dinner = dot(app, "Feed", day: 6, slot: 1)
        XCTAssertTrue(dinner.label.hasPrefix("Dinner, "), dinner.label)
        XCTAssertTrue(dinner.label.hasSuffix("to do"), dinner.label)
        dinner.tap()
        XCTAssertTrue(app.staticTexts["Log a meal"].waitForExistence(timeout: 5))
        let save = app.buttons["save-care"]
        reveal(save, in: app)
        save.waitToSettle()
        save.tap()
        XCTAssertTrue(app.staticTexts["Log a meal"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Meal logged"].waitForExistence(timeout: 10), "The toast says it was logged")
        XCTAssertTrue(app.buttons["trail-Feed-6-1"].label.hasSuffix("James"), "Tonight's dinner is in the trail, mine")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Today 5:20'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "and in the diary")
        reveal(row, in: app)
        snapshot("week-21-meal-logged")

        let chef = element(app, beginningWith: "Chef of the week")
        reveal(chef, in: app)
        XCTAssertTrue(chef.exists, "The meals' podium")
        snapshot("week-22-meals-podium")
    }

    /// Water has its week too.
    func testWater() {
        let app = launch(["-sampleWater"])
        openWeek(app)
        app.buttons["routine-Water"].tap()
        XCTAssertTrue(element(app, beginningWith: "Watering diary").waitForExistence(timeout: 5))
        XCTAssertTrue(dot(app, "Water", day: 4, slot: 0).label.hasSuffix("missed"), "Two days ago's water was skipped")
        snapshot("week-30-water")
    }

    // MARK: Looks

    /// Walks, meals and water in the night look and at the largest text size: nothing runs
    /// off the screen, and the trail, tabs and log button stay reachable.
    func testWeekLooks() {
        let looks: [(name: String, appearance: XCUIDevice.Appearance, arguments: [String])] = [
            ("dark", .dark, []), ("largest", .light, Self.largest), ("largest-dark", .dark, Self.largest),
        ]
        for look in looks {
            XCUIDevice.shared.appearance = look.appearance
            let app = launch(["-sampleWater"] + look.arguments)
            let window = app.windows.firstMatch.frame
            openWeek(app)
            snapshot("week-40-\(look.name)-top")
            for routine in ["Walk", "Feed", "Water"] {
                let tab = app.buttons["routine-\(routine)"]
                reveal(tab, in: app)
                XCTAssertTrue(window.contains(tab.frame), "\(routine)'s tab is whole on screen: \(tab.frame)")
                tab.tap()
                let log = app.buttons["log-routine"]
                reveal(log, in: app)
                XCTAssertTrue(log.isHittable && window.contains(log.frame), "The log button is whole on screen")
                let today = dot(app, routine, day: 6, slot: 0)
                XCTAssertLessThanOrEqual(today.frame.maxX, window.maxX + 1, "The trail fits across the screen")
                snapshot("week-41-\(look.name)-\(routine.lowercased())-trail")
                let milestones = element(app, beginningWith: "Little milestones")
                reveal(milestones, in: app)
                snapshot("week-42-\(look.name)-\(routine.lowercased())-end")
                let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                for _ in 0..<6 { top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))) }
            }
            app.terminate()
        }
    }

    /// A companion added today: the first week, never a zero, in the wall's words.
    func testAFirstWeek() {
        let app = launch(["-sampleCompanions", "4"])
        openWeek(app, of: "Pip")
        XCTAssertTrue(element(app, beginningWith: "Pip's week").exists)
        XCTAssertTrue(element(app, beginningWith: "Mood, Waiting for first meal").exists, "No mood before the first meal")
        snapshot("week-50-first-week")
        let empty = element(app, beginningWith: "Nothing logged this week yet. The first meal starts the story.")
        reveal(empty, in: app)
        XCTAssertTrue(empty.exists)
        let podium = element(app, beginningWith: "No meals yet this week. The podium is wide open.")
        reveal(podium, in: app)
        XCTAssertTrue(podium.exists)
        snapshot("week-51-first-week-end")
    }
}
