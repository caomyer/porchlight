import XCTest

/// A chore's time on the wall (docs/design/phone-shell.md, "A chore's time"): the board puts
/// timed chores first by time, and the editor's "Time" pill sets, clears and edits a time
/// through the time card's popover. At 5:20 pm, with `-sampleChoreTimes`.
@MainActor
final class WallChoreTimeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipUnless(isPad, "The wall's tests run on an iPad")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", UITestClock.at(17, 20), "-sampleChoreTimes", "YES", "-startScreen", "chores"]
        app.launch()
        XCTAssertTrue(app.buttons["Empty the dishwasher"].waitForExistence(timeout: 60))
        return app
    }

    private func snapshot(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTheBoardOrderAndTheEditor() {
        let app = launch()
        let dishwasher = app.buttons["Empty the dishwasher"], bins = app.buttons["Take the bins out"]
        XCTAssertLessThan(dishwasher.frame.minY, bins.frame.minY, "7:00 AM before 7:00 PM")
        // The rest of the first column comes after the timed ones.
        let column = app.buttons.allElementsBoundByIndex.filter {
            abs($0.frame.minX - dishwasher.frame.minX) < 4 && $0.frame.minY > bins.frame.maxY - 1 && ($0.value as? String) == "Not done"
        }
        XCTAssertFalse(column.isEmpty, "untimed chores below the timed ones")
        snapshot("time-20-wall-board", app)

        app.buttons["Open Take the bins out"].tap()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "the chore's sheet")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "7:00 PM")).firstMatch.exists, "which says its time")
        edit.tap()
        let pill = app.buttons["chore-time"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        XCTAssertEqual(pill.value as? String, "7:00 PM")
        snapshot("time-21-wall-editor-set", app)
        app.buttons["chore-time-clear"].tap()
        XCTAssertEqual(pill.value as? String, "Any time")
        snapshot("time-22-wall-editor-unset", app)
        pill.tap()
        let morning = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Morning")).firstMatch
        XCTAssertTrue(morning.waitForExistence(timeout: 5), "the card's suggestions")
        snapshot("time-23-wall-card", app)
        morning.tap()
        XCTAssertTrue(morning.waitForNonExistence(timeout: 5))
        XCTAssertEqual(pill.value as? String, "8:00 AM")
        app.buttons["Save"].tap()
        XCTAssertTrue(pill.waitForNonExistence(timeout: 5))
        XCTAssertLessThan(dishwasher.frame.minY, bins.frame.minY, "7:00 AM before 8:00 AM")
        let first = app.buttons.allElementsBoundByIndex.filter { abs($0.frame.minX - dishwasher.frame.minX) < 4 && ($0.value as? String) == "Not done" }
            .sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(first.prefix(2).map(\.label), ["Empty the dishwasher", "Take the bins out"])
        snapshot("time-24-wall-board-after", app)
    }
}
