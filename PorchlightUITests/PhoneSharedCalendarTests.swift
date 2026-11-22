import XCTest

/// The shared calendar on the phone (docs/design/calendar-shared.md): what another device
/// passed on is on Today's "At home today" card. Runs on the iPhone.
@MainActor
final class PhoneSharedCalendarTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    /// The pinned day (`UITestClock`, a Wednesday) at 8 in the morning, so the day's events
    /// are all ahead and tomorrow's and the day after's are in the same week
    /// (docs/design/testing.md, the hard rule "A test's outcome never depends on the real
    /// clock").
    private static var morning: String { UITestClock.at(8, 0) }

    func testAnotherDevicesCalendarsOnToday() {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.morning, "-me", "James", "-sampleSharedCalendar", "YES", "-startScreen", "today"]
        app.launch()
        waitUntilResponsive(app)
        let work = element(app, beginningWith: "9:00, Mia at work")
        reveal(work, in: app)
        XCTAssertTrue(work.exists, "Mia's work is one quiet row")
        XCTAssertTrue(work.label.contains("3 meetings"), work.label)
        let climb = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Climbing gym")).firstMatch
        XCTAssertTrue(climb.exists, "and her events, with this phone's")
        snapshot("cal-30-today-card")
    }
}
