import XCTest

/// Scrollable screens must follow a finger. The wall watches every touch for its
/// idle timer, and that watcher must never steal pans from a scroll view.
@MainActor
final class ScrollingTests: XCTestCase {
    func testSettingsScrollsToTheLastSection() {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "settings"]
        app.launch()

        let householdName = app.textFields["Household name"].firstMatch
        XCTAssertTrue(householdName.waitForExistence(timeout: 30))
        let lastRow = app.staticTexts["Photo frame when idle"].firstMatch
        XCTAssertTrue(lastRow.waitForExistence(timeout: 10))
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(lastRow.frame.minY, screen.maxY, "The display section should start below the fold")

        for _ in 0..<10 where lastRow.frame.maxY > screen.maxY {
            let window = app.windows.firstMatch
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }

        XCTAssertLessThanOrEqual(lastRow.frame.maxY, screen.maxY, "Swiping up should bring the last section on screen")
        XCTAssertLessThan(householdName.frame.maxY, screen.minY + 1, "The household section should have scrolled off the top")
    }

    /// What only the real wall can get wrong about going idle, in two launches that no slow
    /// Mac can fail: a real drag over a scrolling screen reaches the idle watcher, and with
    /// nobody touching it the wall does go to Ambient.
    ///
    /// The rule between the two (a touch starts the wait again; Ambient comes when the wait is
    /// over) is `IdleRuleTests`, with every time handed in. This test used to touch the wall
    /// every four seconds of a twelve-second "minute" and assert Ambient had stayed away; a
    /// hosted Mac that took 50 seconds over one drag made it fail with the app in the right
    /// (run 44905599973). Nothing here is a race: the first launch's wait is ten real minutes,
    /// far longer than the test, and the second only waits for Ambient to come.
    func testTouchesReachTheIdleWatcherAndAnUntouchedWallGoesToAmbient() {
        // 1. A drag is seen. The wait is 600 seconds, so Ambient cannot come meanwhile.
        var app = XCUIApplication.porchlight()
        app.launchArguments = [
            "-sampleHousehold", "-startScreen", "chores", "-display.ambientMinutes", "1", "-debugIdleSecondsPerMinute", "600",
        ]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        let seen = app.descendants(matching: .any)["wall-touches"]
        XCTAssertTrue(seen.waitForExistence(timeout: 30), "The idle watcher says how many touches it has seen")
        let before = Int(seen.value as? String ?? "") ?? -1
        XCTAssertGreaterThanOrEqual(before, 0, "A count: \(String(describing: seen.value))")
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.6))
        from.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0)
        let counted = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in (Int((element as? XCUIElement)?.value as? String ?? "") ?? -1) > before }, object: seen
        )
        XCTAssertEqual(XCTWaiter().wait(for: [counted], timeout: 30), .completed, "A drag over the board reaches the idle watcher: \(String(describing: seen.value))")
        XCTAssertFalse(app.descendants(matching: .any)["ambient"].exists, "and the wall stays where it is")
        app.terminate()

        // 2. Nobody touches it: a "minute" of three seconds, and Ambient comes, however long
        //    this Mac takes to look.
        app = XCUIApplication.porchlight()
        app.launchArguments = [
            "-sampleHousehold", "-startScreen", "chores", "-display.ambientMinutes", "1", "-debugIdleSecondsPerMinute", "3",
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["ambient"].waitForExistence(timeout: 120), "An untouched wall goes to Ambient")
    }
}
