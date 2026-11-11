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

    /// Types on the card's number pad, e.g. "715" or "7:15", then Done.
    private func type(_ app: XCUIApplication, _ text: String, done: Bool = true) {
        for character in text {
            let key = character == ":" ? "colon" : String(character)
            app.buttons["key-\(key)"].tap()
        }
        if done { app.buttons["time-done"].tap() }
    }

    private func clear(_ app: XCUIApplication) {
        for _ in 0..<6 { app.buttons["key-delete"].tap() }
    }

    /// A breakfast's time is typed, flipped with AM | PM, and a mistake is explained.
    func testTypingAMealTime() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "food"]
        app.launch()

        let meal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Breakfast: Pancakes'")).firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 30))
        meal.tap()
        app.buttons["Edit"].tap()

        let pill = element(app, "time-eaten")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertTrue(value(pill).hasSuffix("AM"), "A sample breakfast is in the morning")
        pill.tap()
        XCTAssertTrue(app.buttons["key-7"].waitForExistence(timeout: 5), "Tapping the time opens the number pad")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The iPad's keyboard stays away")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Usual breakfast'")).firstMatch.exists, "A meal suggests its usual time")
        type(app, "715", done: false)
        XCTAssertEqual(value(element(app, "time-entry")), "715", "The card shows what's typed")
        snapshot("70-meal-keypad")
        app.buttons["time-done"].tap()
        waitFor(pill, "7:15 AM", "Without AM or PM, a breakfast stays in the morning")
        XCTAssertTrue(app.buttons["key-7"].waitForNonExistence(timeout: 5), "Done closes the card")

        pill.tap()
        XCTAssertTrue(app.buttons["PM"].waitForExistence(timeout: 5))
        app.buttons["PM"].tap()
        waitFor(pill, "7:15 PM", "The PM switch flips the half of the day")
        app.buttons["time-done"].tap()

        pill.tap()
        type(app, "7:")
        XCTAssertTrue(element(app, "time-note").waitForExistence(timeout: 5), "Something that isn't a time is explained")
        snapshot("71-meal-keypad-mistake")
        clear(app)
        app.buttons["time-done"].tap()
        XCTAssertTrue(app.buttons["key-7"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(value(pill), "7:15 PM", "A cleared mistake changes nothing")

        app.buttons["Cancel"].tap()
    }

    /// The night runs past midnight: an end before the start is the next day.
    func testNightHoursCrossMidnight() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "settings"]
        app.launch()

        XCTAssertTrue(app.textFields["Household name"].firstMatch.waitForExistence(timeout: 30))
        let start = element(app, "night-start"), end = element(app, "night-end")
        let window = app.windows.firstMatch
        for _ in 0..<8 where !(start.exists && start.isHittable && start.frame.maxY < window.frame.maxY - 200) {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        Thread.sleep(forTimeInterval: 1) // let the scroll settle, or the tap only stops it
        // Saved settings carry over between runs, so put them back at the end.
        let (startBefore, endBefore) = (value(start), value(end))

        start.tap()
        XCTAssertTrue(app.buttons["10:00 PM"].waitForExistence(timeout: 5), "The night suggests evening starts")
        type(app, "10")
        waitFor(start, "10:00 PM", "A night start of 10 is in the evening")

        end.tap()
        type(app, "1")
        waitFor(end, "1:00 AM, next day", "An end before the start is the next morning")
        snapshot("72-night-hours")

        start.tap()
        type(app, startBefore.filter { $0.isNumber })
        waitFor(start, startBefore)
        end.tap()
        type(app, endBefore.prefix { $0 != " " }.filter { $0.isNumber })
        waitFor(end, endBefore)
    }

    /// A routine's window can't end before it starts, and says so.
    func testARoutineWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "settings", "-debugCompanionSheet", "routine"]
        app.launch()

        let start = element(app, "window-start"), end = element(app, "window-end")
        XCTAssertTrue(start.waitForExistence(timeout: 30), "A routine's windows show as two times")
        let (startBefore, endBefore) = (value(start), value(end))
        XCTAssertTrue(startBefore.hasSuffix("AM"), "The sample walk starts in the morning")
        end.tap()
        // An hour before the start: AM after the digits finishes the time.
        let hour = Int(startBefore.prefix { $0 != ":" }) ?? 6
        type(app, "\(hour == 1 ? 12 : hour - 1)", done: false)
        app.buttons["AM"].tap()
        XCTAssertTrue(element(app, "time-note").waitForExistence(timeout: 5), "An end before the start is explained")
        XCTAssertEqual(value(end), endBefore, "A refused time changes nothing")
        snapshot("73-window-mistake")
        clear(app)
        app.buttons["time-done"].tap()
        XCTAssertTrue(app.buttons["key-7"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(value(start), startBefore)
    }
}
