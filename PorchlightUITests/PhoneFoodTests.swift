import XCTest

/// Food on the phone (journey B5): the week's plates and the diary, a meal's page, and
/// snapping a meal with the sample camera (the simulator has none), from asking for the
/// camera to the toast and the new plate. Also shot empty, in the night look and at the
/// largest text size. Runs only on an iPhone (`scripts/test.sh --phone`).
@MainActor
final class PhoneFoodTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    override func tearDown() {
        MainActor.assumeIsolated { XCUIDevice.shared.appearance = .light }
        super.tearDown()
    }

    /// Today at 6:40 pm, so a snapped meal is guessed to be dinner.
    private static var dinnerTime: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02dT18:40", parts.year!, parts.month!, parts.day!)
    }

    private func launch(_ arguments: [String] = [], household: [String] = ["-sampleHousehold"]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = household + ["-debugCompanionNow", Self.dinnerTime, "-me", "James", "-startScreen", "food"] + arguments
        app.launch()
        // `-debugFoodView` opens something over the diary straight away.
        if !arguments.contains("-debugFoodView") {
            XCTAssertTrue(app.staticTexts["What we ate"].waitForExistence(timeout: 60))
        }
        return app
    }

    func testWeekAndDiary() {
        let app = launch()
        XCTAssertTrue(element(app, beginningWith: "This week's meals").exists || app.buttons.matching(identifier: "snap-meal").firstMatch.exists)
        XCTAssertTrue(app.buttons["snap-meal"].isHittable, "Snap a meal is always in reach")
        XCTAssertTrue(element(app, beginningWith: "On this day").exists, "A year ago's turkey")
        snapshot("b5-01-week")
        let today = app.buttons["meal-Avocado toast"]
        XCTAssertTrue(today.label.contains("added by you"), "Who added it: \(today.label)")
        let sushi = app.buttons["meal-Sushi night"]
        reveal(sushi, in: app)
        XCTAssertTrue(sushi.label.contains("Sakura Sushi Bar"), "Where it came from: \(sushi.label)")
        snapshot("b5-02-diary")
    }

    func testMealPage() {
        let app = launch()
        let latte = app.buttons["meal-Oat latte"]
        reveal(latte, in: app)
        let toast = app.buttons["meal-Avocado toast"]
        reveal(toast, in: app)
        toast.tap()
        let pager = app.otherElements["meal-pager"].exists ? app.otherElements["meal-pager"] : app.buttons["meal-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertTrue(pager.label.contains("photo 1 of 2"), "Today's breakfast has two photos: \(pager.label)")
        pager.swipeLeft()
        XCTAssertTrue(pager.label.contains("photo 2 of 2"), "Swiping turns to the next photo")
        XCTAssertTrue(app.buttons["edit-meal"].exists)
        XCTAssertTrue(app.buttons["remove-meal"].exists)
        snapshot("b5-10-detail")
        pager.tap()
        XCTAssertTrue(app.images["whole-photo"].waitForExistence(timeout: 5), "Tapping shows the whole photo")
        snapshot("b5-11-whole-photo")
        app.images["whole-photo"].tap()

        app.buttons["edit-meal"].tap()
        let dish = app.textFields["dish"]
        XCTAssertTrue(dish.waitForExistence(timeout: 5))
        type("Avocado toast and eggs", into: dish, in: app)
        app.buttons["save-edit"].tap()
        XCTAssertTrue(app.staticTexts["Avocado toast and eggs"].waitForExistence(timeout: 5) || element(app, beginningWith: "Avocado toast and eggs").waitForExistence(timeout: 5), "The edit shows right away")
    }

    func testSnappingAMeal() {
        let app = launch(["-debugCamera", "sample", "-cameraAccess", "notDetermined"])
        app.buttons["snap-meal"].tap()
        XCTAssertTrue(app.buttons["allow-camera"].waitForExistence(timeout: 5), "It says what the camera is for before iOS asks")
        XCTAssertTrue(element(app, beginningWith: "Dinner · guessed from the time").exists)
        snapshot("b5-20-camera-ask")
        app.buttons["allow-camera"].tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 5))
        snapshot("b5-21-camera")
        app.buttons["shutter"].tap()

        let dish = app.textFields["dish"]
        XCTAssertTrue(dish.waitForExistence(timeout: 5), "A shot goes straight to the details")
        let youAte = app.buttons.matching(NSPredicate(format: "label == 'You' AND identifier != 'you'")).firstMatch
        XCTAssertTrue(youAte.isSelected, "Who ate starts as me")
        type("Pho", into: dish, in: app)
        app.buttons["Mia"].tap()
        let save = app.buttons["save-meal"]
        reveal(save, in: app)
        XCTAssertTrue(save.label.contains("Save to"), save.label)
        snapshot("b5-22-details")
        save.tap()

        let toast = app.otherElements["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 8), "Back on the diary, a toast says where it went")
        XCTAssertTrue(element(app, beginningWith: "Saved to").exists)
        snapshot("b5-23-saved")
        app.buttons["toast-action"].tap()
        let pager = app.otherElements["meal-pager"].exists ? app.otherElements["meal-pager"] : app.buttons["meal-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5), "Open goes to the new meal")
        XCTAssertTrue(element(app, beginningWith: "You and Mia").exists || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "You and Mia")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "added by you")).firstMatch.exists, "Credited to this phone")
        snapshot("b5-24-new-meal")
    }

    func testCameraTurnedOff() {
        let app = launch(["-cameraAccess", "denied"])
        app.buttons["snap-meal"].tap()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["from-photos"].exists, "Photos still works")
        snapshot("b5-25-camera-off")
        app.buttons["no-photo"].tap()
        XCTAssertTrue(app.textFields["dish"].waitForExistence(timeout: 5), "A meal can be saved without a photo")
        snapshot("b5-26-no-photo")
    }

    func testEmptyHousehold() {
        let app = launch(household: ["-sampleHousehold", "-sampleFood", "none"])
        XCTAssertTrue(element(app, beginningWith: "Nothing in the diary this week").exists)
        snapshot("b5-30-empty")
    }

    func testNightLook() {
        XCUIDevice.shared.appearance = .dark
        let app = launch()
        snapshot("b5-40-week-dark")
        let toast = app.buttons["meal-Avocado toast"]
        reveal(toast, in: app)
        toast.tap()
        XCTAssertTrue(app.buttons["edit-meal"].waitForExistence(timeout: 5))
        snapshot("b5-41-detail-dark")
    }

    // MARK: Paper under the status bar

    func testPaperUnderTheStatusBar() { scrolledScreens(look: "light") }

    func testPaperUnderTheStatusBarAtNight() {
        XCUIDevice.shared.appearance = .dark
        scrolledScreens(look: "dark")
    }

    func testPaperUnderTheStatusBarAtTheLargestSize() {
        scrolledScreens(look: "largest", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }

    /// The diary, a meal's page, the camera and a new meal's details, each scrolled: nothing
    /// shows under the clock.
    private func scrolledScreens(look: String, _ arguments: [String] = []) {
        let app = launch(["-debugCamera", "sample", "-cameraAccess", "allowed"] + arguments)
        expectPaperUnderStatusBar(app, "b5-60-diary-scrolled-\(look)")

        app.terminate()
        let page = launch(["-debugFoodView", "detail"] + arguments)
        XCTAssertTrue(page.descendants(matching: .any)["meal-pager"].waitForExistence(timeout: 60))
        expectPaperUnderStatusBar(page, "b5-61-meal-scrolled-\(look)")

        page.terminate()
        let snap = launch(["-debugCamera", "sample", "-cameraAccess", "allowed", "-debugFoodView", "snap"] + arguments)
        XCTAssertTrue(snap.buttons["shutter"].waitForExistence(timeout: 60))
        expectPaperUnderStatusBar(snap, "b5-62-camera-scrolled-\(look)")

        snap.terminate()
        let details = launch(["-debugFoodView", "details"] + arguments)
        XCTAssertTrue(details.textFields["dish"].waitForExistence(timeout: 60))
        expectPaperUnderStatusBar(details, "b5-63-details-scrolled-\(look)")
    }

    func testLargestText() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-debugCamera", "sample", "-cameraAccess", "allowed"])
        let window = app.windows.firstMatch.frame
        let snap = app.buttons["snap-meal"]
        XCTAssertTrue(window.contains(snap.frame), "Snap a meal is whole on screen")
        snapshot("b5-50-week-largest")
        let toast = app.buttons["meal-Avocado toast"]
        reveal(toast, in: app)
        snapshot("b5-51-diary-largest")
        snap.tap()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        reveal(shutter, in: app)
        snapshot("b5-52-camera-largest")
        shutter.tap()
        let save = app.buttons["save-meal"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        reveal(save, in: app)
        XCTAssertTrue(window.contains(save.frame), "Save is whole on screen")
        snapshot("b5-53-details-largest")
    }
}
