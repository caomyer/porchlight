import XCTest

/// Catching up on care that was never logged: a missed slot shows as a faint mark where its
/// record would be (the calendar, Paw trail, the diary), and tapping it logs it for that day.
/// The sample household missed yesterday's dinner and a morning walk 4 days ago.
final class CatchUpTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold"] + arguments
        app.launch()
        _ = app.otherElements.firstMatch.waitForExistence(timeout: 30)
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(_ app: XCUIApplication, beginningWith part: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", part)).firstMatch
    }

    /// The feedback: "forgot to log feeding her last night, and can't find where to add it".
    func testLoggingYesterdaysDinnerFromTheCalendar() {
        let app = launch(["-startScreen", "calendar", "-calendarMode", "day"])
        let previous = app.buttons["Previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 40))
        previous.tap()
        let missed = app.buttons["Feed Yo-Yo · Dinner, Not logged"]
        XCTAssertTrue(missed.waitForExistence(timeout: 5), "Yesterday's missed dinner shows where it would be")
        snapshot("90-day-missed-dinner")
        missed.tap()
        XCTAssertTrue(app.staticTexts["Who fed Yo-Yo?"].waitForExistence(timeout: 5), "It opens the usual log sheet")
        XCTAssertTrue(app.staticTexts["For yesterday's dinner"].exists, "The sheet says which day and meal")
        XCTAssertTrue((app.buttons["exact-time"].value as? String)?.contains("PM") == true, "The time starts at dinner, not now")
        snapshot("91-catch-up-sheet")
        app.buttons["Save meal"].tap()
        XCTAssertTrue(missed.waitForNonExistence(timeout: 5), "The missed mark is filled in")
        XCTAssertTrue(button(app, beginningWith: "James fed Yo-Yo").exists, "and shows who fed her")
    }

    /// The week grid shows missed slots too, as dashed marks.
    func testMissedCareInTheWeek() {
        let app = launch(["-startScreen", "calendar", "-calendarMode", "week"])
        let walk = button(app, beginningWith: "James walked Yo-Yo")
        XCTAssertTrue(walk.waitForExistence(timeout: 40))
        let missed = app.buttons.matching(NSPredicate(format: "label ENDSWITH ', Not logged'"))
        XCTAssertGreaterThan(missed.count, 0, "Missed slots this week are marked")
        snapshot("92-week-missed")
    }

    /// Yo-Yo's page: the diary lists what wasn't logged, and Paw trail's empty dots open the sheet.
    func testCatchingUpFromYoYosWeek() {
        let app = launch(["-startScreen", "companion-1"])
        let dinner = app.buttons["Feed Yo-Yo · Dinner wasn't logged, yesterday"]
        XCTAssertTrue(dinner.waitForExistence(timeout: 40), "The diary lists yesterday's missed dinner")
        snapshot("93-diary-missed")
        dinner.tap()
        XCTAssertTrue(app.staticTexts["For yesterday's dinner"].waitForExistence(timeout: 5))
        app.buttons["Save meal"].tap()
        XCTAssertTrue(dinner.waitForNonExistence(timeout: 5), "Logged, so it leaves the diary")

        let morning = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Morning walk, ' AND label ENDSWITH ', missed'")).firstMatch
        XCTAssertTrue(morning.exists, "Paw trail's empty dot is a button")
        morning.tap()
        XCTAssertTrue(app.staticTexts["Who walked Yo-Yo?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'For ' AND label ENDSWITH \"'s morning walk\"")).firstMatch.exists)
        app.buttons["Save walk"].tap()
        XCTAssertTrue(morning.waitForNonExistence(timeout: 5), "The dot fills in")
        snapshot("94-trail-caught-up")
    }
}
