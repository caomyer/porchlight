import XCTest

/// Anything logged can be opened again and fixed: tapping a walk or a meal on
/// Today opens its editor, and the log sheets say when it happened.
@MainActor
final class LoggedEntryTests: XCTestCase {
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Logs a walk, then fixes it from Today's timeline. Works at any hour: sample walks
    /// depend on the time of day, so the test makes its own (10 minutes, a length no
    /// sample walk has) and changes it to 45, which Yo-Yo's card must show at once.
    func testFixingAWalkFromToday() {
        let app = XCUIApplication.porchlight()
        // Pinned to 5:20 pm, so an hour ago is today whenever the suite runs. Which choices
        // the time card offers at each minute of the day is `LogTimeTests` (unit).
        app.launchArguments = ["-sampleHousehold", "-startScreen", "today", "-debugCompanionNow", Self.evening]
        app.launch()

        let log = button(app, containing: "I walked Yo-Yo")
        XCTAssertTrue(log.waitForExistence(timeout: 30))
        log.tap()
        XCTAssertTrue(app.staticTexts["Who walked Yo-Yo?"].waitForExistence(timeout: 5))
        // When it started: a new walk ends now by default; a suggestion sets the time, closes
        // the card and is the one marked when the card opens again.
        let started = app.descendants(matching: .any).matching(identifier: "exact-time").firstMatch
        started.tap()
        XCTAssertTrue(app.buttons["Just got back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Just got back"].isSelected, "A new walk ends now by default")
        let hourAgo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '1 hr ago'")).firstMatch
        XCTAssertTrue(hourAgo.exists, "At 5:20 pm an hour ago is still today")
        hourAgo.tap()
        XCTAssertTrue(hourAgo.waitForNonExistence(timeout: 5), "A suggestion sets the time and closes")
        started.tap()
        XCTAssertTrue(hourAgo.waitForExistence(timeout: 5))
        XCTAssertTrue(hourAgo.isSelected)
        snapshot("52-new-walk-earlier")
        app.buttons["time-done"].tap()
        app.buttons["10 min"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save walk'")).firstMatch.tap()
        // Saving celebrates, and the celebration goes by itself after a few seconds. Wait it
        // out: tapping its button races it, and on a busy simulator the button can be gone by
        // the tap, or come after the test stopped waiting and cover the taps below.
        let done = app.buttons["Back to today"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "Saving a walk celebrates")
        XCTAssertTrue(done.waitForNonExistence(timeout: 15), "The celebration goes by itself")

        let walk = button(app, containing: "walked Yo-Yo · 10 min")
        XCTAssertTrue(walk.waitForExistence(timeout: 10), "The new walk should be a tappable row")
        walk.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForExistence(timeout: 5), "Tapping a logged walk should open it for editing")
        let time = app.descendants(matching: .any).matching(identifier: "exact-time").firstMatch
        XCTAssertTrue(time.exists, "The walk's time shows as a pill")
        time.tap()
        XCTAssertTrue(app.buttons["Just got back"].waitForExistence(timeout: 5), "Today's log suggests quick times")
        snapshot("50-edit-walk")
        app.buttons["time-done"].tap()
        XCTAssertTrue(app.buttons["Just got back"].waitForNonExistence(timeout: 5), "Done with nothing typed keeps the time")

        app.buttons["Mia"].tap()
        app.buttons["45 min"].tap()
        app.buttons["Save changes"].tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForNonExistence(timeout: 5), "Saving should close the editor")
        XCTAssertTrue(button(app, containing: "James & Mia walked Yo-Yo · 45 min").waitForExistence(timeout: 5),
                      "The timeline should show both walkers and the new length")
        // Yo-Yo's card refreshes too, not just the timeline.
        let tile = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' · 45 min'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "The Today card should show the fixed walk")
        snapshot("51-walk-fixed")
    }

    /// The pinned day (`UITestClock`) at 5:20 pm for `-debugCompanionNow`, so nothing here
    /// depends on when the suite runs.
    private static var evening: String {
        UITestClock.at(17, 20)
    }

    func testOpeningMealsFromToday() {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "today"]
        app.launch()

        // From the timeline.
        let row = button(app, containing: "Breakfast · ")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Meals on the timeline should be tappable")
        row.tap()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Tapping a meal should open its detail")
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "time-eaten").firstMatch.exists, "A meal's time can be fixed")
        snapshot("53-edit-meal-time")
        app.buttons["Cancel"].tap()
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(edit.waitForNonExistence(timeout: 5))

        // From the plates card.
        let plate = button(app, containing: "Breakfast: ")
        XCTAssertTrue(plate.waitForExistence(timeout: 5), "Today's plates should open their meal")
        plate.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
    }

    func testFixingAWalkFromTheCompanionPage() {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "companion-1"]
        app.launch()

        let diaryRow = app.buttons.matching(NSPredicate(format: "label CONTAINS ' min'")).firstMatch
        XCTAssertTrue(diaryRow.waitForExistence(timeout: 30), "Diary rows should be tappable")
        diaryRow.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForExistence(timeout: 5))
        app.buttons["Remove"].tap()
        let confirm = app.buttons["Remove walk"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Removing asks first")
        snapshot("54-remove-walk")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForNonExistence(timeout: 5))
    }
}
