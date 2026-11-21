import XCTest

/// The phone's everyday pages and tabs: several companions, a companion's week, Pitch in
/// and adding a chore, Lists and dinners, Glow and cashing in, the next 7 days and the
/// calendars on this phone. Each new tab is also shot in the night look and at the
/// largest text size. Runs only on an iPhone (`scripts/test.sh --phone`).
///
/// Time is pinned to 5:20 pm today, like PhoneTests.
@MainActor
final class PhoneTabsTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    override func tearDown() {
        MainActor.assumeIsolated { restoreLightLook() }
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
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        return app
    }

    // MARK: Companions

    func testSeveralCompanionsGoToAGrid() {
        let app = launch(["-sampleCompanions", "3"])
        XCTAssertTrue(app.buttons["week-Yo-Yo"].exists)
        XCTAssertTrue(app.buttons["week-Miso"].exists)
        XCTAssertTrue(app.buttons["week-Fiddle fig"].exists)
        XCTAssertTrue(app.buttons["Log Fiddle fig's water"].exists, "Each card keeps its one tap")
        snapshot("m3-10-grid")
    }

    func testCompanionWeek() {
        let app = launch()
        app.buttons["week-Yo-Yo"].tap()
        XCTAssertTrue(element(app, beginningWith: "Yo-Yo's week").waitForExistence(timeout: 5), "Tapping a card opens its week")
        XCTAssertTrue(element(app, beginningWith: "Paw trail").exists)
        XCTAssertTrue(element(app, beginningWith: "Walk diary").exists)
        snapshot("m3-11-week")
        let milestones = element(app, beginningWith: "Little milestones")
        reveal(milestones, in: app)
        XCTAssertTrue(element(app, beginningWith: "Walker of the week").exists)
        snapshot("m3-12-week-walkers")
        let missed = element(app, beginningWith: "Morning walk wasn't logged")
        reveal(missed, in: app)
        missed.tap()
        XCTAssertTrue(element(app, beginningWith: "For ").waitForExistence(timeout: 5), "A missed slot in the diary is caught up on")
        let save = app.buttons["save-care"]
        reveal(save, in: app)
        save.waitToSettle()
        save.tap()
        XCTAssertTrue(app.staticTexts["Morning walk logged"].waitForExistence(timeout: 5))
    }

    // MARK: Pitch in

    func testPitchInAndAddingAChore() {
        let app = launch()
        app.buttons["see-all"].tap()
        XCTAssertTrue(app.staticTexts["Pitch in"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, beginningWith: "This week ·").exists)
        snapshot("m3-20-pitch-in-yours")
        app.buttons["Open"].tap()
        XCTAssertTrue(app.buttons["Check off Vacuum the living room as yours"].waitForExistence(timeout: 5))
        app.buttons["Everyone"].tap()
        XCTAssertTrue(element(app, beginningWith: "Mia,").waitForExistence(timeout: 5), "Everyone's chores, Mia's included")
        snapshot("m3-21-pitch-in-everyone")
        app.buttons["add-chore"].tap()
        XCTAssertTrue(app.staticTexts["New chore"].waitForExistence(timeout: 5), "The wall's chore editor, as a phone sheet")
        type("Wash the car", into: app.textFields["What needs doing?"], in: app)
        app.buttons["Just once"].tap()
        snapshot("m3-22-add-chore")
        app.buttons["Add chore"].tap()
        XCTAssertTrue(app.staticTexts["New chore"].waitForNonExistence(timeout: 5))
        app.buttons["Yours"].tap()
        XCTAssertTrue(app.buttons["Check off Wash the car"].waitForExistence(timeout: 5), "It is mine, today")
    }

    // MARK: Lists

    func testListsAndDinners() {
        let app = launch()
        // Opened as the Groceries widget opens it: `porchlight://lists`.
        app.open(URL(string: "porchlight://lists")!)
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 10), "The widget's link opens Lists")
        XCTAssertTrue(app.tabBars.buttons["Lists"].isSelected)
        XCTAssertTrue(app.staticTexts["PRODUCE"].exists, "Groceries go by aisle")
        type("Lemons", into: app.textFields["add-item"], in: app)
        app.buttons["add-item-button"].tap()
        XCTAssertTrue(app.buttons["Lemons"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.buttons["Lemons"].value as? String)?.contains("added by you") == true, "Credited to me")
        app.buttons["Lemons"].tap()
        XCTAssertTrue((app.buttons["Lemons"].value as? String)?.hasPrefix("Checked") == true)
        snapshot("m3-30-groceries")

        app.buttons["This week's dinners"].tap()
        XCTAssertTrue(app.staticTexts["Dinners"].waitForExistence(timeout: 5))
        snapshot("m3-31-dinners")
        let needs = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add what Taco Tuesday needs'")).firstMatch
        needs.tap()
        let text = app.textFields["needs"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        type("tortillas, limes", into: text, in: app)
        snapshot("m3-32-dinner-needs")
        app.buttons["add-needs"].tap()
        XCTAssertTrue(app.staticTexts["2 items added to groceries"].waitForExistence(timeout: 5), "The toast shows once the sheet has closed")
        // 8 open items, then Lemons (checked off) and these two.
        XCTAssertTrue(app.buttons["Groceries · 10"].exists, "Both went on the groceries")
        app.buttons["Groceries · 10"].tap()
        XCTAssertTrue(app.buttons["Tortillas"].waitForExistence(timeout: 5))
        // And the other widgets' link goes back to Today.
        app.open(URL(string: "porchlight://today")!)
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 10), "porchlight://today opens Today")
    }

    // MARK: Glow

    func testGlowAndCashingIn() {
        let app = launch()
        app.tabBars.buttons["Glow"].tap()
        XCTAssertTrue(element(app, beginningWith: "Saving for").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, beginningWith: "Everyone,").exists)
        snapshot("m3-40-glow")
        let cashIn = app.buttons["Cash in Fancy coffee run"]
        reveal(cashIn, in: app)
        cashIn.tap()
        XCTAssertTrue(app.staticTexts["Cash in Fancy coffee run?"].waitForExistence(timeout: 5), "It asks once")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'stars from you'")).firstMatch.exists, "It names who earned it")
        snapshot("m3-41-cash-in")
        app.buttons["confirm-cash-in"].waitToSettle()
        app.buttons["confirm-cash-in"].tap()
        XCTAssertTrue(app.staticTexts["Fancy coffee run!"].waitForExistence(timeout: 5), "This phone celebrates")
        snapshot("m3-42-celebration")
        app.buttons["celebration-done"].tap()
        XCTAssertFalse(app.buttons["Cash in Fancy coffee run"].exists, "It starts saving again")
    }

    // MARK: Calendars

    func testChoosingCalendars() {
        let app = launch(["-calendarAccess", "notDetermined"])
        let choose = app.buttons["choose-calendars"]
        reveal(choose, in: app)
        XCTAssertTrue(choose.exists, "No calendars yet: one row to choose them")
        choose.tap()
        XCTAssertTrue(app.staticTexts["Show your calendars on Today"].waitForExistence(timeout: 5), "Why, before the system asks")
        snapshot("m3-60-calendars-ask")
        app.buttons["allow-calendars"].tap()
        let work = app.buttons["sharing-Work"]
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        XCTAssertEqual(work.label, "Work is shared as Busy only")
        app.buttons["sharing-Mia"].tap()
        app.buttons["Just me"].tap()
        XCTAssertTrue(app.buttons["Mia is shared as Just me"].waitForExistence(timeout: 5))
        snapshot("m3-61-calendars")
    }

    // MARK: Fixing a log

    /// Opens Today's done morning walk to fix, as tapping a logged walk does on the wall.
    private func openMorningWalk(_ app: XCUIApplication) {
        let tile = app.buttons["slot-Yo-Yo-0"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "A done slot is a button")
        reveal(tile, in: app)
        tile.waitToSettle()
        tile.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForExistence(timeout: 5), "It opens the walk to fix")
    }

    /// Taps Save changes, in view and settled, and checks the sheet closes. It closes as soon
    /// as the fix passes the rules, before the write; a busy simulator can still take a few
    /// seconds to draw that.
    private func saveFix(_ app: XCUIApplication) {
        let save = app.buttons["save-care"]
        reveal(save, in: app)
        save.waitToSettle()
        save.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForNonExistence(timeout: 10), "Saving closes the sheet")
    }

    /// Mirrors the wall's `LoggedEntryTests.testFixingAWalkFromToday`: fix a walk from
    /// Today, see it saved, then remove it.
    func testFixingAWalkFromToday() {
        let app = launch()
        openMorningWalk(app)
        XCTAssertTrue(app.staticTexts["Fix who, when or how it went"].exists)
        // "You" is also the avatar button behind the sheet; the pill is the selected one.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'You' AND selected == true")).firstMatch.exists, "Who went is filled in as logged")
        snapshot("edit-10-today")
        let longer = app.buttons["45 min"]
        reveal(longer, in: app)
        longer.tap()
        saveFix(app)

        openMorningWalk(app)
        XCTAssertTrue(app.buttons["45 min"].isSelected, "The fix was saved")
        let remove = app.buttons["remove-care"]
        reveal(remove, in: app)
        remove.tap()
        let confirm = app.buttons["Remove walk"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Removing asks first")
        XCTAssertTrue(app.buttons["Keep it"].exists)
        snapshot("edit-11-remove")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForNonExistence(timeout: 10), "Removing closes the sheet")
        XCTAssertTrue(app.buttons["slot-Yo-Yo-0"].waitForNonExistence(timeout: 5), "The morning slot is open again")
    }

    /// Mirrors `LoggedEntryTests.testFixingAWalkFromTheCompanionPage`: a diary row opens
    /// its walk, and "Keep it" backs out of removing.
    func testFixingAWalkFromTheWeek() {
        let app = launch()
        app.buttons["week-Yo-Yo"].tap()
        XCTAssertTrue(element(app, beginningWith: "Walk diary").waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS ' min'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Diary rows are buttons")
        let before = row.label
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForExistence(timeout: 5))
        snapshot("edit-20-week")
        let remove = app.buttons["remove-care"]
        reveal(remove, in: app)
        remove.tap()
        XCTAssertTrue(app.buttons["Remove walk"].waitForExistence(timeout: 5))
        app.buttons["Keep it"].tap()
        XCTAssertTrue(app.buttons["save-care"].waitForExistence(timeout: 5), "Keeping it goes back to saving")
        remove.tap()
        app.buttons["Remove walk"].tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons[before].exists, "The walk is gone from the diary")
    }

    /// A shared screen fixes any walk too, crediting whoever is picked, as the wall does.
    func testFixingAWalkOnASharedScreen() {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.evening, "-device.role", "sharedScreen"]
        app.launch()
        openMorningWalk(app)
        XCTAssertTrue(app.buttons["James"].isSelected, "Who went, by name, with no \"You\"")
        saveFix(app)
    }

    /// The real fix sheet at the largest text size, for what only the real sheet shows: the
    /// time pill among everything else on it, and Save changes within reach by scrolling.
    /// How the sheet looks in the night look and at the largest size, new, fixing and
    /// catching up, is `PocketCareSheetScreenTests` (unit bundle), which hosts and draws it.
    func testFixingAWalkLooks() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openMorningWalk(app)
        checkTimePill(app)
        snapshot("edit-40-today-largest")
        let save = app.buttons["save-care"]
        reveal(save, in: app)
        XCTAssertTrue(save.isHittable, "Save changes is reachable at the largest size")
        snapshot("edit-41-save-largest")
    }

    /// The pill's time is set large enough to read at this size, and it sits clear of its label.
    private func checkTimePill(_ app: XCUIApplication) {
        let pill = app.buttons["exact-time"]
        let started = app.staticTexts["Started"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5) && started.exists)
        XCTAssertGreaterThan(pill.frame.height, 60, "the pill grows with the text: \(pill.frame)")
        XCTAssertFalse(pill.frame.intersects(started.frame), "and never overlaps \"Started\"")
        XCTAssertLessThanOrEqual(pill.frame.maxX, app.windows.firstMatch.frame.maxX, "nor runs off the screen")
    }

    // MARK: Looks

    /// The real tabs in the night look at the largest text size, in one launch, for what only
    /// they show: the list's field and the cash-in button whole on the real screen with its
    /// tab bar, cashing in through to the celebration, and the next 7 days reached from
    /// Today. How Lists, Glow and Pitch in look and fit in each look is
    /// `PocketTabsScreenTests` (unit bundle), and a companion's week `PocketWeekScreenTests`;
    /// this class launched twice to photograph them.
    func testLooks() {
        XCUIDevice.shared.appearance = .dark
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let window = app.windows.firstMatch.frame
        app.tabBars.buttons["Lists"].tap()
        let field = app.textFields["add-item"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(window.contains(field.frame))
        snapshot("m3-90-lists-largest-dark")

        app.tabBars.buttons["Glow"].tap()
        let cashIn = app.buttons["Cash in Fancy coffee run"]
        reveal(cashIn, in: app)
        XCTAssertTrue(window.contains(cashIn.frame), "The cash-in button is whole on screen")
        snapshot("m3-91-glow-largest-dark")
        cashIn.tap()
        let confirm = app.buttons["confirm-cash-in"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        reveal(confirm, in: app)
        confirm.waitToSettle()
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Fancy coffee run!"].waitForExistence(timeout: 5))
        snapshot("m3-83-celebration-largest-dark")
        let done = app.buttons["celebration-done"]
        reveal(done, in: app)
        done.tap()

        app.tabBars.buttons["Today"].tap()
        let next = app.buttons["next-7-days"]
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.staticTexts["Next 7 days"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TODAY"].exists, "Grouped by day")
        snapshot("m3-94-next-7-days-largest-dark")
    }

    /// Every tab, scrolled, keeps paper under the status bar, at the usual size and the largest.
    func testPaperUnderTheStatusBar() {
        for size in ["", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = launch(size.isEmpty ? [] : ["-UIPreferredContentSizeCategoryName", size])
            for tab in ["Today", "Food", "Lists", "Glow"] {
                app.tabBars.buttons[tab].tap()
                Thread.sleep(forTimeInterval: 0.5)
                XCTAssertTrue(app.buttons["you"].exists, "You is on every tab: \(tab)")
                expectPaperUnderStatusBar(app, "m3-95-\(tab.lowercased())-scrolled\(size.isEmpty ? "" : "-largest")")
            }
            app.terminate()
        }
    }

}
