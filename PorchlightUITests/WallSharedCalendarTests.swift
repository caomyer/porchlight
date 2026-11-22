import XCTest

/// The shared calendar on the wall (docs/design/calendar-shared.md), one test per journey:
/// another device's calendars on the wall's week, and a calendar set to Just me leaving the
/// household. Runs on the iPad.
@MainActor
final class WallSharedCalendarTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPhone = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .phone }
        try XCTSkipIf(isPhone, "The wall's tests run on an iPad")
    }

    /// Today at 8 in the morning, so the day's events are all ahead (hard rule 1).
    private static var morning: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02dT08:00", parts.year!, parts.month!, parts.day!)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.morning] + arguments
        app.launch()
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Mia's phone passed on her work as Keep it quiet and her own calendar in full, two days
    /// ago: the wall's week has her work as one block a day, its meetings a tap away, the
    /// climbing gym she shares with James once with both faces, and says her calendar is old.
    func testAnotherDevicesCalendarsOnTheWall() {
        let app = launch(["-sampleSharedCalendar", "stale", "-startScreen", "calendar"])
        let block = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Mia at work, until")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 30), "Her work is one quiet block")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Mia's calendar, updated")).firstMatch.exists, "and the wall says her calendar is old")
        let climb = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Climbing gym")).firstMatch
        XCTAssertTrue(climb.exists, "The climbing gym, once")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Climbing gym")).count, 1)
        snapshot("cal-10-week")
        block.waitToSettle()
        block.tap()
        let meetings = app.descendants(matching: .any)["quiet-events"]
        XCTAssertTrue(meetings.waitForExistence(timeout: 5), "A tap lists the meetings")
        XCTAssertTrue(app.staticTexts["Launch review"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Mia · From Mia's Exchange")).firstMatch.exists, "and where they come from")
        snapshot("cal-11-quiet-block")
        app.buttons["Close"].tap()
        XCTAssertTrue(meetings.waitForNonExistence(timeout: 5))
        climb.waitToSettle()
        climb.tap()
        let both = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "James and Mia")).firstMatch
        XCTAssertTrue(both.waitForExistence(timeout: 5), "One event for both of them, with both faces")
        snapshot("cal-12-both-faces")
    }

    /// Setting one of the wall's calendars to Just me takes it out of what the wall passes
    /// on: Sync details' line for this device counts one calendar fewer.
    func testJustMeLeavesTheHousehold() {
        let app = launch(["-startScreen", "settings"])
        let mia = app.buttons["sharing-Mia"]
        XCTAssertTrue(mia.waitForExistence(timeout: 30), "The calendars, with what the household sees")
        for _ in 0..<8 where !mia.isHittable { app.swipeUp() }
        let before = calendarsLine(app)
        XCTAssertTrue(before.contains("6 calendars"), "The wall passes on its six: \(before)")
        for _ in 0..<8 where !mia.isHittable { app.swipeDown() }
        mia.tap()
        let justMe = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Just me")).firstMatch
        XCTAssertTrue(justMe.waitForExistence(timeout: 5))
        justMe.tap()
        XCTAssertTrue(app.buttons["Mia: the household sees Just me"].waitForExistence(timeout: 5))
        let fewer = NSPredicate(format: "label CONTAINS %@", "5 calendars")
        let line = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Calendars, ")).firstMatch
        for _ in 0..<8 where !line.isHittable { app.swipeUp() }
        wait(for: [expectation(for: fewer, evaluatedWith: line)], timeout: 20)
        snapshot("cal-20-just-me")
    }

    /// Opens Sync details and reads this device's calendars line.
    private func calendarsLine(_ app: XCUIApplication) -> String {
        let details = app.buttons["sync-details"]
        for _ in 0..<8 where !details.isHittable { app.swipeUp() }
        details.tap()
        let line = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Calendars, ")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 20), "Sync details has a line for this device's calendars")
        for _ in 0..<8 where !line.isHittable { app.swipeUp() }
        return line.label
    }
}
