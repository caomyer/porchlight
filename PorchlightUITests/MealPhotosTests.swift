import XCTest

/// Several photos per meal: shots fill the capture form's Photos row instead of saving
/// the meal, can be removed or made the cover, are kept from being lost by accident, and
/// can be paged, added and removed on a saved meal. The simulator has no camera, so
/// `-debugCaptureShots` adds photos through the shutter's path, and sample meals already
/// have photos. Sample launches use their own storage sandbox.
@MainActor
final class MealPhotosTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold"] + arguments
        app.launch()
        _ = app.otherElements.firstMatch.waitForExistence(timeout: 30)
        Thread.sleep(forTimeInterval: 4)
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func photo(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "meal-photo-\(index)").firstMatch
    }

    private func labelled(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Photos wait in the form while the rest is filled in; nothing saves until Save.
    func testShotsWaitInTheFormUntilSave() {
        let app = launch(["-startScreen", "food", "-debugFoodView", "capture", "-debugCaptureShots", "3"])
        XCTAssertTrue(photo(app, 2).waitForExistence(timeout: 20), "Three shots should wait in the Photos row")
        XCTAssertTrue(app.staticTexts["3 photos ready. Fill in anything else, then Save."].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to'")).firstMatch.exists,
                       "Taking photos must not save the meal")
        snapshot("45-capture-three-shots")

        app.buttons["Remove photo 2"].tap()
        XCTAssertTrue(photo(app, 2).waitForNonExistence(timeout: 5), "Removing a shot leaves two")
        XCTAssertTrue(app.staticTexts["2 photos ready. Fill in anything else, then Save."].waitForExistence(timeout: 5))

        // Closing would lose the photos, so it asks first.
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Discard 2 photos?"].waitForExistence(timeout: 5), "Closing with unsaved photos should ask")
        snapshot("46-discard-prompt")
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(app.staticTexts["Discard 2 photos?"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(photo(app, 1).exists, "Keeping on editing keeps the photos")

        let dish = app.textFields["What was it? e.g. Dan dan noodles"]
        dish.tap()
        dish.typeText("Sunday roast\n")
        app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Company'")).firstMatch.tap()
        // The guessed slot depends on the hour, and in the morning today's sample breakfast
        // would stack on top. Today's dinner is always empty in the samples.
        app.buttons["🌙 Dinner"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to'")).firstMatch.waitForExistence(timeout: 10))
        let polaroid = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Dinner: Sunday roast, 2 photos")).firstMatch
        XCTAssertTrue(polaroid.exists, "The saved polaroid should show the meal and its two photos")
        snapshot("47-saved-with-photos")
    }

    /// A saved meal pages through its photos, and Edit removes one only once saved.
    func testPagingAndEditingPhotosOfASavedMeal() {
        let app = launch(["-startScreen", "food"])
        // Today's breakfast is two dishes; the avocado toast on top has two photos.
        let breakfast = labelled(app, startingWith: "Breakfast: Avocado toast and 1 more, 2 photos")
        XCTAssertTrue(breakfast.waitForExistence(timeout: 20), "Today's breakfast shows it has two photos")
        breakfast.tap()

        let pager = app.descendants(matching: .any)["meal-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertEqual(pager.label, "Avocado toast, photo 1 of 2")
        pager.swipeLeft()
        let second = expectation(for: NSPredicate(format: "label == 'Avocado toast, photo 2 of 2'"), evaluatedWith: pager)
        wait(for: [second], timeout: 5)
        XCTAssertTrue(app.buttons["Add photo"].exists, "A saved meal can get more photos")
        snapshot("48-detail-paging")

        app.buttons["Edit"].tap()
        XCTAssertTrue(photo(app, 1).waitForExistence(timeout: 5), "Edit shows the photos")
        app.buttons["Remove photo 2"].tap()
        XCTAssertTrue(photo(app, 1).waitForNonExistence(timeout: 5))
        snapshot("49-edit-photos")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["meal-pager"].label.hasSuffix("of 2"), "Cancel keeps both photos")

        app.buttons["Edit"].tap()
        XCTAssertTrue(photo(app, 1).waitForExistence(timeout: 5))
        app.buttons["Remove photo 2"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["meal-pager"].label, "Avocado toast", "Saving removes the photo")
    }

    /// The camera window is the polaroid's square, and new shots line up right under it.
    func testTheViewfinderIsThePolaroidSquare() {
        let app = launch(["-startScreen", "food", "-debugFoodView", "capture", "-debugCaptureShots", "2"])
        let window = app.descendants(matching: .any)["viewfinder-window"]
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        XCTAssertEqual(window.frame.width, window.frame.height, accuracy: 2, "The viewfinder shows exactly the polaroid's square")
        let shot = photo(app, 1)
        XCTAssertTrue(shot.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(shot.frame.minY, window.frame.maxY, "Shots line up under the camera")
        XCTAssertLessThan(shot.frame.maxX, window.frame.maxX + 1, "Shots sit in the camera's column")
        snapshot("48-square-viewfinder")
    }

    /// The polaroid opens the whole shot, and a photo can be reframed in Edit.
    func testWholePhotoAndReframing() {
        let app = launch(["-startScreen", "food"])
        let breakfast = labelled(app, startingWith: "Breakfast: Avocado toast and 1 more, 2 photos")
        XCTAssertTrue(breakfast.waitForExistence(timeout: 20))
        breakfast.tap()

        let pager = app.descendants(matching: .any)["meal-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.tap()
        let whole = app.descendants(matching: .any)["whole-photo"]
        XCTAssertTrue(whole.waitForExistence(timeout: 5), "Tapping the polaroid shows the whole photo")
        snapshot("49-whole-photo")
        app.staticTexts["Tap anywhere to close"].tap()
        XCTAssertTrue(whole.waitForNonExistence(timeout: 5))

        app.buttons["Edit"].tap()
        let tile = photo(app, 0)
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.55)).tap()
        let reframe = app.buttons["Reframe"]
        XCTAssertTrue(reframe.waitForExistence(timeout: 5), "A photo offers to be reframed")
        reframe.tap()
        let frameWindow = app.descendants(matching: .any)["reframe-window"]
        XCTAssertTrue(frameWindow.waitForExistence(timeout: 5))
        let before = frameWindow.value as? String
        frameWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: frameWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        XCTAssertNotEqual(frameWindow.value as? String, before, "Dragging moves the square")
        snapshot("50-reframe")
        app.buttons["Done"].tap()
        XCTAssertTrue(frameWindow.waitForNonExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForNonExistence(timeout: 5), "The reframed photo saves with the meal")
    }

    /// Making another photo the cover moves it to the front, once.
    func testMakingAnotherPhotoTheCover() {
        let app = launch(["-startScreen", "food"])
        let breakfast = labelled(app, startingWith: "Breakfast: Avocado toast and 1 more, 2 photos")
        XCTAssertTrue(breakfast.waitForExistence(timeout: 20))
        breakfast.tap()
        app.buttons["Edit"].tap()
        let second = photo(app, 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.55)).tap()
        let makeCover = app.buttons["Make cover"]
        XCTAssertTrue(makeCover.waitForExistence(timeout: 5))
        makeCover.tap()
        XCTAssertTrue(photo(app, 1).waitForExistence(timeout: 5))
        // Count every tile: a duplicate would share its twin's identifier.
        let tiles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'meal-photo-'"))
        XCTAssertEqual(tiles.count, 2, "Making a photo the cover must not duplicate it")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'COVER'")).count, 1, "Only one photo is the cover")
        snapshot("51-new-cover")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["meal-pager"].label, "Avocado toast, photo 1 of 2", "The meal still has two photos")
    }
}
