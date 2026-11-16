import XCTest

/// The iPhone: picking who you are, Today, one-tap care with undo, the care sheet,
/// catching up, chores, the You sheet, the night look and the largest text size.
/// Runs only on an iPhone simulator (`scripts/test.sh --phone`); the iPad run skips it.
///
/// Time is pinned to 5:20 pm today with `-debugCompanionNow`, so Yo-Yo's evening walk
/// and dinner are open whenever the suite runs. The sample household also missed
/// yesterday's dinner, gives James the leaky faucet, and leaves the vacuuming to anyone.
@MainActor
final class PhoneTests: XCTestCase, PhoneTestHelpers {
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

    private func launch(_ arguments: [String] = [], me: String? = "James") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.evening] + (me.map { ["-me", $0] } ?? []) + arguments
        app.launch()
        return app
    }

    private func logButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Log Yo-Yo's evening walk"]
    }

    // MARK: Who you are

    func testPickingWhoYouAre() {
        let app = launch(me: nil)
        XCTAssertTrue(app.staticTexts["Which one is you?"].waitForExistence(timeout: 60), "A phone without a person asks once")
        XCTAssertFalse(app.buttons["continue-as"].isEnabled, "Nothing is picked yet")
        snapshot("phone-01-who-are-you")
        app.buttons["who-Mia"].tap()
        XCTAssertEqual(app.buttons["continue-as"].label, "Continue as Mia")
        snapshot("phone-02-who-are-you-picked")
        app.buttons["continue-as"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Mia"].waitForExistence(timeout: 5), "Today greets the person picked")
    }

    // MARK: Today

    func testTodayWithSomethingDue() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        XCTAssertTrue(logButton(app).exists, "The open walk leads, one tap away")
        XCTAssertTrue(element(app, beginningWith: "Yo-Yo's dinner wasn't logged yesterday").exists, "Yesterday's missed dinner shows once")
        XCTAssertTrue(app.buttons["Check off Fix the leaky faucet"].exists, "My chores come next")
        snapshot("phone-10-today-due")
        let anyone = app.buttons["Check off Vacuum the living room as yours"]
        reveal(anyone, in: app)
        XCTAssertTrue(anyone.exists, "Then what anyone can take")
        snapshot("phone-11-today-anyone")
        let agenda = app.staticTexts["At home today"]
        reveal(agenda, in: app)
        XCTAssertTrue(agenda.exists, "Then today's calendar, when the phone may read it")
        snapshot("phone-12-today-agenda")
    }

    func testOneTapLogAndUndo() {
        let app = launch()
        let log = logButton(app)
        XCTAssertTrue(log.waitForExistence(timeout: 60))
        app.buttons["Mia"].tap()
        log.tap()
        XCTAssertTrue(app.staticTexts["Evening walk logged"].waitForExistence(timeout: 5), "One tap logs it, with no question")
        XCTAssertTrue(element(app, beginningWith: "With Mia").exists, "Also went adds Mia")
        snapshot("phone-20-logged-toast")
        XCTAssertFalse(log.exists, "The walk is done")
        app.buttons["toast-action"].tap()
        XCTAssertTrue(log.waitForExistence(timeout: 5), "Undo takes the walk back")
        snapshot("phone-21-undone")
    }

    func testCareSheet() {
        let app = launch()
        let more = app.buttons["More details for Yo-Yo's walk"]
        XCTAssertTrue(more.waitForExistence(timeout: 60))
        more.tap()
        XCTAssertTrue(app.staticTexts["Log a walk"].waitForExistence(timeout: 5), "More… opens the care sheet")
        let you = app.buttons.matching(NSPredicate(format: "label == 'You' AND identifier != 'you'")).firstMatch
        XCTAssertTrue(you.isSelected, "Who went starts with you")
        XCTAssertTrue(app.buttons["exact-time"].exists, "The wall's time pill")
        snapshot("phone-30-care-sheet")
        app.buttons["20 min"].tap()
        app.buttons["save-care"].waitToSettle()
        app.buttons["save-care"].tap()
        XCTAssertTrue(app.staticTexts["Walk logged"].waitForExistence(timeout: 5))
        XCTAssertFalse(logButton(app).exists, "The evening walk is filled in")
        snapshot("phone-31-care-sheet-saved")
    }

    func testCatchingUp() {
        let app = launch()
        let banner = element(app, beginningWith: "Yo-Yo's dinner wasn't logged yesterday")
        XCTAssertTrue(banner.waitForExistence(timeout: 60))
        banner.tap()
        XCTAssertTrue(app.staticTexts["When did Yo-Yo eat?"].waitForExistence(timeout: 5), "Catching up asks only when")
        XCTAssertTrue(app.buttons["key-7"].exists, "with the wall's number pad")
        snapshot("phone-40-catch-up")
        app.buttons["save-catch-up"].waitToSettle()
        app.buttons["save-catch-up"].tap()
        XCTAssertTrue(app.staticTexts["Dinner logged"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, beginningWith: "Yo-Yo's dinner wasn't logged yesterday").exists, "It doesn't come back")
        snapshot("phone-41-caught-up")
    }

    func testCheckingChores() {
        let app = launch()
        let faucet = app.buttons["Check off Fix the leaky faucet"]
        XCTAssertTrue(faucet.waitForExistence(timeout: 60))
        faucet.tap()
        XCTAssertTrue(app.staticTexts["Fix the leaky faucet done"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, beginningWith: "Nothing else for you today").waitForExistence(timeout: 5), "All mine done folds into a quiet line")
        snapshot("phone-50-chores-done")
        app.buttons["toast-action"].tap()
        XCTAssertTrue(faucet.waitForExistence(timeout: 5), "Undo puts it back")

        let vacuum = app.buttons["Check off Vacuum the living room as yours"]
        reveal(vacuum, in: app)
        vacuum.tap()
        XCTAssertTrue(app.staticTexts["Vacuum the living room done"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, beginningWith: "Done by you").waitForExistence(timeout: 5), "A shared chore is credited to you")
        snapshot("phone-51-took-shared")
    }

    /// Late in the evening Yo-Yo is all set, and with the faucet fixed nothing is left for James.
    func testAllClear() {
        let app = XCUIApplication()
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let late = String(format: "%04d-%02d-%02dT21:30", parts.year!, parts.month!, parts.day!)
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", late, "-me", "James"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Yo-Yo is all set"].waitForExistence(timeout: 60), "A finished day folds to one line")
        app.buttons["Check off Fix the leaky faucet"].tap()
        XCTAssertTrue(element(app, beginningWith: "Nothing else for you today").waitForExistence(timeout: 5))
        _ = app.buttons["toast-action"].waitForNonExistence(timeout: 10)
        snapshot("phone-15-all-clear")
    }

    // MARK: You

    func testYouSheet() {
        let app = launch()
        let you = app.buttons["you"]
        XCTAssertTrue(you.waitForExistence(timeout: 60))
        you.tap()
        XCTAssertTrue(app.staticTexts["The Lake House"].waitForExistence(timeout: 5), "The household's name")
        XCTAssertTrue(element(app, beginningWith: "James's iPhone, Personal").exists, "This phone's role")
        snapshot("phone-60-you")
        app.buttons["change-me"].waitToSettle()
        app.buttons["change-me"].tap()
        XCTAssertTrue(app.staticTexts["Which one is you?"].waitForExistence(timeout: 5))
        app.buttons["who-Mia"].tap()
        app.buttons["continue-as"].tap()
        XCTAssertTrue(element(app, beginningWith: "This iPhone is Mia").waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Mia"].waitForExistence(timeout: 5))
    }

    func testFoodIsCalm() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        app.tabBars.buttons["Food"].tap()
        XCTAssertTrue(app.staticTexts["Coming to the phone soon"].waitForExistence(timeout: 5), "Food comes next")
        snapshot("phone-70-coming-soon")
        for tab in ["Food", "Lists", "Glow"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.buttons["you"].waitForExistence(timeout: 5), "You is on every tab: \(tab)")
        }
    }

    // MARK: Looks

    func testNightLook() {
        XCUIDevice.shared.appearance = .dark
        let app = launch()
        XCTAssertTrue(logButton(app).waitForExistence(timeout: 60))
        snapshot("phone-80-today-dark")
        app.buttons["More details for Yo-Yo's walk"].tap()
        XCTAssertTrue(app.staticTexts["Log a walk"].waitForExistence(timeout: 5))
        snapshot("phone-81-care-sheet-dark")
    }

    func testLargestText() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let log = logButton(app)
        XCTAssertTrue(log.waitForExistence(timeout: 60))
        reveal(log, in: app)
        XCTAssertTrue(log.isHittable)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(log.frame), "The whole button is on screen: \(log.frame) in \(window)")
        XCTAssertGreaterThanOrEqual(log.frame.width, window.width - 2 * 16 - 2 * 14 - 1, "and it keeps its full width")
        snapshot("phone-90-largest-text")
        let faucet = app.buttons["Check off Fix the leaky faucet"]
        reveal(faucet, in: app)
        XCTAssertTrue(window.contains(faucet.frame))
        snapshot("phone-91-largest-text-chores")
    }
}
