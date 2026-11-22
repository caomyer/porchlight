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
        MainActor.assumeIsolated { restoreLightLook() }
        super.tearDown()
    }

    /// The pinned day (`UITestClock`) at 6:40 pm, so a snapped meal is guessed to be dinner.
    private static var dinnerTime: String {
        UITestClock.at(18, 40)
    }

    private func launch(_ arguments: [String] = [], household: [String] = ["-sampleHousehold"]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = household + ["-debugCompanionNow", Self.dinnerTime, "-me", "James", "-startScreen", "food"] + arguments
        app.launch()
        // `-debugFoodView` opens something over the diary straight away.
        if !arguments.contains("-debugFoodView") {
            XCTAssertTrue(app.staticTexts["What we ate"].waitForExistence(timeout: 60))
        }
        waitUntilResponsive(app)
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
        tapToastAction(app)
        let pager = app.otherElements["meal-pager"].exists ? app.otherElements["meal-pager"] : app.buttons["meal-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5), "Open goes to the new meal")
        XCTAssertTrue(element(app, beginningWith: "You and Mia").exists || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "You and Mia")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "added by you")).firstMatch.exists, "Credited to this phone")
        snapshot("b5-24-new-meal")
    }

    // MARK: Other weeks

    /// Back a week on the week's card, open one of its meals and come back to the same
    /// week, fill an empty slot there (the saved meal stays in its week), then back to
    /// this week. The pager's words and limits are PocketFoodWeeksTests'; its looks are
    /// PocketFoodScreenTests'.
    func testChangingWeeks() {
        let app = launch(["-debugCamera", "sample", "-cameraAccess", "allowed"])
        let name = app.staticTexts["week-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(name.label.hasPrefix("This week"), name.label)
        XCTAssertFalse(app.buttons["week-forward"].exists, "Nothing after today")
        app.buttons["week-back"].tap()
        XCTAssertTrue(app.buttons["week-this"].waitForExistence(timeout: 5), "Away from this week, the way back")
        XCTAssertTrue(name.label.hasPrefix("Last week"), name.label)
        snapshot("b5-30-last-week")

        // Last week's bento box opens, and Back comes to the same week.
        let bento = app.buttons["meal-Bento box"]
        reveal(bento, in: app)
        bento.tap()
        XCTAssertTrue(app.buttons["edit-meal"].waitForExistence(timeout: 5), "On the meal's page")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(name.label.hasPrefix("Last week"), "Back lands on the week it left: \(name.label)")

        app.buttons["week-this"].tap()
        XCTAssertTrue(name.label.hasPrefix("This week"), name.label)
        XCTAssertFalse(app.buttons["week-this"].exists)
        XCTAssertTrue(element(app, beginningWith: "On this day").exists, "This week has \"On this day\" again")
    }

    /// A slot nobody filled thirteen days ago: snapped into, the meal stays in that week,
    /// and the diary stays on it. A test of its own: with the weeks above it was one test of
    /// 94 to 121 seconds.
    func testAPastSlotsMealStaysInItsWeek() {
        let app = launch(["-debugCamera", "sample", "-cameraAccess", "allowed"])
        let name = app.staticTexts["week-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.buttons["week-back"].tap()
        XCTAssertTrue(app.buttons["week-this"].waitForExistence(timeout: 5))
        XCTAssertTrue(name.label.hasPrefix("Last week"), name.label)

        let slot = app.buttons["plate-\(UITestClock.day(-13))-Lunch"]
        reveal(slot, in: app)
        slot.tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 5))
        app.buttons["shutter"].tap()
        let dish = app.textFields["dish"]
        XCTAssertTrue(dish.waitForExistence(timeout: 5))
        type("Leftover soup", into: dish, in: app)
        app.typeText("\n")
        let save = app.buttons["save-meal"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.otherElements["toast"].waitForExistence(timeout: 8))
        XCTAssertTrue(name.label.hasPrefix("Last week"), "A past slot's meal shows in its week: \(name.label)")
        // Sunday is the week's last day card, and the diary builds its cards as they scroll in.
        let soup = app.buttons["meal-Leftover soup"]
        reveal(soup, in: app)
        XCTAssertTrue(soup.exists, "It is in last week's diary")
    }

    // MARK: Where, one kind or several

    /// A delivery dinner at the office: Delivery and Company picked together, saved,
    /// shown as both, and both picked again when the meal is edited. The last kind picked
    /// can't be taken off.
    func testWhereTakesSeveralKinds() {
        let app = launch(["-debugCamera", "sample", "-cameraAccess", "allowed"])
        app.buttons["snap-meal"].tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 5))
        app.buttons["shutter"].tap()
        let dish = app.textFields["dish"]
        XCTAssertTrue(dish.waitForExistence(timeout: 5))
        type("Bento", into: dish, in: app)

        let home = app.buttons["source-home"], delivery = app.buttons["source-delivery"], company = app.buttons["source-company"]
        reveal(home, in: app)
        XCTAssertTrue(home.isSelected, "A new meal starts home-cooked")
        delivery.tap()
        XCTAssertTrue(delivery.isSelected && !home.isSelected, "The first tap picks Delivery instead of the guess")
        // The restaurant field opens under the pills; let it settle before the next tap.
        company.waitToSettle()
        company.tap()
        XCTAssertTrue(delivery.isSelected && company.isSelected, "A second kind joins the first")
        // What each further tap does (off again, never the last one) is `MealSourcesTests`.
        XCTAssertTrue(app.textFields["Restaurant"].waitForExistence(timeout: 5), "Delivery asks from where")
        snapshot("where-10-phone-two-kinds")

        let save = app.buttons["save-meal"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.otherElements["toast"].waitForExistence(timeout: 8))
        tapToastAction(app)
        let pager = app.otherElements["meal-pager"].exists ? app.otherElements["meal-pager"] : app.buttons["meal-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5), "Open goes to the new meal")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Delivery · Company")).firstMatch.exists, "The page says both")
        snapshot("where-11-phone-meal")

        app.buttons["edit-meal"].tap()
        let editDelivery = app.buttons["source-delivery"]
        XCTAssertTrue(editDelivery.waitForExistence(timeout: 5))
        reveal(editDelivery, in: app)
        XCTAssertTrue(editDelivery.isSelected && app.buttons["source-company"].isSelected, "Both are picked when it opens to edit")
        XCTAssertFalse(app.buttons["source-home"].isSelected)
        app.buttons["source-home"].tap()
        XCTAssertTrue(app.buttons["source-home"].isSelected && editDelivery.isSelected, "Editing adds, with no guess to replace")
        snapshot("where-12-phone-edit")
    }

    /// The Where pills in the night look at the largest text size, in one launch: both looks
    /// at once is the hardest case for them, and a look costs a launch.
    func testWhereLooks() {
        XCUIDevice.shared.appearance = .dark
        let app = launch(["-debugCamera", "sample", "-cameraAccess", "allowed"] + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["snap-meal"].tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 5))
        app.buttons["shutter"].tap()
        let delivery = app.buttons["source-delivery"]
        XCTAssertTrue(delivery.waitForExistence(timeout: 5))
        reveal(delivery, in: app)
        waitUntilResponsive(app)
        delivery.waitToSettle()
        delivery.tap()
        XCTAssertTrue(delivery.wait(for: \.isSelected, toEqual: true, timeout: 10), "Delivery is picked")
        let company = app.buttons["source-company"]
        reveal(company, in: app)
        company.waitToSettle()
        company.tap()
        XCTAssertTrue(company.wait(for: \.isSelected, toEqual: true, timeout: 10), "Company joins it")
        XCTAssertTrue(delivery.isSelected)
        snapshot("where-20-phone-largest-dark")
    }

    // MARK: Cover and reframe, as on the wall

    /// The photo in a tile of the photo row: "photo-<id>-centered" or "photo-<id>-framed".
    private func photo(_ index: Int, in app: XCUIApplication) -> String {
        let tile = app.descendants(matching: .any)["meal-photo-\(index)"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "Photo \(index + 1) is in the row")
        let image = tile.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo-'")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        return image.identifier
    }

    /// Taps a photo in the row and picks one of its choices.
    private func choose(_ choice: String, onPhoto index: Int, in app: XCUIApplication) {
        tapPhoto(index, in: app)
        let button = app.buttons[choice]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Tapping a photo offers \(choice)")
        button.tap()
    }

    /// Taps a photo in the row in its own middle: the tile's frame also holds its × and cover tag.
    private func tapPhoto(_ index: Int, in app: XCUIApplication) {
        let tile = app.descendants(matching: .any)["meal-photo-\(index)"].firstMatch
        reveal(tile, in: app)
        let image = tile.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo-'")).firstMatch
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Makes the second photo the cover, then reframes it, zoomed in; returns its photo.
    private func coverAndReframe(_ app: XCUIApplication, shot: String) -> String {
        let second = photo(1, in: app)
        choose("Make cover", onPhoto: 1, in: app)
        XCTAssertEqual(photo(0, in: app), second, "The second photo is the cover now")
        snapshot("\(shot)-row")
        tapPhoto(0, in: app)  // the cover has only Reframe, which a tap opens straight away
        let window = app.descendants(matching: .any)["reframe-window"].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Reframe opens the photo to frame")
        app.buttons["Zoom in"].tap()
        app.buttons["Zoom in"].tap()
        snapshot("\(shot)-reframe")
        app.buttons["reframe-done"].tap()
        XCTAssertTrue(window.waitForNonExistence(timeout: 10))
        let framed = photo(0, in: app)
        XCTAssertEqual(framed, second.replacingOccurrences(of: "-centered", with: "-framed"), "The cover is reframed: \(framed)")
        return framed
    }

    /// Snapping a meal: two shots, the second made the cover and reframed, saved, and the
    /// meal's own editor shows that cover, framed.
    func testCoverAndReframeWhenSnapping() {
        let app = launch(["-debugCamera", "sample", "-cameraAccess", "allowed"])
        app.buttons["snap-meal"].tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 5))
        app.buttons["shutter"].tap()
        XCTAssertTrue(app.textFields["dish"].waitForExistence(timeout: 5))
        let another = app.buttons["another-photo"]
        reveal(another, in: app)
        another.tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 5))
        app.buttons["shutter"].tap()
        XCTAssertTrue(app.textFields["dish"].waitForExistence(timeout: 5))
        _ = photo(1, in: app)
        let cover = coverAndReframe(app, shot: "parity-10-new")
        let dish = app.textFields["dish"]
        reveal(dish, in: app)
        type("Pho", into: dish, in: app)
        let save = app.buttons["save-meal"]
        reveal(save, in: app)
        save.tap()

        XCTAssertTrue(app.otherElements["toast"].waitForExistence(timeout: 8))
        tapToastAction(app)
        let edit = app.buttons["edit-meal"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Open goes to the new meal")
        snapshot("parity-12-new-saved")
        reveal(edit, in: app)
        edit.tap()
        XCTAssertEqual(photo(0, in: app), cover, "Saved with that cover, framed")
    }

    /// Reframing a photo that isn't the cover: the action sheet's Reframe opens the reframe
    /// sheet as the action sheet goes, and Done brings back the row with that photo framed.
    func testReframingAnotherPhotoWhenEditing() {
        let app = launch(["-samplePhotoMeals"])
        let meal = app.buttons["meal-Avocado toast"]
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        meal.tap()
        let edit = app.buttons["edit-meal"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForExistence(timeout: 5))
        let cover = photo(0, in: app)
        let second = photo(1, in: app)
        XCTAssertTrue(second.hasSuffix("-centered"), "The sample's second photo starts unframed: \(second)")
        choose("Reframe", onPhoto: 1, in: app)
        let window = app.descendants(matching: .any)["reframe-window"].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Reframe opens the second photo to frame")
        app.buttons["Zoom in"].tap()
        snapshot("parity-23-reframe-second")
        app.buttons["reframe-done"].tap()
        XCTAssertTrue(window.waitForNonExistence(timeout: 10), "Done goes back to the row")
        XCTAssertEqual(photo(1, in: app), second.replacingOccurrences(of: "-centered", with: "-framed"), "The second photo is framed")
        XCTAssertEqual(photo(0, in: app), cover, "and the cover is as it was")
    }

    /// Editing a meal: the same row and reframe as the wall's editor, saved and shown again.
    func testCoverAndReframeWhenEditing() {
        let app = launch(["-samplePhotoMeals"])
        let meal = app.buttons["meal-Avocado toast"]
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        meal.tap()
        let edit = app.buttons["edit-meal"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["add-photo-tile"].firstMatch.exists, "More photos can be added while editing, as on the wall")
        let cover = coverAndReframe(app, shot: "parity-20-edit")
        let save = app.buttons["save-edit"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForNonExistence(timeout: 5))
        snapshot("parity-22-edit-saved")
        reveal(edit, in: app)
        edit.tap()
        XCTAssertEqual(photo(0, in: app), cover, "Saved with that cover, framed")
    }

    /// The photo row and the reframe screen in the night look at the largest size, in one
    /// launch of the editor. A new meal's row is the same row (the journeys above use it), so
    /// it is not launched again here for a second picture of it.
    func testPhotoRowAndReframeLooks() {
        XCUIDevice.shared.appearance = .dark
        let app = launch(["-samplePhotoMeals"] + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let meal = app.buttons["meal-Avocado toast"]
        reveal(meal, in: app)
        meal.tap()
        let edit = app.buttons["edit-meal"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForExistence(timeout: 5))
        _ = photo(0, in: app)
        snapshot("parity-30-edit-row-largest-dark")
        tapPhoto(0, in: app)  // the cover opens straight to Reframe
        XCTAssertTrue(app.descendants(matching: .any)["reframe-window"].firstMatch.waitForExistence(timeout: 10))
        let done = app.buttons["reframe-done"]
        reveal(done, in: app)
        XCTAssertTrue(done.isHittable, "Done is in reach at this size")
        snapshot("parity-31-reframe-largest-dark")
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

    // The empty diary ("Nothing in the diary this week") is checked where a person meets it:
    // `PhoneSetupTests.testStartingAHouseholdOnThisPhone`, on a household just started.

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

    /// The same in the night look at the largest size: the two looks share their four launches.
    func testPaperUnderTheStatusBarAtNightAtTheLargestSize() {
        XCUIDevice.shared.appearance = .dark
        scrolledScreens(look: "largest-dark", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
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
