import XCTest

/// Everything the household does shows on Today and on the calendar, and opens the same
/// sheet wherever it is tapped: chores on Today, walks, feeds and meals in the calendar grid,
/// chores in the calendar's Pitch in lane. Sample launches never touch real data.
@MainActor
final class DayAtAGlanceTests: XCTestCase {
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
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
    }

    private func button(_ app: XCUIApplication, beginningWith part: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", part)).firstMatch
    }

    /// Today's Pitch in card checks a shared chore off (asking who did it), and the
    /// timeline then shows it as done.
    func testCheckingOffAChoreOnToday() {
        let app = launch(["-startScreen", "today"])
        let box = app.buttons["Vacuum the living room"]
        XCTAssertTrue(box.waitForExistence(timeout: 40), "Today lists the chores still to do")
        XCTAssertEqual(box.value as? String, "Not done")
        box.tap()
        let james = app.buttons["James"]
        XCTAssertTrue(james.waitForExistence(timeout: 5), "A shared chore asks who did it")
        james.tap()
        XCTAssertTrue(app.buttons["Vacuum the living room, done"].waitForExistence(timeout: 5), "It moves to the done chips")
        XCTAssertTrue(button(app, beginningWith: "Vacuum the living room").exists)
        XCTAssertTrue(app.staticTexts["James pitched in · +2 stars"].waitForExistence(timeout: 5), "The timeline shows who did it")
        snapshot("70-today-chore-done")
    }

    /// A chore row on Today opens the same sheet as on the board.
    func testOpeningAChoreFromToday() {
        let app = launch(["-startScreen", "today"])
        let row = app.buttons["Open Fix the leaky faucet"]
        XCTAssertTrue(row.waitForExistence(timeout: 40))
        row.tap()
        XCTAssertTrue(app.staticTexts["Who did it?"].waitForExistence(timeout: 5), "The chore's sheet opens")
        snapshot("71-today-chore-opened")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Who did it?"].waitForNonExistence(timeout: 5))
    }

    /// Walks and meals sit in the week grid at their times and open like on Today.
    func testMomentsInTheWeek() {
        let app = launch(["-startScreen", "calendar", "-calendarMode", "week"])
        let walk = button(app, beginningWith: "James walked Yo-Yo")
        XCTAssertTrue(walk.waitForExistence(timeout: 40), "The morning walk is in the week grid")
        snapshot("72-week-moments")
        walk.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForExistence(timeout: 5), "A walk opens to be fixed")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForNonExistence(timeout: 5))

        let meal = button(app, beginningWith: "Breakfast · Avocado toast")
        XCTAssertTrue(meal.exists, "Meals are in the week grid too")
        meal.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5), "A meal opens its detail")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForNonExistence(timeout: 5))
    }

    /// The Pitch in lane shows each day's chores and opens them; the day view names them.
    func testChoresInTheCalendar() {
        let app = launch(["-startScreen", "calendar", "-calendarMode", "day"])
        let open = app.buttons["Run the dishwasher, to do"]
        XCTAssertTrue(open.waitForExistence(timeout: 40), "The day view lists the day's chores")
        XCTAssertTrue(button(app, beginningWith: "Make breakfast, done by").exists, "Done chores say who did them")
        snapshot("73-day-chores")
        open.tap()
        XCTAssertTrue(app.staticTexts["Who did it?"].waitForExistence(timeout: 5), "A chore opens its sheet")
        app.buttons["Mia did it"].tap()
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Run the dishwasher, done by Mia"].waitForExistence(timeout: 5), "The lane updates")
    }
}
