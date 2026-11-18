import XCTest

/// A brand-new household's first run against the real calendar store: onboarding,
/// the iPadOS calendar permission prompt, and giving each calendar to a person.
/// `-resetData` uses the sample storage sandbox, so real data is never touched.
/// The test resets the calendar permission itself, so the prompt always appears.
@MainActor
final class FirstRunTests: XCTestCase {
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Types into a field and checks it took. Typing straight after a field gains
    /// focus (or while the app moves focus to a new row) can drop the first keys.
    private func type(_ text: String, into field: XCUIElement) {
        for _ in 0..<3 {
            field.tap()
            let current = field.value as? String ?? ""
            let placeholder = field.placeholderValue ?? ""
            if !current.isEmpty, current != placeholder {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            field.typeText(text)
            if field.value as? String == text { return }
        }
        XCTFail("Could not type \"\(text)\" into the field")
    }

    func testOnboardingWithRealCalendarAccess() throws {
        let app = XCUIApplication.porchlight()
        // Ask as a new install does, whatever an earlier run on this simulator answered.
        app.resetAuthorizationStatus(for: .calendar)
        app.launchArguments = ["-resetData"]
        app.launch()

        let household = app.textFields["household-name"]
        XCTAssertTrue(household.waitForExistence(timeout: 30))
        type("Test House", into: household)
        household.typeText("\n")

        // How this iPad is used: a shared screen unless someone says otherwise (journey A1).
        XCTAssertTrue(app.staticTexts["How will this iPad be used?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["role-sharedScreen"].isSelected, "An iPad starts as a shared screen")
        snapshot("29-onboarding-role")
        app.buttons["Continue"].tap()

        let firstName = app.textFields["Name"].firstMatch
        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        type("James", into: firstName)
        app.buttons["Add someone"].tap()
        let secondName = app.textFields.matching(identifier: "Name").element(boundBy: 1)
        XCTAssertTrue(secondName.waitForExistence(timeout: 5))
        type("Mia", into: secondName)
        app.buttons["Continue"].tap()

        let allow = app.buttons["Allow calendar access"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "The calendars step should ask for access")
        snapshot("30-calendars-before-access")
        allow.tap()

        // The system prompt belongs to SpringBoard, not the app, and comes once the system's
        // privacy service has answered, which on a busy Mac has taken more than 15 seconds.
        // Wait for whichever button it shows, for up to a minute: no prompt by then is a real
        // failure, and the calendars must still be listed below.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let fullAccess = springboard.alerts.buttons["Allow Full Access"]
        let ok = springboard.alerts.buttons["OK"]
        let deadline = Date.now.addingTimeInterval(60)
        while !(fullAccess.exists || ok.exists), Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(fullAccess.exists || ok.exists, "iPadOS should ask for calendar access")
        snapshot("31-calendar-permission-prompt")
        (fullAccess.exists ? fullAccess : ok).tap()

        let owner = app.buttons.matching(NSPredicate(format: "label CONTAINS ' belongs to '")).firstMatch
        XCTAssertTrue(owner.waitForExistence(timeout: 30), "The iPad's calendars should be listed after access is granted")
        let calendarName = String(owner.label.components(separatedBy: " belongs to ").first ?? "")
        snapshot("32-calendars-listed")

        owner.tap()
        let mia = app.buttons["Mia"]
        XCTAssertTrue(mia.waitForExistence(timeout: 5), "The owner menu should list the household's people")
        mia.tap()
        let assigned = app.buttons["\(calendarName) belongs to Mia"]
        XCTAssertTrue(assigned.waitForExistence(timeout: 5), "\(calendarName) should now belong to Mia")
        snapshot("33-calendar-assigned")

        for _ in 0..<4 { app.buttons["Continue"].tap() }

        // The last step says where the household lives, and can go straight to inviting.
        XCTAssertTrue(app.staticTexts["Test House lives in your iCloud"].waitForExistence(timeout: 5))
        snapshot("35-onboarding-icloud")
        app.buttons["Invite phones now"].tap()
        XCTAssertTrue(app.staticTexts["Who has the app"].waitForExistence(timeout: 10), "Setup ends on Family & devices")
        XCTAssertTrue(app.buttons["Invite someone"].isHittable, "with the invite on screen")
        snapshot("36-onboarding-ends-on-family")

        // The assignment survives onboarding and shows in Settings.
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["\(calendarName) belongs to Mia"].waitForExistence(timeout: 10), "Settings should keep the assignment")
        snapshot("34-settings-calendars")
    }
}
