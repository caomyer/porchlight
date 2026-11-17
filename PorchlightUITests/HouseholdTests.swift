import XCTest

/// Households on the wall: Family & devices with its invite, code and removal (A3, D2,
/// A6), setup's role and iCloud steps (A1), rows arriving from phones (D1), and a restored
/// database waiting for a choice. Sharing is the fake (`-debugSharing`), on sample data.
@MainActor
final class HouseholdTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold"] + arguments
        app.launch()
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls Settings until `element` is on screen.
    private func scroll(to element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(element) should exist")
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(element) should scroll into view")
    }

    private func row(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["family-\(name)"]
    }

    // MARK: Family & devices

    func testFamilyAndDevicesShowsEveryoneAndBothWaysIn() {
        let app = launch(["-startScreen", "settings", "-debugSharing", "invited", "-debugSyncStatus", "upToDate"])
        scroll(to: app.staticTexts["Who has the app"], in: app)
        scroll(to: app.buttons["show-code"], in: app)
        XCTAssertTrue(row(app, "James").label.contains("Owner · James's iPhone"), row(app, "James").label)
        XCTAssertTrue(row(app, "James").label.contains("Joined"))
        XCTAssertTrue(row(app, "Mia").label.contains("Invited"), row(app, "Mia").label)
        XCTAssertTrue(row(app, "Ava").label.contains("Pitches in on this screen"), row(app, "Ava").label)
        XCTAssertTrue(app.staticTexts["The Lake House · stored in James's iCloud"].exists)
        XCTAssertTrue(app.staticTexts["Shared iPad"].exists, "This iPad, by the name it has")
        snapshot("80-family-and-devices")

        app.buttons["invite"].tap()
        XCTAssertTrue(app.staticTexts["Join The Lake House on Porchlight"].waitForExistence(timeout: 5), "Invite opens the sharing sheet")
        snapshot("81-family-invite")
        app.buttons["invite-done"].tap()

        app.buttons["show-code"].tap()
        XCTAssertTrue(app.images["join-code"].waitForExistence(timeout: 15), "The code is drawn on the iPad")
        XCTAssertTrue(app.staticTexts["Point an iPhone camera here. The first person who scans joins The Lake House, so show it only to family."].exists)
        snapshot("82-family-join-code")
        app.buttons["Done"].tap()
        XCTAssertFalse(app.images["join-code"].waitForExistence(timeout: 2))
    }

    /// With sync off nothing is in iCloud: the card says so, and Invite says why it can't,
    /// with a way to the switch.
    func testWithSyncOffTheHouseholdIsOnThisIPadOnly() {
        let app = launch(["-startScreen", "settings", "-debugSharing", "invited", "-debugSyncStatus", "off"])
        let blocker = app.staticTexts["invite-blocker"]
        scroll(to: blocker, in: app)
        XCTAssertEqual(app.staticTexts["household-home"].label, "The Lake House · on this iPad only")
        XCTAssertEqual(blocker.label, "Turn on iCloud sync to invite phones.")
        XCTAssertFalse(app.buttons["invite"].isEnabled, "Invite waits for sync")
        XCTAssertFalse(app.buttons["show-code"].isEnabled)
        snapshot("92-family-sync-off")
        app.buttons["go-to-sync"].tap()
        let toggle = app.switches["sync-switch"]
        let shown = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: toggle)
        wait(for: [shown], timeout: 5)
        snapshot("93-sync-section")
    }

    func testTheOwnerRemovesSomeonesPhone() {
        let app = launch(["-startScreen", "settings", "-debugSharing", "joined", "-debugSyncStatus", "upToDate"])
        let remove = app.buttons["Remove Mia's devices"]
        scroll(to: remove, in: app)
        XCTAssertTrue(row(app, "Mia").label.contains("Mia's iPhone"), row(app, "Mia").label)
        remove.tap()
        XCTAssertTrue(app.staticTexts["Remove Mia's iPhone?"].waitForExistence(timeout: 5))
        snapshot("83-family-remove")
        app.buttons["Remove"].tap()
        XCTAssertTrue(app.staticTexts["Remove Mia's iPhone?"].waitForNonExistence(timeout: 5))
        let mia = row(app, "Mia")
        XCTAssertTrue(mia.waitForExistence(timeout: 5), "Mia stays in the household")
        XCTAssertTrue(mia.label.contains("Pitches in on this screen"), mia.label)
        XCTAssertFalse(remove.exists)
    }

    func testRenamingThisIPadFitsAboveTheKeyboard() {
        let app = launch(["-startScreen", "settings", "-debugSharing", "invited", "-debugSyncStatus", "upToDate"])
        let change = app.buttons["change-this-device"]
        scroll(to: change, in: app)
        change.tap()
        let name = app.textFields["device-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Hallway iPad")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        snapshot("84-this-ipad-keyboard")
        let save = app.buttons["save-device"]
        let keyboard = app.keyboards.firstMatch.frame
        XCTAssertLessThan(save.frame.maxY, keyboard.minY, "Save stays above the keyboard")
        XCTAssertGreaterThan(app.staticTexts["This iPad"].frame.minY, 0, "and so does the sheet's title")
        save.tap()
        XCTAssertTrue(app.staticTexts["Hallway iPad"].waitForExistence(timeout: 5))
    }

    // MARK: Setup

    func testSetupAsksHowThisIPadIsUsed() {
        let app = launch(["-onboardingStep", "role"])
        XCTAssertTrue(app.staticTexts["How will this iPad be used?"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["role-sharedScreen"].isSelected)
        snapshot("85-setup-role")
        app.buttons["role-personal"].tap()
        XCTAssertTrue(app.buttons["role-personal"].isSelected)
    }

    func testSetupSaysWhereTheHouseholdLives() {
        var app = launch(["-onboardingStep", "iCloud"])
        XCTAssertTrue(app.staticTexts["The Lake House lives in your iCloud"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Invite phones now"].exists && app.buttons["Finish"].exists)
        snapshot("86-setup-icloud")
        app.terminate()

        app = launch(["-onboardingStep", "iCloud", "-debugSyncStatus", "noAccount"])
        XCTAssertTrue(app.staticTexts["Keep it on this iPad for now?"].waitForExistence(timeout: 30), "Without iCloud it never blocks")
        XCTAssertTrue(app.buttons["Keep going on this iPad"].exists && app.buttons["Open iPad Settings"].exists)
        snapshot("87-setup-signed-out")
    }

    // MARK: Arrivals

    func testRowsFromPhonesAreTaggedAndArrivalsNamed() {
        let app = launch(["-startScreen", "today", "-debugArrival"])
        let fromMia = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "from Mia's phone")).firstMatch
        XCTAssertTrue(fromMia.waitForExistence(timeout: 30), "What Mia did today came from her phone")
        let toast = app.descendants(matching: .any)["arrival-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 15), "A walk arrives from James's phone")
        XCTAssertEqual(toast.label, "James walked Yo-Yo · from their phone")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "from James's phone")).firstMatch.exists, "and its row says where it came from")
        snapshot("88-arrival")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 12), "The toast goes by itself")
        snapshot("89-arrival-settled")
    }

    // MARK: Sample data

    /// Sample meal photos are read back from Caches and stored as photo rows, like a
    /// camera's: the week's polaroids show them.
    func testSampleMealsHaveTheirPhotos() {
        let app = launch(["-startScreen", "food"])
        let toast = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Avocado toast")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 30), "Today's breakfast is on the week")
        snapshot("91-food-week-sample")
    }

    // MARK: A restored database

    func testARestoredCopyWaitsForAChoice() {
        let app = launch(["-startScreen", "settings", "-debugSyncStatus", "restoredCopy"])
        let title = app.staticTexts["This iPad's data was replaced by an older copy"]
        scroll(to: title, in: app)
        XCTAssertTrue(app.buttons["Use what is in iCloud"].exists)
        XCTAssertTrue(app.buttons["Keep this copy on this iPad, without sync"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'send'")).firstMatch.exists, "Sending this copy up is never offered")
        XCTAssertEqual(app.buttons["Settings"].value as? String, "Sync needs a look", "The gear shows a dot")
        snapshot("90-restored-copy")

        app.buttons["Keep this copy on this iPad, without sync"].tap()
        let toggle = app.switches["sync-switch"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Keeping it brings back the switch")
        XCTAssertEqual(toggle.value as? String, "0", "off")
    }
}
