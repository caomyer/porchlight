import XCTest

/// Pitch in (chores and companion care together) and Glow (everyone's stars), through
/// the real screens with sample data. Sample launches never touch real data.
@MainActor
final class PitchInTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
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

    private func text(_ app: XCUIApplication, containing part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }

    /// Opening a chore shows who did it; picking someone else re-credits it on the board.
    func testFixingWhoDidAChore() {
        let app = launch(["-startScreen", "chores"])
        let row = app.buttons["Open Make breakfast"]
        XCTAssertTrue(row.waitForExistence(timeout: 40), "Rows open the chore")
        row.tap()
        XCTAssertTrue(text(app, containing: "James did it").waitForExistence(timeout: 5), "The sheet says who did it")
        snapshot("60-chore-opened")
        app.buttons["Mia did it"].tap()
        XCTAssertTrue(text(app, containing: "Mia did it").waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Mia pitched in"].waitForExistence(timeout: 5), "The board shows someone else pitched in")
        snapshot("61-mia-pitched-in")
    }

    /// Checking off a shared chore asks who did it.
    func testCheckingOffASharedChore() {
        let app = launch(["-startScreen", "chores"])
        let box = app.buttons["Vacuum the living room"]
        XCTAssertTrue(box.waitForExistence(timeout: 40))
        XCTAssertEqual(box.value as? String, "Not done")
        box.tap()
        let james = app.buttons["James"]
        XCTAssertTrue(james.waitForExistence(timeout: 5), "A shared chore asks who did it")
        james.tap()
        XCTAssertTrue(app.staticTexts["Done by James"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Vacuum the living room"].value as? String, "Done")
    }

    /// Companion care is on the board, and checking it opens the companion's log sheet.
    func testLoggingCareFromTheBoard() {
        let app = launch(["-startScreen", "chores"])
        let walk = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Walk Yo-Yo'")).firstMatch
        XCTAssertTrue(walk.waitForExistence(timeout: 40), "Yo-Yo's walks sit on the board")
        let feed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Feed Yo-Yo' AND value == 'Not done'")).firstMatch
        if feed.exists {
            feed.tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save'")).firstMatch.waitForExistence(timeout: 5), "Care is logged with the companion's own sheet")
        } else {
            walk.tap()
            XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 5), "Done care opens its log to fix it")
        }
        snapshot("62-care-from-board")
    }

    /// A reached reward is cashed in on Glow and shows up in "Lately".
    func testCashingInOnGlow() {
        let app = launch(["-startScreen", "glow"])
        XCTAssertTrue(text(app, containing: "lit the porch").waitForExistence(timeout: 40), "Glow tells the week's story")
        snapshot("63-glow")
        let cashIn = app.buttons["Cash in Fancy coffee run"]
        XCTAssertTrue(cashIn.waitForExistence(timeout: 5), "A reached reward can be cashed in")
        cashIn.tap()
        XCTAssertTrue(app.staticTexts["Cashed in Fancy coffee run"].waitForExistence(timeout: 5), "Lately shows the cash-in")
        XCTAssertFalse(app.buttons["Cash in Fancy coffee run"].exists, "The reward starts a new round")
        snapshot("64-glow-cashed-in")
    }

    /// A new chore picks how it repeats and when it starts, and the picker reads it back.
    func testNewChoreWithAStartDay() {
        let app = launch(["-startScreen", "chores", "-homeSheet", "newChore"])
        let title = app.textFields["What needs doing?"]
        XCTAssertTrue(title.waitForExistence(timeout: 40))
        // The sheet fades and scales in; a tap computed mid-animation lands on a field
        // that has moved, and XCTest reports it as lost after interruption handling.
        title.waitToSettle()
        title.tap()
        title.typeText("Water the ferns\n")
        app.buttons["Some days"].tap()
        let summary = app.staticTexts["repeatSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue((summary.label).hasPrefix("Every "), "The picker reads back the pattern: \(summary.label)")
        app.buttons["Monthly"].tap()
        XCTAssertTrue(summary.label.hasPrefix("Monthly on the "), summary.label)
        app.buttons["Every day"].tap()
        snapshot("65-new-chore-repeat")
        app.buttons["Add chore"].tap()
        XCTAssertTrue(app.buttons["Open Water the ferns"].waitForExistence(timeout: 5), "A daily chore starting today is on the board")
    }
}
