import XCTest

/// The phone's Calendar tab (docs/design/calendar-phone-tab.md), one test per journey: the
/// week, picking a day, a person's events and an event's page; and the month. With Mia's phone
/// having passed her calendars on, and the clock pinned to a Wednesday at 8 in the morning. Runs on the iPhone.
@MainActor
final class PhoneCalendarTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    /// The pinned day (`UITestClock`, a Wednesday) at 8 in the morning, so the day's events
    /// are all ahead and tomorrow is in the same week (docs/design/testing.md, "A new feature
    /// and the clock").
    private static var morning: String { UITestClock.at(8, 0) }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.morning, "-me", "James", "-sampleSharedCalendar", "YES"] + arguments
        app.launch()
        waitUntilResponsive(app)
        return app
    }

    private static func key(_ offset: Int) -> String { UITestClock.day(offset) }

    /// The tab from the bar, tomorrow picked, Mia's events alone, and one event's page.
    func testTheWeekAPersonAndAnEvent() {
        let app = launch()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendar-month-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["calendar-strip-\(Self.key(0))"].isSelected, "Today is picked")
        snapshot("cal-40-tab")

        let tomorrow = app.buttons["calendar-strip-\(Self.key(1))"]
        tomorrow.tap()
        XCTAssertTrue(tomorrow.isSelected)
        let ballet = app.buttons["calendar-event-Ava's ballet recital"]
        reveal(ballet, in: app)
        XCTAssertTrue(ballet.exists, "The list starts at the picked day")
        XCTAssertTrue(app.buttons["calendar-today"].isHittable, "with a way back to today")

        // James's haircut, his alone, is in the list until Mia's chip is picked.
        let haircut = app.buttons["calendar-event-Haircut"]
        XCTAssertTrue(haircut.exists, "James's haircut, in the days after")
        app.buttons["calendar-chip-Mia"].tap()
        XCTAssertTrue(app.buttons["calendar-chip-Mia"].isSelected)
        XCTAssertFalse(haircut.exists, "James's own events go")
        snapshot("cal-41-mia")

        reveal(ballet, in: app)
        ballet.tap()
        let page = app.descendants(matching: .any)["event-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 5), "The event's page, in the app")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "From Mia's iCloud")).firstMatch.exists, "where it came from")
        XCTAssertFalse(app.buttons["open-in-calendar"].exists, "another phone's event can't open in this phone's Calendar")
        snapshot("cal-42-event")
    }

    /// The title opens the month; a day in it picks that day and folds the month away.
    func testTheMonth() {
        let app = launch(["-startScreen", "calendar"])
        let title = app.buttons["calendar-month-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        let month = app.descendants(matching: .any)["calendar-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 5), "The month unfolds")
        snapshot("cal-50-month")
        let day = app.buttons["calendar-month-\(Self.key(2))"]
        day.tap()
        XCTAssertTrue(month.waitForNonExistence(timeout: 5), "and folds back")
        XCTAssertTrue(app.buttons["calendar-strip-\(Self.key(2))"].isSelected, "with that day picked")
        XCTAssertTrue(app.descendants(matching: .any)["calendar-day-\(Self.key(2))"].exists, "and the list there")
    }
}
