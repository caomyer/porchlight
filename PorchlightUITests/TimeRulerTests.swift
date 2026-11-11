import XCTest

/// Times are picked with the app's own pill and day ruler, not the system wheel.
@MainActor
final class TimeRulerTests: XCTestCase {
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    /// A saved breakfast (8:40 AM in the samples) is moved with the nudges and by
    /// tapping along the ruler, and the pill follows.
    func testFixingAMealTimeOnTheRuler() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "food"]
        app.launch()

        let breakfast = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Breakfast: Avocado toast'")).firstMatch
        XCTAssertTrue(breakfast.waitForExistence(timeout: 30))
        breakfast.tap()
        app.buttons["Edit"].tap()

        let pill = element(app, "time-eaten")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(value(pill), "8:40 AM")
        XCTAssertFalse(element(app, "time-ruler").exists, "The ruler opens only when asked")
        pill.tap()

        let ruler = element(app, "time-ruler")
        XCTAssertTrue(ruler.waitForExistence(timeout: 5), "Tapping the time opens the day ruler")
        XCTAssertEqual(value(ruler), "8:40 AM")
        snapshot("60-meal-ruler")

        app.buttons["5 minutes earlier"].tap()
        XCTAssertEqual(value(ruler), "8:35 AM")
        XCTAssertEqual(value(pill), "8:35 AM", "The pill follows the ruler")

        // The ruler runs 6am to midnight, so its middle is 3pm.
        ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(value(pill), "3:00 PM")
        snapshot("61-meal-ruler-moved")

        app.buttons["Done"].tap()
        XCTAssertTrue(ruler.waitForNonExistence(timeout: 5), "Done closes the ruler")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForNonExistence(timeout: 5))
    }

    /// Snap a meal is the tallest form; with the ruler open, Save must stay on screen.
    func testTheRulerFitsWhenSnappingAMeal() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "food", "-debugFoodView", "capture", "-debugCaptureShots", "1"]
        app.launch()

        let pill = element(app, "time-eaten")
        XCTAssertTrue(pill.waitForExistence(timeout: 30))
        pill.tap()
        XCTAssertTrue(element(app, "time-ruler").waitForExistence(timeout: 5))
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save'")).firstMatch
        XCTAssertTrue(save.exists)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(save.frame), "Save should stay on screen with the ruler open")
        snapshot("64-capture-ruler")
    }

    /// The walk's quick choices stay, and the ruler picks anything else.
    func testPickingAWalkStartOnTheRuler() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "today"]
        app.launch()

        let log = app.buttons.matching(NSPredicate(format: "label CONTAINS 'I walked Yo-Yo'")).firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 30))
        log.tap()
        XCTAssertTrue(app.staticTexts["Who walked Yo-Yo?"].waitForExistence(timeout: 5))
        app.buttons["1 hr ago"].tap()

        let pill = element(app, "exact-time")
        pill.tap()
        let ruler = element(app, "time-ruler")
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        XCTAssertEqual(value(ruler), value(pill))
        snapshot("62-walk-ruler")

        let before = value(pill)
        app.buttons["5 minutes earlier"].tap()
        // Just after midnight there may be nothing earlier to pick.
        if value(pill) != before {
            XCTAssertFalse(app.buttons["1 hr ago"].isSelected, "An exact time replaces the quick choice")
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(ruler.waitForNonExistence(timeout: 5))
        snapshot("63-walk-ruler-closed")
    }
}
