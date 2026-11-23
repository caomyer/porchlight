import XCTest

/// Sync in the states the owner has to see: Settings explains each, the gear on the rail
/// shows a dot when sync is stuck, and a fresh install looks for its household before
/// setting up a new one. `-debugSyncStatus` puts sync in a state without iCloud, and
/// sample launches use their own storage sandbox.
@MainActor
final class SyncSettingsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = arguments
        app.launch()
        _ = app.otherElements.firstMatch.waitForExistence(timeout: 30)
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls Settings until the sync section is on screen.
    private func showSyncSection(_ app: XCUIApplication, title: String) {
        let element = app.staticTexts[title]
        XCTAssertTrue(element.waitForExistence(timeout: 20), "Settings should say \"\(title)\"")
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "The sync section should scroll into view")
    }

    /// The wall asks iCloud for changes every 15 seconds while it stays open and untouched.
    /// `-debugSyncPoll` runs the real schedule against a stand-in for iCloud, and Sync
    /// details counts the checks.
    func testChecksTickOnAnUntouchedWall() {
        let app = launch(["-sampleHousehold", "-startScreen", "settings", "-debugSyncPoll"])
        let details = app.buttons["sync-details"]
        XCTAssertTrue(details.waitForExistence(timeout: 20), "Settings has Sync details")
        for _ in 0..<8 where !details.isHittable {
            app.swipeUp()
        }
        details.tap()
        let checks = app.descendants(matching: .any)["sync-details-checks"]
        XCTAssertTrue(checks.waitForExistence(timeout: 5), "The details open")
        XCTAssertTrue((checks.label).contains("Checks"), "got \(checks.label)")
        // One check on coming to the front, then one each 15 seconds: three within 40.
        let three = NSPredicate(format: "label MATCHES %@", ".*Checks, ([3-9]|[1-9][0-9]+),.*")
        let ticked = expectation(for: three, evaluatedWith: checks)
        wait(for: [ticked], timeout: 45)
        let last = app.descendants(matching: .any)["sync-details-last-check"]
        XCTAssertTrue(last.label.contains("answered"), "got \(last.label)")
        snapshot("73-sync-details")
    }

    /// Records iCloud refused and this iPad kept say so in Sync details, in words read aloud,
    /// and "none" while there were none (docs/design/sync-icloud.md, "A record sent before
    /// its parent"). The counts are kept in the device's preferences, given here at launch.
    func testHeldRecordsSayHowManyInWords() {
        for kept in [true, false] {
            let app = launch(["-sampleHousehold", "-startScreen", "settings"] + (kept ? Self.keptRecords : []))
            let details = app.buttons["sync-details"]
            XCTAssertTrue(details.waitForExistence(timeout: 20), "Settings has Sync details")
            for _ in 0..<8 where !details.isHittable {
                app.swipeUp()
            }
            details.tap()
            let held = app.descendants(matching: .any)["sync-details-held"]
            XCTAssertTrue(held.waitForExistence(timeout: 5), "The details open")
            for _ in 0..<8 where !held.isHittable {
                app.swipeUp()
            }
            let resent = app.descendants(matching: .any)["sync-details-resent"]
            if kept {
                XCTAssertTrue(held.label.range(of: SyncSettingsTests.heldWords, options: .regularExpression) != nil, "got \(held.label)")
                XCTAssertTrue(resent.label.contains("Sent again 1 record iCloud turned down. Last: a walk or meal,"), "got \(resent.label)")
                snapshot("74-sync-details-held")
            } else {
                XCTAssertTrue(held.label.hasSuffix("none"), "got \(held.label)")
                XCTAssertTrue(resent.label.hasSuffix("none"), "got \(resent.label)")
                snapshot("75-sync-details-held-none")
            }
            app.terminate()
        }
    }

    /// The held line in words, then when: the day and time follow the household's time zone,
    /// which is the runner's, so only their shape is checked here (`SyncDeferralsTests`
    /// pins them).
    static let heldWords = #"^Held for a parent, Held 3 records until their parent arrived\. Last: who walked or fed, [A-Z][a-z]{2} \d{1,2} at \d{1,2}:\d{2}\W?[AP]M\.$"#

    /// Three held for a parent and one sent again, the last at one moment on Nov 23 or 24,
    /// wherever the runner is.
    static let keptRecords = [
        "-sync.deferrals.held", "3", "-sync.deferrals.lastHeld", "(careLogPerson, 1795488060)",
        "-sync.deferrals.resent", "1", "-sync.deferrals.lastResent", "(careLog, 1795488060)",
    ]

    func testADifferentAccountAsksWhatToDo() {
        let app = launch(["-sampleHousehold", "-startScreen", "settings", "-debugSyncStatus", "needsDecision"])
        showSyncSection(app, title: "A different iCloud account signed in")
        XCTAssertTrue(app.buttons["Keep it here without sync"].exists)
        XCTAssertTrue(app.buttons["Remove it from this iPad"].exists)
        XCTAssertEqual(app.buttons["Settings"].value as? String, "Sync needs a look", "The gear shows a dot")
        snapshot("70-sync-needs-decision")

        app.buttons["Keep it here without sync"].tap()
        let toggle = app.switches["sync-switch"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Keeping it brings back the switch")
        XCTAssertEqual(toggle.value as? String, "0", "off")
        XCTAssertEqual(app.buttons["Settings"].value as? String, "", "and the dot goes")
    }

    func testAFullICloudPausesSync() {
        let app = launch(["-sampleHousehold", "-startScreen", "settings", "-debugSyncStatus", "iCloudFull"])
        showSyncSection(app, title: "Sync is paused: iCloud is full")
        XCTAssertEqual(app.buttons["Settings"].value as? String, "Sync needs a look", "The gear shows a dot")
        snapshot("71-sync-icloud-full")
        app.buttons["Today"].tap()
        XCTAssertFalse(app.staticTexts["Sync is paused: iCloud is full"].exists, "Nothing about sync shows on Today")
        snapshot("72-sync-gear-dot")
    }

    /// A missing iCloud says why in Settings, with the gear's dot. One state on screen proves
    /// the status reaches the sync section and the rail; the words for each way iCloud can be
    /// missing, and which states put the dot on the gear, are `SyncWordingTests` (unit).
    func testAMissingICloudSaysWhy() {
        let summary = "iCloud is off for Porchlight: this iPad isn't signed in to iCloud, or iCloud is turned off for Porchlight. Turn it on in the Settings app to sync again; everything stays here meanwhile."
        let app = launch(["-sampleHousehold", "-startScreen", "settings", "-debugSyncStatus", "noAccount"])
        // Too long to look up by its whole text, so by how it starts, then checked whole.
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", String(summary.prefix(40)))).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 20), "Settings says why")
        XCTAssertEqual(line.label, summary)
        for _ in 0..<8 where !line.isHittable { app.swipeUp() }
        XCTAssertTrue(line.isHittable, "The sync section scrolls into view")
        XCTAssertEqual(app.buttons["Settings"].value as? String, "Sync needs a look", "The gear shows a dot")
        snapshot("74-sync-icloud-off")
    }

    func testAFreshInstallLooksForItsHouseholdFirst() {
        let app = launch(["-resetData", "-debugSyncStatus", "lookingForHousehold"])
        XCTAssertTrue(app.staticTexts["Looking for your household in iCloud"].waitForExistence(timeout: 20))
        let fresh = app.buttons["Start fresh instead"]
        XCTAssertTrue(fresh.waitForExistence(timeout: 10))
        let offered = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: fresh)
        wait(for: [offered], timeout: 10)
        snapshot("73-looking-for-household")
        fresh.tap()
        XCTAssertTrue(app.staticTexts["Welcome home"].waitForExistence(timeout: 10), "Starting fresh opens setup")
    }
}
