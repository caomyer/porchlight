import XCTest

/// Every time in the app is a pill that opens a small card: suggestions and a
/// number pad. The iPad's keyboard never comes up.
@MainActor
final class TimeFieldTests: XCTestCase {
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    /// Waits for an element's value, since values can lag a tap.
    private func waitFor(_ element: XCUIElement, _ expected: String, _ message: String = "") {
        let predicate = NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected \(expected), got \(value(element)). \(message)")
    }

    /// Types digits on the card's number pad, then Done.
    private func type(_ app: XCUIApplication, _ digits: String, done: Bool = true) {
        for digit in digits { app.buttons["key-\(digit)"].tap() }
        if done { app.buttons["time-done"].tap() }
    }

    /// Sets a pill to a time shown like "9:30 PM" by typing it, then Done.
    private func set(_ app: XCUIApplication, _ pill: XCUIElement, to shown: String) {
        pill.tap()
        XCTAssertTrue(app.buttons["key-1"].waitForExistence(timeout: 5))
        let time = shown.prefix { $0 != " " && $0 != "," }.split(separator: ":")
        type(app, String(time[0]), done: false)
        element(app, "time-minute").tap()
        type(app, String(time[1]), done: false)
        if shown.contains("AM") { app.buttons["AM"].tap() }
        if shown.contains("PM") { app.buttons["PM"].tap() }
        app.buttons["time-done"].tap()
        waitFor(pill, shown)
    }

    /// The card opens on the meal's time; each digit counts at once, so 2 to 1
    /// is one tap, and AM | PM flips the half of the day.
    func testTypingAMealTime() {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "food"] + UITestClock.arguments
        app.launch()

        let meal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Breakfast: Pancakes'")).firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 30))
        meal.tap()
        app.buttons["Edit"].tap()

        let pill = element(app, "time-eaten")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        let before = value(pill)
        XCTAssertTrue(before.hasSuffix("AM"), "A sample breakfast is in the morning")
        pill.tap()
        XCTAssertTrue(app.buttons["key-7"].waitForExistence(timeout: 5), "Tapping the time opens the number pad")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The iPad's keyboard stays away")
        XCTAssertFalse(app.buttons["key-colon"].exists, "The boxes split hours from minutes, so there's no colon key")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Usual breakfast'")).firstMatch.exists, "A meal suggests its usual time")
        let hour = element(app, "time-hour"), minutes = element(app, "time-minute")
        XCTAssertEqual(value(hour), String(before.prefix { $0 != ":" }), "The card opens on the meal's time")
        XCTAssertTrue(hour.isSelected, "with the hour selected")

        type(app, "715", done: false)
        waitFor(pill, "7:15 AM", "Each digit counts at once, and the morning stays the morning")
        XCTAssertEqual(value(minutes), "15")
        snapshot("70-meal-keypad")
        app.buttons["time-done"].tap()
        XCTAssertTrue(app.buttons["key-7"].waitForNonExistence(timeout: 5), "Done closes the card")

        pill.tap()
        XCTAssertTrue(app.buttons["key-1"].waitForExistence(timeout: 5))
        type(app, "1", done: false)
        waitFor(pill, "1:15 AM", "Changing the hour from 7 to 1 is one tap")
        XCTAssertTrue(element(app, "time-hint").label.contains("10, 11 or 12"), "A 1 can still become 10, 11 or 12")
        app.buttons["time-done"].tap()
        waitFor(pill, "1:15 AM", "Done keeps the 1")

        pill.tap()
        XCTAssertTrue(app.buttons["PM"].waitForExistence(timeout: 5))
        app.buttons["PM"].tap()
        waitFor(pill, "1:15 PM", "The PM switch flips the half of the day")
        minutes.tap()
        type(app, "30", done: false)
        waitFor(pill, "1:30 PM", "Tapping the minutes changes only them")
        snapshot("71-meal-keypad-minutes")
        app.buttons["time-done"].tap()

        app.buttons["Cancel"].tap()
    }

    /// The night runs past midnight: an end before the start is the next day.
    func testNightHoursCrossMidnight() {
        // The night's hours are the device's own and outlive this test; they are forgotten
        // afterwards, pass or fail, so nothing here has to put them back.
        forgetDisplaySettingsAfterwards()
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "settings"] + UITestClock.arguments
        app.launch()

        XCTAssertTrue(app.textFields["Household name"].firstMatch.waitForExistence(timeout: 30))
        let start = element(app, "night-start"), end = element(app, "night-end")
        let window = app.windows.firstMatch
        for _ in 0..<8 where !(start.exists && start.isHittable && start.frame.maxY < window.frame.maxY - 200) {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        Thread.sleep(forTimeInterval: 1) // let the scroll settle, or the tap only stops it
        start.tap()
        XCTAssertTrue(app.buttons["10:00 PM"].waitForExistence(timeout: 5), "The night suggests evening starts")
        app.buttons["10:00 PM"].tap()
        waitFor(start, "10:00 PM", "A suggestion sets the start")

        set(app, end, to: "1:00 AM, next day")
        snapshot("72-night-hours")
    }

    /// A routine's window can't end before it starts, and says so.
    func testARoutineWindow() {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "settings", "-debugCompanionSheet", "routine"] + UITestClock.arguments
        app.launch()

        let start = element(app, "window-start"), end = element(app, "window-end")
        XCTAssertTrue(start.waitForExistence(timeout: 30), "A routine's windows show as two times")
        let (startBefore, endBefore) = (value(start), value(end))
        XCTAssertTrue(startBefore.hasSuffix("AM"), "The sample walk starts in the morning")
        end.tap()
        XCTAssertTrue(app.buttons["key-1"].waitForExistence(timeout: 5))
        // An hour before the start.
        let hour = Int(startBefore.prefix { $0 != ":" }) ?? 6
        type(app, "\(hour == 1 ? 12 : hour - 1)", done: false)
        app.buttons["AM"].tap()
        XCTAssertTrue(element(app, "time-note").waitForExistence(timeout: 5), "An end before the start is explained")
        XCTAssertEqual(value(end), endBefore, "A refused time changes nothing")
        XCTAssertFalse(app.buttons["time-done"].isEnabled, "and can't be kept")
        snapshot("73-window-mistake")
        element(app, "time-hour").tap()
        type(app, String(endBefore.prefix { $0 != ":" }), done: false)
        XCTAssertTrue(element(app, "time-note").waitForNonExistence(timeout: 5), "Typing a good hour clears it")
        app.buttons["time-done"].tap()
        XCTAssertTrue(app.buttons["key-7"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(value(end), endBefore)
        XCTAssertEqual(value(start), startBefore)
    }
}
