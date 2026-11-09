import XCTest

/// A brand-new household's first run against the real calendar store: onboarding,
/// the iPadOS calendar permission prompt, and giving each calendar to a person.
/// `-resetData` uses the sample storage sandbox, so real data is never touched.
/// Run after `xcrun simctl privacy <udid> reset calendar com.mingyucao.porchlight`
/// so the permission prompt appears.
@MainActor
final class FirstRunTests: XCTestCase {
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testOnboardingWithRealCalendarAccess() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetData"]
        app.launch()

        let household = app.textFields["e.g. The Lake House"]
        XCTAssertTrue(household.waitForExistence(timeout: 30))
        household.tap()
        household.typeText("Test House\n")

        let firstName = app.textFields["Name"].firstMatch
        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        firstName.tap()
        firstName.typeText("James")
        app.buttons["Add someone"].tap()
        let secondName = app.textFields.matching(identifier: "Name").element(boundBy: 1)
        XCTAssertTrue(secondName.waitForExistence(timeout: 5))
        secondName.typeText("Mia")
        app.buttons["Continue"].tap()

        let allow = app.buttons["Allow calendar access"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "The calendars step should ask for access")
        snapshot("30-calendars-before-access")
        allow.tap()

        // The system prompt belongs to SpringBoard, not the app.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let fullAccess = springboard.alerts.buttons["Allow Full Access"]
        if fullAccess.waitForExistence(timeout: 10) {
            snapshot("31-calendar-permission-prompt")
            fullAccess.tap()
        } else {
            let ok = springboard.alerts.buttons["OK"]
            XCTAssertTrue(ok.waitForExistence(timeout: 5), "iPadOS should ask for calendar access")
            ok.tap()
        }

        let owner = app.buttons.matching(NSPredicate(format: "label CONTAINS ' belongs to '")).firstMatch
        XCTAssertTrue(owner.waitForExistence(timeout: 15), "The iPad's calendars should be listed after access is granted")
        let calendarName = String(owner.label.components(separatedBy: " belongs to ").first ?? "")
        snapshot("32-calendars-listed")

        owner.tap()
        let mia = app.buttons["Mia"]
        XCTAssertTrue(mia.waitForExistence(timeout: 5), "The owner menu should list the household's people")
        mia.tap()
        let assigned = app.buttons["\(calendarName) belongs to Mia"]
        XCTAssertTrue(assigned.waitForExistence(timeout: 5), "\(calendarName) should now belong to Mia")
        snapshot("33-calendar-assigned")

        for _ in 0..<3 { app.buttons["Continue"].tap() }
        app.buttons["Start using Porchlight"].tap()

        // The assignment survives onboarding and shows in Settings.
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["\(calendarName) belongs to Mia"].waitForExistence(timeout: 10), "Settings should keep the assignment")
        snapshot("34-settings-calendars")
    }
}
