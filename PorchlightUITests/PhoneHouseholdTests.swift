import XCTest

/// Households on the iPhone: the welcome, joining from an invite (A4), the removed screen
/// (A6), sync's banners on Today (E5), and the You sheet's people and invite (A3, E1).
/// Sharing is the fake (`-debugJoin`, `-debugSharing`). Runs only on an iPhone simulator
/// (`scripts/test.sh --phone`); the iPad run skips it.
@MainActor
final class PhoneHouseholdTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    override func tearDown() {
        MainActor.assumeIsolated { restoreLightLook() }
        super.tearDown()
    }

    private static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    // MARK: Two households (A5)

    private static var evening: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02dT17:20", parts.year!, parts.month!, parts.day!)
    }

    private func twoHouseholds(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(["-sampleHousehold", "-sampleSecondHousehold", "-me", "James", "-debugCompanionNow", Self.evening] + extra)
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        return app
    }

    /// Today names the household, You lists both with a tick, and one tap switches every tab.
    func testSwitchingHouseholds() {
        let app = twoHouseholds()
        let switcher = app.buttons["household-switcher"]
        XCTAssertTrue(switcher.exists, "Today's header names the household when there are two")
        XCTAssertEqual(switcher.label, "The Lake House")
        XCTAssertTrue(app.buttons["week-Yo-Yo"].exists || app.staticTexts["Yo-Yo"].exists, "The Lake House's companion")
        snapshot("a5-10-today-header")
        switcher.tap()

        let rosas = app.buttons["household-Grandma Rosa's"]
        XCTAssertTrue(rosas.waitForExistence(timeout: 5), "You lists both households")
        XCTAssertTrue(app.buttons["household-The Lake House"].label.contains("You are James · 2 people"), app.buttons["household-The Lake House"].label)
        XCTAssertEqual(app.buttons["household-The Lake House"].value as? String, "Showing now")
        XCTAssertTrue(app.buttons["another-household"].exists, "Join or start another")
        snapshot("a5-11-your-households")
        rosas.tap()

        XCTAssertTrue(app.buttons["household-switcher"].waitForExistence(timeout: 10))
        let switched = expectation(for: NSPredicate(format: "label == %@", "Grandma Rosa's"), evaluatedWith: app.buttons["household-switcher"])
        wait(for: [switched], timeout: 10)
        XCTAssertTrue(element(app, beginningWith: "Tomatoes").waitForExistence(timeout: 10), "Today shows Grandma Rosa's tomatoes")
        XCTAssertFalse(app.staticTexts["Yo-Yo"].exists, "and nothing of The Lake House")
        snapshot("a5-12-today-rosas")

        app.tabBars.buttons["Lists"].tap()
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["PRODUCE"].exists, "The Lake House's groceries stay there")
    }

    /// The night look of the switcher and the header, for review.
    func testSwitcherNightLook() {
        XCUIDevice.shared.appearance = .dark
        let app = twoHouseholds()
        XCTAssertTrue(app.buttons["household-switcher"].exists)
        snapshot("a5-20-today-header-dark")
        app.buttons["household-switcher"].tap()
        XCTAssertTrue(app.buttons["household-Grandma Rosa's"].waitForExistence(timeout: 5))
        snapshot("a5-21-your-households-dark")
    }

    /// At the largest text: the household under the date, whole, and the slots' times and
    /// statuses. (Queries of the You sheet at this size take half a minute each, so the
    /// switcher's list is left to the eye.)
    func testHeaderAndSlotsLargestText() {
        let app = twoHouseholds(Self.largestText)
        XCTAssertEqual(app.buttons["household-switcher"].label, "The Lake House")
        snapshot("a5-22-today-header-largest")
        // Too narrow for "5-8pm · open now": the status sits under the time, dot and all gone.
        // The tile reads as one element: its title, time and status.
        let evening = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Evening, 5-8pm, open now")).firstMatch
        // Today builds its cards as they come near the screen, so scroll down to it first.
        for _ in 0..<8 where !evening.exists { app.swipeUp() }
        XCTAssertTrue(evening.waitForExistence(timeout: 5), "The evening slot's time and status read without a separator dot")
        reveal(evening, in: app)
        snapshot("a5-23-today-slots-largest")
    }

    /// With one household, nothing names it and You has no list, only "Join or start another".
    func testOneHouseholdHasNoSwitcher() {
        let app = launch(["-sampleHousehold", "-me", "James", "-debugCompanionNow", Self.evening])
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.buttons["household-switcher"].exists)
        let you = app.buttons["you"]
        // Today is still settling after launch: a tap during that is dropped.
        you.waitToSettle()
        you.tap()
        let another = app.buttons["another-household"]
        XCTAssertTrue(another.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["household-The Lake House"].exists)
        reveal(another, in: app)
        another.tap()
        XCTAssertTrue(app.buttons["start-another"].waitForExistence(timeout: 5), "Start or join another")
        snapshot("a5-30-another")
    }

    // MARK: Welcome and joining

    func testTheWelcomeExplainsBothWaysIn() {
        let app = launch(["-resetData"])
        XCTAssertTrue(app.buttons["start-household"].waitForExistence(timeout: 60), "Two doors: start one here")
        app.buttons["join-one"].tap()
        XCTAssertTrue(app.staticTexts["Open the invite someone sent you"].waitForExistence(timeout: 5), "or join one, and how")
        XCTAssertTrue(app.staticTexts["Or scan your family's code"].exists)
        snapshot("phone-100-welcome")
    }

    func testJoiningFromAnInvite() {
        let app = launch(["-resetData", "-debugJoin", "preview"])
        XCTAssertTrue(app.staticTexts["Join The Lake House?"].waitForExistence(timeout: 60), "The invite opens a preview first")
        XCTAssertTrue(app.staticTexts["James invited you. You'll share walks, meals, chores and lists with the household."].exists)
        XCTAssertTrue(app.staticTexts["Stored in James's iCloud"].exists)
        snapshot("phone-101-join-preview")

        app.buttons["join"].tap()
        XCTAssertTrue(app.staticTexts["Which one is you?"].waitForExistence(timeout: 30))
        let mia = app.buttons["who-Mia"]
        let james = app.buttons["who-James"]
        XCTAssertTrue(mia.label.contains("Hasn't joined yet"), mia.label)
        XCTAssertTrue(james.label.contains("On James's iPhone"), james.label)
        XCTAssertLessThan(mia.frame.minY, james.frame.minY, "People without a phone come first")
        mia.tap()
        XCTAssertEqual(app.buttons["continue-as"].label, "Continue as Mia")
        snapshot("phone-102-join-who")

        app.buttons["continue-as"].tap()
        XCTAssertTrue(app.staticTexts["Bringing everything in"].waitForExistence(timeout: 10))
        snapshot("phone-103-join-bringing-in")
        app.buttons["go-to-today"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Mia"].waitForExistence(timeout: 10), "Joining ends on Today")
    }

    func testImNewHere() {
        let app = launch(["-resetData", "-debugJoin", "preview"])
        XCTAssertTrue(app.buttons["join"].waitForExistence(timeout: 60))
        app.buttons["join"].tap()
        let new = app.buttons["who-new"]
        XCTAssertTrue(new.waitForExistence(timeout: 30))
        new.tap()
        let name = app.textFields["new-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        type("Ava", into: name, in: app)
        let proceed = app.buttons["continue-as"]
        let named = expectation(for: NSPredicate(format: "label == %@", "Continue as Ava"), evaluatedWith: proceed)
        wait(for: [named], timeout: 5)
        snapshot("phone-104-join-new-here")
        app.buttons["continue-as"].tap()
        XCTAssertTrue(app.buttons["go-to-today"].waitForExistence(timeout: 10))
        app.buttons["go-to-today"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Ava"].waitForExistence(timeout: 10))
    }

    /// By hand only: "I'm new here" twelve times over, each from a fresh launch, typing a name
    /// once with no second try and no tap on the field, and counting the rounds where the
    /// keys never arrive. On November 20 the name field twice showed its cursor with the
    /// keyboard up while typed keys went nowhere (docs/design/testing.md, "Known and not
    /// yet explained"). `testImNewHere` types through a helper that taps the field again
    /// before a second try, which would hide that; this does not.
    /// `TEST_RUNNER_PORCHLIGHT_NEW_HERE=1 xcodebuild test ... -only-testing:PorchlightUITests/PhoneHouseholdTests/testImNewHereAgainAndAgainByHand`.
    func testImNewHereAgainAndAgainByHand() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PORCHLIGHT_NEW_HERE"] == "1", "Run by hand")
        var lost: [Int] = []
        for round in 1...12 {
            let app = launch(["-resetData", "-debugJoin", "preview"])
            XCTAssertTrue(app.buttons["join"].waitForExistence(timeout: 60))
            app.buttons["join"].tap()
            let new = app.buttons["who-new"]
            XCTAssertTrue(new.waitForExistence(timeout: 30))
            new.tap()
            let name = app.textFields["new-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: name)
            XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 10), .completed, "round \(round): the field takes the focus by itself")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "round \(round): the keyboard comes up")
            for character in "Ava" { app.typeText(String(character)) }
            let arrived = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ava"), object: name)
            if XCTWaiter().wait(for: [arrived], timeout: 3) != .completed {
                lost.append(round)
                snapshot("new-here-lost-keys-round-\(round)")
            }
            app.terminate()
        }
        XCTAssertTrue(lost.isEmpty, "Typed keys never arrived in \(lost.count) of 12 rounds: \(lost)")
    }

    func testAnAccountTheHouseholdKnowsSkipsWhoYouAre() {
        let app = launch(["-resetData", "-debugJoin", "known"])
        XCTAssertTrue(app.buttons["join"].waitForExistence(timeout: 60))
        app.buttons["join"].tap()
        XCTAssertTrue(app.staticTexts["Bringing everything in"].waitForExistence(timeout: 30), "This iCloud user is already Mia")
        XCTAssertFalse(app.staticTexts["Which one is you?"].exists)
        app.buttons["go-to-today"].tap()
        XCTAssertTrue(app.staticTexts["Hi, Mia"].waitForExistence(timeout: 10))
    }

    func testAJoinThatFailsCanBeTriedAgain() {
        let app = launch(["-resetData", "-debugJoin", "failing"])
        XCTAssertTrue(app.buttons["join"].waitForExistence(timeout: 60))
        app.buttons["join"].tap()
        let banner = app.descendants(matching: .any)["join-failed"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Offline, a banner offers to try again")
        XCTAssertTrue(app.staticTexts["Join The Lake House?"].exists, "and nothing is half joined")
        snapshot("phone-105-join-failed")
        banner.tap()
        XCTAssertTrue(app.staticTexts["Which one is you?"].waitForExistence(timeout: 30))
    }

    // MARK: Removed

    func testARemovedHouseholdSaysSoOnce() {
        let app = launch(["-resetData", "-debugRemoved"])
        XCTAssertTrue(app.staticTexts["You're no longer in The Lake House"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["James removed this iPhone from the household, or stopped sharing it. What you logged stays with the household."].exists)
        snapshot("phone-106-removed")
        app.buttons["removed-ok"].tap()
        XCTAssertTrue(app.buttons["start-household"].waitForExistence(timeout: 10), "then the household is gone from this phone")
    }

    // MARK: Sync banners

    /// One banner on Today, with its fix: a member sees whose iCloud is full, and a restored
    /// copy's "Choose" opens the choice in You. What the banner says in each of sync's states
    /// is `ArrivalsTests` (unit), so the app is not launched once per state here.
    func testSyncBannersOnToday() {
        var app = launch(["-sampleHousehold", "-me", "Mia", "-debugSharing", "member", "-debugSyncStatus", "iCloudFull"])
        var banner = app.descendants(matching: .any)["sync-banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 60), "A stuck sync shows on Today")
        XCTAssertTrue(banner.label.hasPrefix("Sync paused: James's iCloud is full"), "It names the owner to a member: \(banner.label)")
        snapshot("phone-110-banner-iCloudFull")
        app.terminate()

        app = launch(["-sampleHousehold", "-me", "Mia", "-debugSharing", "member", "-debugSyncStatus", "restoredCopy"])
        banner = app.descendants(matching: .any)["sync-banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 60))
        XCTAssertTrue(banner.label.hasPrefix("Sync is waiting for you"), banner.label)
        snapshot("phone-115-banner-restoredCopy")
        banner.tap()
        XCTAssertTrue(app.buttons["Use what is in iCloud"].waitForExistence(timeout: 5), "Choose opens the choice")
        snapshot("phone-119-restored-choice")
    }

    // MARK: You

    func testYouListsPeopleAndInvites() {
        let app = launch(["-sampleHousehold", "-me", "James", "-debugSharing", "invited", "-debugSyncStatus", "upToDate", "-startScreen", "you"])
        let people = app.descendants(matching: .any)["people-card"]
        XCTAssertTrue(people.waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["Invited, hasn't joined yet"].exists, "Mia is invited")
        XCTAssertTrue(app.staticTexts["No phone yet"].exists, "Ava has no phone")
        snapshot("phone-120-you")

        app.buttons["invite-someone"].tap()
        XCTAssertTrue(app.staticTexts["Invite someone"].waitForExistence(timeout: 5))
        snapshot("phone-121-invite")
        app.buttons["Invite Mia"].tap()
        XCTAssertTrue(app.staticTexts["Join The Lake House on Porchlight"].waitForExistence(timeout: 5), "Invite opens the sharing sheet")
        snapshot("phone-122-invite-sheet")
        app.buttons["invite-done"].tap()
        XCTAssertTrue(app.staticTexts["Join The Lake House on Porchlight"].waitForNonExistence(timeout: 5))
    }

    /// On its own launch: after a sheet over the You sheet closes, iOS 17's accessibility
    /// tree stops seeing the You sheet, though it is on screen.
    func testShowingTheCodeOnThePhone() {
        let app = launch(["-sampleHousehold", "-me", "James", "-debugSharing", "invited", "-debugSyncStatus", "upToDate", "-startScreen", "you"])
        let invite = app.buttons["invite-someone"]
        XCTAssertTrue(invite.waitForExistence(timeout: 60))
        invite.tap()
        let show = app.buttons["show-code"]
        // Once the page has finished sliding in: a tap during the push is dropped.
        let settled = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: show)
        wait(for: [settled], timeout: 10)
        show.tap()
        XCTAssertTrue(app.staticTexts["Join The Lake House"].waitForExistence(timeout: 10), "The code's page opens")
        // Core Image takes a while to start the first time on a simulator.
        XCTAssertTrue(app.images["join-code"].waitForExistence(timeout: 30), "The code is drawn on the phone")
        snapshot("phone-123-join-code")
    }

    /// With sync off, You and the invite page say the household is on this phone only, and
    /// inviting says why it can't.
    func testWithSyncOffTheHouseholdIsOnThisPhoneOnly() {
        let app = launch(["-sampleHousehold", "-me", "James", "-debugSharing", "invited", "-debugSyncStatus", "off", "-startScreen", "you"])
        let home = app.descendants(matching: .any)["household-home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 60))
        XCTAssertTrue(home.label.contains("On this iPhone only"), home.label)
        app.buttons["invite-someone"].tap()
        let explanation = app.staticTexts["invite-explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertEqual(explanation.label, "The household is on this iPhone only, so nobody can join it yet.")
        XCTAssertTrue(app.descendants(matching: .any)["invite-blocker"].firstMatch.label.contains("Turn on iCloud sync to invite phones."))
        snapshot("phone-124-invite-sync-off")

        // The switch is in You: turning sync on lets invites go.
        app.navigationBars.buttons.firstMatch.tap()
        let toggle = app.switches["sync-switch"]
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0")
        snapshot("phone-126-you-sync-off")
        // The switch itself, not the row's label, flips it.
        let knob = toggle.switches.firstMatch
        (knob.exists ? knob : toggle).tap()
        XCTAssertTrue(home.label.contains("Stored in your iCloud"), home.label)
        app.buttons["invite-someone"].tap()
        XCTAssertTrue(app.staticTexts["invite-explanation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["invite-blocker"].exists, "Invites can go once sync is on")
    }

    /// As a member, the household is in its owner's iCloud.
    func testAMemberSeesWhoseICloudItIs() {
        let app = launch(["-sampleHousehold", "-me", "Mia", "-debugSharing", "member", "-debugSyncStatus", "upToDate", "-startScreen", "you"])
        let home = app.descendants(matching: .any)["household-home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 60))
        XCTAssertTrue(home.label.contains("Stored in James's iCloud"), home.label)
        // Only the owner can add people to the share: no way in, and who can.
        XCTAssertFalse(app.buttons["invite-someone"].exists, "A member has nothing to invite with")
        let invite = app.descendants(matching: .any)["invite-someone"].firstMatch
        XCTAssertTrue(invite.label.contains("Only James can add people"), invite.label)
        snapshot("phone-125-you-member")
    }

    func testRenamingThisPhone() {
        let app = launch(["-sampleHousehold", "-me", "James", "-debugSharing", "invited", "-debugSyncStatus", "upToDate", "-startScreen", "you"])
        let device = app.buttons["this-device"]
        XCTAssertTrue(device.waitForExistence(timeout: 60))
        XCTAssertTrue(device.label.hasPrefix("James's iPhone"), device.label)
        device.tap()
        let name = app.textFields["device-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        // Key by key and checked: on a busy simulator a fast typeText drops keys ("W").
        type("Work Phone", into: name, in: app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["this-device"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["this-device"].label.hasPrefix("Work Phone"), app.buttons["this-device"].label)
    }

    // MARK: Looks

    func testNightLook() {
        XCUIDevice.shared.appearance = .dark
        var app = launch(["-resetData", "-debugJoin", "preview"])
        XCTAssertTrue(app.buttons["join"].waitForExistence(timeout: 60))
        snapshot("phone-130-join-preview-dark")
        app.buttons["join"].tap()
        XCTAssertTrue(app.staticTexts["Which one is you?"].waitForExistence(timeout: 30))
        snapshot("phone-131-join-who-dark")
        app.terminate()

        app = launch(["-sampleHousehold", "-me", "James", "-debugSharing", "invited", "-debugSyncStatus", "upToDate", "-startScreen", "you"])
        XCTAssertTrue(app.descendants(matching: .any)["people-card"].waitForExistence(timeout: 60))
        snapshot("phone-132-you-dark")
    }

    func testLargestText() {
        var app = launch(["-resetData", "-debugJoin", "preview"] + Self.largestText)
        let join = app.buttons["join"]
        XCTAssertTrue(join.waitForExistence(timeout: 60))
        reveal(join, in: app)
        snapshot("phone-140-join-preview-largest")
        join.tap()
        let proceed = app.buttons["continue-as"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 30))
        app.buttons["who-Mia"].tap()
        reveal(proceed, in: app)
        XCTAssertEqual(proceed.label, "Continue as Mia")
        snapshot("phone-141-join-who-largest")
        app.terminate()

        app = launch(["-sampleHousehold", "-me", "Mia", "-debugSharing", "member", "-debugSyncStatus", "noAccount"] + Self.largestText)
        let banner = app.descendants(matching: .any)["sync-banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 60))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(banner.frame), "The banner fits, its fix included")
        snapshot("phone-142-banner-largest")
    }
}
