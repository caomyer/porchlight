import XCTest

/// A household started and set up on an iPhone alone (journeys A2, F1, F2), leaving it or
/// removing someone (A6), and what it stores (E4). Starting is from a fresh install with no
/// sample data. Runs only on an iPhone (`scripts/test.sh --phone`).
@MainActor
final class PhoneSetupTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Scrolls to an element in a sheet only when it can't be tapped where it is. A sheet's
    /// own bottom button is in reach from the start, but lower than the tab bar the sheet
    /// covers, so `reveal` never counts it as in view and drags all fourteen times: 94 of
    /// this class's companion test's 147 seconds on a hosted Mac.
    private func bringIntoReach(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.waitToSettle()
        if !element.isHittable { reveal(element, in: app) }
    }

    // MARK: A2

    func testStartingAHouseholdOnThisPhone() {
        // No household, no sample data: what a new install shows.
        let app = launch(["-resetData"])
        let start = app.buttons["start-household"]
        XCTAssertTrue(start.waitForExistence(timeout: 60))
        snapshot("a2-01-welcome")
        app.buttons["join-one"].tap()
        XCTAssertTrue(element(app, beginningWith: "Open the invite someone sent you").waitForExistence(timeout: 5), "Join one says how")
        start.tap()

        // You and the household.
        let household = app.textFields["household-name"]
        XCTAssertTrue(household.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["setup-continue"].isEnabled, "Nothing to save yet")
        type("Maple Street", into: household, in: app)
        type("Sam", into: app.textFields["my-name"], in: app)
        snapshot("a2-02-you")
        app.buttons["setup-continue"].tap()

        // Who else lives here.
        XCTAssertTrue(app.staticTexts["Who else lives here?"].waitForExistence(timeout: 5))
        app.buttons["add-someone"].tap()
        type("Riley", into: app.textFields["person-name-1"], in: app)
        snapshot("a2-03-people")
        app.buttons["setup-continue"].tap()

        // Anyone to look after: a cat, with its preset routines.
        XCTAssertTrue(app.staticTexts["Anyone to look after?"].waitForExistence(timeout: 5))
        app.buttons["Cat"].tap()
        type("Miso", into: app.textFields["companion-name"], in: app)
        XCTAssertTrue(element(app, beginningWith: "Suggested routines: feed").exists)
        snapshot("a2-04-companion")
        app.buttons["setup-continue"].tap()

        // Ready.
        XCTAssertTrue(app.staticTexts["Maple Street is ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["setup-home"].label.hasPrefix("It's "), "Where it lives, in HouseholdHome's words")
        XCTAssertTrue(app.buttons["Invite Riley"].exists)
        snapshot("a2-05-done")
        app.buttons["go-to-today"].tap()

        // Today, credited to Sam, with Miso to look after; this phone didn't ask who it is.
        XCTAssertTrue(app.staticTexts["Hi, Sam"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, beginningWith: "Miso").waitForExistence(timeout: 5))
        snapshot("a2-10-today")

        // Every tab is intentional while empty.
        app.tabBars.buttons["Food"].tap()
        XCTAssertTrue(element(app, beginningWith: "Nothing in the diary this week").waitForExistence(timeout: 5), "The diary is on, as the wall's setup leaves it")
        snapshot("a2-11-food-empty")
        app.tabBars.buttons["Lists"].tap()
        XCTAssertTrue(app.textFields["add-item"].waitForExistence(timeout: 5))
        snapshot("a2-12-lists-empty")
        app.tabBars.buttons["Glow"].tap()
        let addChores = app.buttons["set-up-chores"]
        XCTAssertTrue(addChores.waitForExistence(timeout: 5), "Glow says where stars come from")
        snapshot("a2-13-glow-empty")
        addChores.tap()
        XCTAssertTrue(app.buttons["new-chore"].waitForExistence(timeout: 5), "It opens Household's chores")
    }

    func testAnEmptyTodayOffersSetup() {
        let app = launch(["-resetData", "-debugSetup", "done"])
        let go = app.buttons["go-to-today"]
        XCTAssertTrue(go.waitForExistence(timeout: 60))
        go.tap()
        let setUp = app.buttons["set-up-household"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 10), "Nothing to do yet, and a way to change that")
        snapshot("a2-14-today-empty")
        setUp.tap()
        XCTAssertTrue(app.staticTexts["Household"].waitForExistence(timeout: 5))
    }

    // MARK: F1, F2

    func testSettingUpTheHouseholdFromThePhone() {
        let app = launch(["-sampleHousehold", "-me", "James", "-debugSharing", "invited", "-startScreen", "you"])
        let household = app.buttons["household"]
        XCTAssertTrue(household.waitForExistence(timeout: 60))
        household.tap()
        XCTAssertTrue(app.staticTexts["Household"].waitForExistence(timeout: 5))
        snapshot("f1-01-hub")

        // Someone new.
        app.buttons["add-person"].tap()
        type("Grandma", into: app.textFields["new-person-name"], in: app)
        app.buttons["save-new-person"].tap()
        let grandma = app.buttons["person-Grandma"]
        XCTAssertTrue(grandma.waitForExistence(timeout: 5))

        // A person: rename, then archive (her history stays).
        grandma.tap()
        let name = app.textFields["person-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        type("Nana", into: name, in: app)
        snapshot("f2-01-person")
        app.buttons["save-person"].tap()
        let nana = app.buttons["person-Nana"]
        XCTAssertTrue(nana.waitForExistence(timeout: 5), "Renamed")
        nana.tap()
        app.buttons["archive-person"].tap()
        let archive = app.buttons["Archive Nana"].firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        XCTAssertTrue(app.buttons["person-Nana"].waitForNonExistence(timeout: 5), "Archived, so not among the people")

        // A chore, through the wall's editor.
        let chores = app.buttons["household-chores"]
        reveal(chores, in: app)
        chores.tap()
        app.buttons["new-chore"].tap()
        let title = app.textFields["What needs doing?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        type("Feed the fish", into: title, in: app)
        snapshot("f2-02-chore")
        let add = app.buttons["Add chore"]
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(app.buttons["chore-Feed the fish"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        // A list.
        let lists = app.buttons["household-lists"]
        reveal(lists, in: app)
        lists.tap()
        type("Hardware store", into: app.textFields["new-list-title"], in: app)
        app.buttons["add-list"].tap()
        XCTAssertTrue(element(app, beginningWith: "Hardware store").waitForExistence(timeout: 5))
        snapshot("f1-02-lists")
    }

    func testACompanionInTheWallsEditor() {
        let app = launch(["-sampleHousehold", "-me", "James", "-startScreen", "you", "-debugYouPage", "companions"])
        let yoyo = app.buttons["companion-Yo-Yo"]
        XCTAssertTrue(yoyo.waitForExistence(timeout: 60))
        snapshot("f2-03-companions")
        yoyo.tap()
        let name = app.textFields["companion-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        snapshot("f2-04-companion")
        // A routine opens the routine editor as its own sheet.
        let edit = app.buttons["Edit"].firstMatch
        reveal(edit, in: app)
        edit.tap()
        let done = app.buttons["routine-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        snapshot("f2-05-routine")
        bringIntoReach(done, in: app)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        type("Yo-Yo Ma", into: name, in: app)
        let save = app.buttons["save-companion"]
        bringIntoReach(save, in: app)
        save.tap()
        XCTAssertTrue(app.buttons["companion-Yo-Yo Ma"].waitForExistence(timeout: 5), "Saved, and back on the list")
    }

    // MARK: A6

    func testAMemberLeaves() {
        let app = launch(["-sampleHousehold", "-me", "Mia", "-debugSharing", "member", "-debugSyncStatus", "upToDate", "-startScreen", "you"])
        let leave = app.buttons["leave-household"]
        XCTAssertTrue(leave.waitForExistence(timeout: 60))
        reveal(leave, in: app)
        leave.tap()
        let confirm = app.buttons["confirm-leave"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["leave-explanation"].label.contains("James can invite you back"))
        snapshot("a6-01-leave")
        confirm.waitToSettle()
        confirm.tap()
        XCTAssertTrue(app.buttons["start-household"].waitForExistence(timeout: 10), "Gone from this phone, without a removed screen")
        snapshot("a6-02-left")
    }

    func testTheOwnerIsPointedToRemovingSomeone() {
        let app = launch(["-sampleHousehold", "-me", "James", "-debugSharing", "joined", "-debugSyncStatus", "upToDate", "-startScreen", "you"])
        let leave = app.buttons["leave-household"]
        XCTAssertTrue(leave.waitForExistence(timeout: 60))
        reveal(leave, in: app)
        leave.tap()
        let manage = app.buttons["manage-members"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["leave-explanation"].label.hasPrefix("It's stored in your iCloud, so leaving would delete it"))
        snapshot("a6-03-owner")
        manage.waitToSettle()
        manage.tap()

        // Removing Mia's iPhone: the person stays.
        let mia = app.buttons["person-Mia"]
        XCTAssertTrue(mia.waitForExistence(timeout: 5))
        mia.tap()
        let remove = app.buttons["remove-devices"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        let confirm = app.buttons["Remove"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snapshot("a6-04-remove")
        confirm.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element(app, beginningWith: "Not yet").waitForExistence(timeout: 5), "Mia stays, without a phone")
    }

    // MARK: E4

    func testStorage() {
        let app = launch(["-sampleHousehold", "-me", "James", "-debugSharing", "joined", "-debugSyncStatus", "upToDate", "-startScreen", "you", "-debugYouPage", "storage"])
        let breakdown = app.staticTexts["storage-breakdown"]
        XCTAssertTrue(breakdown.waitForExistence(timeout: 60))
        XCTAssertTrue(breakdown.label.contains("Photos"), breakdown.label)
        XCTAssertEqual(app.staticTexts["storage-home"].label, "Stored in your iCloud")
        snapshot("e4-01-owner")
    }

    func testStorageWhenTheOwnersICloudIsFull() {
        let app = launch(["-sampleHousehold", "-me", "Mia", "-debugSharing", "member", "-debugSyncStatus", "iCloudFull", "-startScreen", "you", "-debugYouPage", "storage"])
        let full = app.descendants(matching: .any)["storage-full"].firstMatch
        XCTAssertTrue(full.waitForExistence(timeout: 60))
        XCTAssertTrue(element(app, beginningWith: "Sync is paused: James's iCloud is full").exists)
        XCTAssertEqual(app.staticTexts["storage-home"].label, "Stored in James's iCloud")
        snapshot("e4-02-member-full")
    }
}
