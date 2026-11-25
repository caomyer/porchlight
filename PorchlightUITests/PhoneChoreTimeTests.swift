import XCTest

/// A chore's time on the phone (docs/design/phone-shell.md, "A chore's time"): the editor's
/// "Time" pill, unset, with its card open, set and cleared; and Today's order, timed chores
/// first by time, the one whose time has passed in the accent color. At 5:20 pm, with
/// `-sampleChoreTimes`: the dishwasher at 7:00 AM (past) and the bins at 7:00 PM.
@MainActor
final class PhoneChoreTimeTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    override func tearDown() {
        MainActor.assumeIsolated { restoreLightLook() }
        super.tearDown()
    }

    private func launch(dark: Bool = false, _ extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", UITestClock.at(17, 20), "-me", "James", "-sampleChoreTimes", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        waitUntilResponsive(app)
        return app
    }

    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", "Check off \(title)")).firstMatch
    }

    func testTodaysOrderAndTheLateLine() {
        for dark in [false, true] {
            let app = launch(dark: dark)
            let dishwasher = row(app, "Empty the dishwasher"), bins = row(app, "Take the bins out")
            reveal(dishwasher, in: app)
            XCTAssertEqual(dishwasher.value as? String, "7:00 AM")
            XCTAssertEqual(bins.value as? String, "7:00 PM")
            let others = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Check off ")).allElementsBoundByIndex
                .filter { $0.label != dishwasher.label && $0.label != bins.label }
            XCTAssertLessThan(dishwasher.frame.minY, bins.frame.minY, "by time: 7:00 AM before 7:00 PM")
            for other in others { XCTAssertLessThan(bins.frame.maxY, other.frame.minY + 1, "timed first, then \(other.label)") }
            snapshot("time-10-today-\(dark ? "dark" : "light")")
            app.terminate()
        }
    }

    func testSettingClearingAndEditingATime() {
        for dark in [false, true] {
            let app = launch(dark: dark)
            app.buttons["see-all"].tap()
            XCTAssertTrue(app.staticTexts["Pitch in"].waitForExistence(timeout: 5))
            app.buttons["add-chore"].tap()
            XCTAssertTrue(app.staticTexts["New chore"].waitForExistence(timeout: 5))
            type("Water the ferns", into: app.textFields["What needs doing?"], in: app)
            // The keyboard down, so the shots show the sheet.
            let keyboardDone = app.keyboards.buttons["done"]
            if keyboardDone.exists { keyboardDone.tap() }
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            let pill = app.buttons["chore-time"]
            reveal(pill, in: app)
            XCTAssertEqual(pill.value as? String, "Any time", "left alone, any time")
            XCTAssertFalse(app.buttons["chore-time-clear"].exists, "nothing to clear")
            let look = dark ? "dark" : "light"
            snapshot("time-01-unset-\(look)")
            pill.tap()
            let evening = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Evening")).firstMatch
            XCTAssertTrue(evening.waitForExistence(timeout: 5), "the card, with its suggestions")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Morning")).firstMatch.exists)
            XCTAssertTrue(app.buttons["Noon"].exists)
            snapshot("time-02-card-\(look)")
            evening.tap()
            XCTAssertTrue(evening.waitForNonExistence(timeout: 5), "a suggestion sets the time and closes the card")
            XCTAssertEqual(pill.value as? String, "7:00 PM")
            snapshot("time-03-set-\(look)")
            app.buttons["chore-time-clear"].tap()
            XCTAssertEqual(pill.value as? String, "Any time", "the x goes back to any time")
            // Done on an unset time sets the one the card shows.
            pill.tap()
            let done = app.buttons["time-done"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
            XCTAssertTrue(done.waitForNonExistence(timeout: 5))
            XCTAssertEqual(pill.value as? String, "8:00 AM")
            let add = app.buttons["Add chore"]
            reveal(add, in: app)
            add.tap()
            XCTAssertTrue(app.staticTexts["New chore"].waitForNonExistence(timeout: 5))
            app.buttons["Yours"].tap()
            let ferns = row(app, "Water the ferns")
            XCTAssertTrue(ferns.waitForExistence(timeout: 5))
            XCTAssertEqual(ferns.value as? String, "8:00 AM", "its time is its line")
            XCTAssertLessThan(ferns.frame.minY, row(app, "Take the bins out").frame.minY, "8:00 AM comes before 7:00 PM")
            app.terminate()
        }
    }

    func testEditingAChoresTime() {
        let app = launch(["-startScreen", "you", "-debugYouPage", "chores"])
        let bins = app.buttons["chore-Take the bins out"]
        XCTAssertTrue(bins.waitForExistence(timeout: 10))
        bins.tap()
        let pill = app.buttons["chore-time"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        reveal(pill, in: app)
        XCTAssertEqual(pill.value as? String, "7:00 PM", "the chore's own time")
        pill.tap()
        let noon = app.buttons["Noon"]
        XCTAssertTrue(noon.waitForExistence(timeout: 5))
        noon.tap()
        XCTAssertEqual(pill.value as? String, "12:00 PM")
        let save = app.buttons["Save"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(bins.waitForExistence(timeout: 5))
        XCTAssertTrue((bins.label + " " + ((bins.value as? String) ?? "")).contains("12:00 PM"), "the list says the new time: \(bins.label)")
    }
}
