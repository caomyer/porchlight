import XCTest

/// Notifications in the You sheet: saying why before iOS asks, the turned-off state, and
/// choosing which routines remind. `-notificationAccess` pretends each permission state, so
/// the system prompt never shows. Runs only on an iPhone (`scripts/test.sh --phone`).
@MainActor
final class PhoneRemindersTests: XCTestCase, PhoneTestHelpers {
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

    /// Opens the Notifications page with the given pretend permission.
    private func openNotifications(_ access: String, _ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.evening, "-me", "James", "-notificationAccess", access] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["you"].waitForExistence(timeout: 60))
        app.buttons["you"].tap()
        let row = app.buttons["notifications"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // Below the household, storage and people now, so scrolled into view first, then
        // settled. The other way round, the row is off screen and never settles: twenty looks
        // at the screen, 54 of this page's 147 seconds on a hosted Mac in the night look.
        reveal(row, in: app)
        row.waitToSettle()
        row.tap()
        XCTAssertTrue(app.navigationBars.buttons["You"].waitForExistence(timeout: 5), "On the Notifications page")
        return app
    }

    func testSaysWhyBeforeAsking() {
        let app = openNotifications("notDetermined")
        XCTAssertTrue(app.staticTexts["Remind you about your routines?"].exists, "What reminders are, before iOS asks")
        snapshot("e2-10-ask")
        app.buttons["allow-reminders"].tap()
        XCTAssertTrue(app.buttons["remind-chores"].waitForExistence(timeout: 5), "Allowed: the choices")
    }

    func testTurnedOff() {
        let app = openNotifications("denied")
        XCTAssertTrue(app.staticTexts["Notifications are turned off"].exists)
        XCTAssertTrue(app.buttons["open-settings"].exists, "One way to fix it")
        snapshot("e2-11-denied")
    }

    func testChoosingReminders() {
        let app = openNotifications("allowed")
        let evening = app.buttons["remind-Yo-Yo · evening walk"]
        XCTAssertTrue(evening.waitForExistence(timeout: 5), "Each routine's slots are listed")
        XCTAssertTrue(app.navigationBars.buttons["You"].exists, "Back goes to You")
        XCTAssertEqual(evening.label, "Yo-Yo · evening walk: Off", "Nothing reminds until chosen")
        evening.tap()
        app.buttons["When it opens, 5pm"].tap()
        XCTAssertTrue(app.buttons["Yo-Yo · evening walk: 5-8pm · when it opens"].waitForExistence(timeout: 5))
        let chores = app.buttons["remind-chores"]
        XCTAssertEqual(chores.value as? String, "On")
        chores.tap()
        XCTAssertEqual(chores.value as? String, "Off")
        chores.tap()
        XCTAssertEqual(chores.value as? String, "On")
        sleep(1)
        snapshot("e2-12-choices")
    }

    /// Delivery and actions, with real permission and a reminder a few seconds out. iOS
    /// delivery timing isn't reliable enough for the suite, so this runs only when asked:
    /// `TEST_RUNNER_PORCHLIGHT_DELIVERY=1 xcodebuild test ... -only-testing:PorchlightUITests/PhoneRemindersTests/testDeliveryByHand`.
    func testDeliveryByHand() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PORCHLIGHT_DELIVERY"] == "1", "Run by hand")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // Real permission: ask from the Notifications page and allow.
        let app = openNotifications("real")
        if app.buttons["allow-reminders"].exists {
            app.buttons["allow-reminders"].tap()
            let allow = springboard.alerts.buttons["Allow"]
            XCTAssertTrue(allow.waitForExistence(timeout: 10), "iOS asks once")
            allow.tap()
        }
        XCTAssertTrue(app.buttons["remind-chores"].waitForExistence(timeout: 10))
        app.terminate()

        // A reminder 20 seconds out, then quit, so the action has to launch the app.
        let quiet = XCUIApplication.porchlight()
        quiet.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.evening, "-me", "James", "-debugReminderIn", "20"]
        quiet.launch()
        XCTAssertTrue(quiet.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        sleep(8)
        quiet.terminate()
        XCUIDevice.shared.press(.home)

        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Yo-Yo'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 40), "The reminder is delivered")
        snapshot("c1-10-reminder")
        let log = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'I '")).firstMatch
        // The banner can still be sliding in; press until its actions open.
        for _ in 0..<3 where !log.exists {
            banner.waitToSettle()
            banner.press(forDuration: 1.5)
            _ = log.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(log.exists, "Its actions show on a long press")
        snapshot("c1-11-actions")
        log.tap()
        let logged = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Logged:'")).firstMatch
        XCTAssertTrue(logged.waitForExistence(timeout: 30), "With the app closed, the action logs and says so")
        snapshot("c1-12-logged")
    }

    /// Two households' reminders arrive, each named (journey A5, `a5notif`). Delivery by hand,
    /// like `testDeliveryByHand`: `TEST_RUNNER_PORCHLIGHT_DELIVERY=1` with
    /// `-only-testing:PorchlightUITests/PhoneRemindersTests/testNamedRemindersByHand`, after
    /// notifications were allowed once. `TEST_RUNNER_PORCHLIGHT_DARK=1` shoots the night look.
    func testNamedRemindersByHand() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PORCHLIGHT_DELIVERY"] == "1", "Run by hand")
        let dark = ProcessInfo.processInfo.environment["PORCHLIGHT_DARK"] == "1"
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-sampleSecondHousehold", "-debugCompanionNow", Self.evening, "-me", "James", "-debugReminderIn", "15"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        sleep(6)
        app.terminate()
        XCUIDevice.shared.press(.home)
        let lake = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'The Lake House ·'")).firstMatch
        let rosas = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS \"Grandma Rosa's ·\"")).firstMatch
        // In DEBUG each household's comes ten seconds after the one before, so each has its own banner.
        let shown = NSPredicate(format: "exists == true AND hittable == true")
        expectation(for: shown, evaluatedWith: lake)
        waitForExpectations(timeout: 40)
        sleep(1)
        snapshot(dark ? "a5-41-named-reminder-dark" : "a5-40-named-reminder")
        expectation(for: shown, evaluatedWith: rosas)
        waitForExpectations(timeout: 40)
        XCTAssertFalse(lake.isHittable, "Grandma Rosa's banner is the one showing")
        snapshot(dark ? "a5-43-named-reminder-other-dark" : "a5-42-named-reminder-other")
    }

    /// The choices in the night look at the largest text size, in one launch: a look costs a
    /// launch and, for the night look, quitting the app twice more, so the two looks of this
    /// one page share it.
    func testLooks() {
        XCUIDevice.shared.appearance = .dark
        let app = openNotifications("allowed", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let evening = app.buttons["remind-Yo-Yo · evening walk"]
        XCTAssertTrue(evening.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(evening.frame), "The choice is whole on screen")
        XCTAssertTrue(app.buttons["remind-chores"].exists)
        snapshot("e2-80-choices-largest-dark")
    }
}
