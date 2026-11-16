import XCTest

/// Notifications in the You sheet: saying why before iOS asks, the turned-off state, and
/// choosing which routines remind. `-notificationAccess` pretends each permission state, so
/// the system prompt never shows. Runs only on an iPhone (`scripts/test.sh --phone`).
@MainActor
final class PhoneRemindersTests: XCTestCase {
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

    /// Opens the Notifications page with the given pretend permission.
    private func openNotifications(_ access: String, _ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.evening, "-me", "James", "-notificationAccess", access] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["you"].waitForExistence(timeout: 60))
        app.buttons["you"].tap()
        let row = app.buttons["notifications"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.waitToSettle()
        row.tap()
        XCTAssertTrue(app.staticTexts["Notifications"].waitForExistence(timeout: 5))
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        let quiet = XCUIApplication()
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

    func testNightLook() {
        XCUIDevice.shared.appearance = .dark
        let app = openNotifications("allowed")
        XCTAssertTrue(app.buttons["remind-chores"].waitForExistence(timeout: 5))
        snapshot("e2-80-choices-dark")
    }

    func testLargestText() {
        let app = openNotifications("allowed", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let evening = app.buttons["remind-Yo-Yo · evening walk"]
        XCTAssertTrue(evening.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(evening.frame), "The choice is whole on screen")
        snapshot("e2-90-choices-largest")
    }
}
