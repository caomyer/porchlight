import XCTest

/// Free together on the phone (docs/design/calendar-free-together.md): from the Calendar tab
/// to the coming evenings and weekend days, one person's answer, and a free evening planned
/// into the home calendar. The clock is pinned to the Wednesday at 8 in the morning; what is
/// added goes to the sample's calendars in memory. Runs on the iPhone.
@MainActor
final class PhoneFreeTogetherTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    func testPlanningAFreeEvening() {
        let app = XCUIApplication.porchlight()
        app.launchArguments = [
            "-sampleHousehold", "-debugCompanionNow", UITestClock.at(8, 0), "-me", "James",
            "-sampleSharedCalendar", "YES", "-sampleHomeCalendar", "YES", "-startScreen", "calendar",
        ]
        app.launch()
        waitUntilResponsive(app)
        let free = app.buttons["calendar-view-free"]
        XCTAssertTrue(free.waitForExistence(timeout: 10))
        free.tap()
        let tonight = app.descendants(matching: .any)["free-\(UITestClock.day(0))"]
        XCTAssertTrue(tonight.waitForExistence(timeout: 5), "Tonight first")
        XCTAssertTrue(tonight.label.hasPrefix("Tonight"), tonight.label)
        snapshot("free-60-phone")

        // Mia's chip: the answer for her alone.
        app.buttons["calendar-chip-Mia"].tap()
        XCTAssertTrue(app.buttons["calendar-chip-Mia"].isSelected)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Everyone free")).firstMatch.exists, "no \"Everyone\" for one person")
        snapshot("free-61-mia")
        app.buttons["calendar-chip-Everyone"].tap()

        // A green evening opens the add sheet from when everyone is free.
        let green = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Everyone free from")).firstMatch
        reveal(green, in: app)
        // The time the row says everyone is free from, as "7:30".
        let label = green.label
        guard let from = label.range(of: #"from \d{1,2}:\d{2}"#, options: .regularExpression).map({ String(label[$0].dropFirst(5)) }) else {
            return XCTFail("A green row says when: \(label)")
        }
        green.tap()
        let line = app.descendants(matching: .any).matching(identifier: "event-line").firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10), "The add sheet")
        type("Dinner with the Lees", into: line, in: app)
        let reads = app.descendants(matching: .any).matching(identifier: "event-reads-as").firstMatch
        XCTAssertTrue(reads.waitForExistence(timeout: 5) && reads.label.contains("Dinner with the Lees"), reads.label)
        XCTAssertTrue(reads.label.contains("· \(from)"), "from the free evening, \(from): \(reads.label)")
        snapshot("free-62-plan")
        app.buttons["event-save"].tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 10), "saved")
    }
}
