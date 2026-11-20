import XCTest

/// Catching up on a slot nobody logged opens the same care sheet as any other log, from
/// Today's banner and from a companion's week: filled in for that slot at its usual time,
/// with who went, how long and the rest, saved the same way.
/// Runs only on an iPhone (`scripts/test.sh --phone`).
///
/// Time is pinned to 5:20 pm today, like PhoneTests. Today's morning walk is taken off
/// first, so the morning is late and Today's banner asks about it.
@MainActor
final class PhoneCatchUpTests: XCTestCase, PhoneTestHelpers {
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

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.evening, "-me", "James"] + arguments
        app.launch()
        return app
    }

    private var morningTile: (XCUIApplication) -> XCUIElement { { $0.buttons["slot-Yo-Yo-0"] } }

    /// Takes today's morning walk off, so the morning slot is late and Today's banner asks.
    private func forgetMorningWalk(_ app: XCUIApplication) {
        let tile = morningTile(app)
        XCTAssertTrue(tile.waitForExistence(timeout: 60))
        reveal(tile, in: app)
        tile.waitToSettle()
        tile.tap()
        let remove = app.buttons["remove-care"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        reveal(remove, in: app)
        remove.tap()
        app.buttons["Remove walk"].tap()
        XCTAssertTrue(tile.waitForNonExistence(timeout: 10), "The morning is open again")
    }

    private func banner(_ app: XCUIApplication) -> XCUIElement {
        element(app, beginningWith: "Yo-Yo's morning walk wasn't logged")
    }

    /// Opens the catch-up from Today's banner.
    private func openFromBanner(_ app: XCUIApplication) {
        forgetMorningWalk(app)
        let banner = banner(app)
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Today asks about the morning")
        banner.tap()
        XCTAssertTrue(app.staticTexts["Log a walk"].waitForExistence(timeout: 5), "The same care sheet as any walk")
        XCTAssertTrue(app.staticTexts["For today's morning walk"].exists, "for the slot nobody logged")
    }

    func testCatchingUpFromTodaysBanner() {
        let app = launch()
        openFromBanner(app)
        XCTAssertTrue(app.buttons["went-James"].isSelected, "Who went starts with you")
        XCTAssertTrue(app.buttons["exact-time"].exists, "When, at the slot's usual time")
        snapshot("catch-up-10-banner-sheet")
        // The card's "Also went" behind the sheet has a Mia too: the sheet's is "went-Mia".
        let mia = app.buttons["went-Mia"]
        reveal(mia, in: app)
        mia.tap()
        let longer = app.buttons["45 min"]
        reveal(longer, in: app)
        longer.tap()
        let save = app.buttons["save-care"]
        reveal(save, in: app)
        save.waitToSettle()
        save.tap()
        XCTAssertTrue(app.staticTexts["Morning walk logged"].waitForExistence(timeout: 5), "A toast says so")
        XCTAssertTrue(morningTile(app).waitForExistence(timeout: 5), "The morning shows as logged")
        XCTAssertFalse(banner(app).exists, "The banner is gone")
        snapshot("catch-up-11-banner-saved")

        // Saved as chosen: both walkers, and the length.
        let tile = morningTile(app)
        reveal(tile, in: app)
        tile.waitToSettle()
        tile.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["went-James"].isSelected && app.buttons["went-Mia"].isSelected, "Credited to both")
        XCTAssertTrue(app.buttons["45 min"].isSelected)
    }

    func testCatchingUpFromTheWeek() {
        let app = launch()
        app.buttons["week-Yo-Yo"].tap()
        let missed = element(app, beginningWith: "Morning walk wasn't logged")
        XCTAssertTrue(missed.waitForExistence(timeout: 10), "The week shows the walk nobody logged")
        reveal(missed, in: app)
        missed.tap()
        XCTAssertTrue(app.staticTexts["Log a walk"].waitForExistence(timeout: 5), "The same care sheet as any walk")
        XCTAssertTrue(element(app, beginningWith: "For ").exists, "for that day's morning walk")
        XCTAssertTrue(app.buttons["went-James"].isSelected)
        snapshot("catch-up-20-week-sheet")
        let mia = app.buttons["went-Mia"]
        reveal(mia, in: app)
        mia.tap()
        let save = app.buttons["save-care"]
        reveal(save, in: app)
        save.waitToSettle()
        save.tap()
        XCTAssertTrue(app.staticTexts["Morning walk logged"].waitForExistence(timeout: 5))
        XCTAssertTrue(missed.waitForNonExistence(timeout: 5), "The missed mark is filled in")
        snapshot("catch-up-21-week-saved")
    }

    /// The catch-up sheet in the night look and at the largest text size.
    func testCatchingUpLooks() {
        XCUIDevice.shared.appearance = .dark
        var app = launch()
        openFromBanner(app)
        snapshot("catch-up-30-dark")
        app.terminate()

        XCUIDevice.shared.appearance = .light
        app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openFromBanner(app)
        snapshot("catch-up-40-largest")
        let save = app.buttons["save-care"]
        reveal(save, in: app)
        snapshot("catch-up-41-largest-save")
    }
}
