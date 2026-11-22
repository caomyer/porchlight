import XCTest

/// Adding and changing events in a real calendar on the phone (docs/design/calendar-add-edit.md),
/// one test per journey: adding one, choosing the home calendar on the way; and changing a
/// repeating one from here on. The sample's calendars are written in memory as EventKit would.
/// Runs on the iPhone.
@MainActor
final class PhoneCalendarEditTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    /// Today at 8 in the morning (hard rule 1).
    private static var morning: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02dT08:00", parts.year!, parts.month!, parts.day!)
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.morning, "-me", "James", "-startScreen", "calendar"] + arguments
        app.launch()
        waitUntilResponsive(app)
        return app
    }

    /// "+" with no home calendar yet asks for one first, then the line is read as it is typed,
    /// and the event is in the list for whom it said.
    func testAddingAnEvent() {
        let app = launch()
        let add = app.buttons["calendar-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let us = app.buttons["home-Us"]
        XCTAssertTrue(us.waitForExistence(timeout: 5), "The household chooses its home calendar once")
        snapshot("cal-60-home-calendar")
        us.tap()

        let line = app.descendants(matching: .any).matching(identifier: "event-line").firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10), "then the sheet")
        type("Mia piano tomorrow 4pm", into: line, in: app)
        let reads = app.descendants(matching: .any).matching(identifier: "event-reads-as").firstMatch
        XCTAssertTrue(reads.waitForExistence(timeout: 5))
        XCTAssertTrue(reads.label.contains("Mia piano") && reads.label.contains("4:00"), "Reads as: \(reads.label)")
        XCTAssertTrue(app.buttons["event-for-Mia"].isSelected, "For Mia, from her name")
        XCTAssertTrue(app.descendants(matching: .any)["event-saved-in"].label.contains("Us"), "saved in the home calendar")
        snapshot("cal-61-new-event")
        app.buttons["event-save"].tap()

        let added = app.buttons["calendar-event-Mia piano"]
        reveal(added, in: app)
        XCTAssertTrue(added.waitForExistence(timeout: 10), "It is in the list")
        XCTAssertTrue(added.label.contains("Mia"), "for Mia: \(added.label)")
        snapshot("cal-62-added")
    }

    /// A weekly event in the home calendar changed for this week and the ones after.
    func testChangingARepeatingEvent() {
        let app = launch(["-sampleHomeCalendar", "YES"])
        let piano = app.buttons.matching(identifier: "calendar-event-Piano lesson").firstMatch
        reveal(piano, in: app)
        XCTAssertTrue(piano.waitForExistence(timeout: 10))
        piano.tap()
        let edit = app.buttons["event-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "This phone may change it")
        XCTAssertTrue(app.staticTexts["Repeats every week"].exists)
        snapshot("cal-70-event-page")
        edit.tap()

        let title = app.descendants(matching: .any).matching(identifier: "event-title").firstMatch
        type("Piano lesson, new teacher", into: title, in: app)
        app.buttons["event-save"].tap()
        // The dialog can list a button more than once in the tree.
        let future = app.buttons.matching(identifier: "span-future").firstMatch
        XCTAssertTrue(future.waitForExistence(timeout: 5), "It asks: this one, or this and future ones")
        snapshot("cal-71-span")
        future.tap()

        let changed = app.buttons.matching(identifier: "calendar-event-Piano lesson, new teacher").firstMatch
        reveal(changed, in: app)
        XCTAssertTrue(changed.waitForExistence(timeout: 10), "changed from here on")
        snapshot("cal-72-changed")
    }
}
