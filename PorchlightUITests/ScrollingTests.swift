import XCTest

/// Scrollable screens must follow a finger. The wall watches every touch for its
/// idle timer, and that watcher must never steal pans from a scroll view.
@MainActor
final class ScrollingTests: XCTestCase {
    func testSettingsScrollsToTheLastSection() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "settings"]
        app.launch()

        let householdName = app.textFields["Household name"].firstMatch
        XCTAssertTrue(householdName.waitForExistence(timeout: 30))
        let lastRow = app.staticTexts["Photo frame when idle"].firstMatch
        XCTAssertTrue(lastRow.waitForExistence(timeout: 10))
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(lastRow.frame.minY, screen.maxY, "The display section should start below the fold")

        for _ in 0..<6 where lastRow.frame.maxY > screen.maxY {
            let window = app.windows.firstMatch
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }

        XCTAssertLessThanOrEqual(lastRow.frame.maxY, screen.maxY, "Swiping up should bring the last section on screen")
        XCTAssertLessThan(householdName.frame.maxY, screen.minY + 1, "The household section should have scrolled off the top")
    }

    /// Touches still count as activity: the wall stays put while someone keeps
    /// dragging, and switches to Ambient once the touches stop.
    func testTouchesKeepTheWallAwake() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "chores", "-display.ambientMinutes", "1"]
        app.launch()
        let ambient = app.descendants(matching: .any)["ambient"]
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30))

        let start = Date.now
        while Date.now.timeIntervalSince(start) < 95 {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.6))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0)
            Thread.sleep(forTimeInterval: 20)
        }
        XCTAssertFalse(ambient.exists, "Regular touches should keep Ambient away")

        XCTAssertTrue(ambient.waitForExistence(timeout: 100), "Ambient should appear about a minute after the last touch")
    }
}
