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

    /// The × badge hangs over its photo's corner, and a tap on the part over the photo still
    /// removes it. On iOS 27 the photo's old menu took every touch inside the photo, so that
    /// tap opened Make cover and Reframe instead.
    func testTheRemoveBadgeTakesTapsOverThePhoto() {
        let app = launch(["-startScreen", "food"])
        let breakfast = labelled(app, startingWith: "Breakfast: Avocado toast and 1 more, 2 photos")
        XCTAssertTrue(breakfast.waitForExistence(timeout: 20))
        breakfast.tap()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "The meal opens")
        edit.tap()
        XCTAssertTrue(photo(app, 1).waitForExistence(timeout: 5), "Edit shows the photos")

        // The badge is drawn round the middle of its frame, which sits on the photo's corner:
        // a little left of and below the middle is the badge, over the photo.
        let badge = app.buttons["Remove photo 2"]
        let inner = 5 / max(badge.frame.width, 1)
        badge.coordinate(withNormalizedOffset: CGVector(dx: 0.5 - inner, dy: 0.5 + inner)).tap()
        XCTAssertTrue(photo(app, 1).waitForNonExistence(timeout: 5), "A tap on the badge over the photo removes it")
        XCTAssertFalse(app.buttons["Make cover"].exists, "and does not open the photo's choices")
        snapshot("49b-badge-over-photo")
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
        // The cover's only choice is Reframe, so a tap opens it straight away.
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.55)).tap()
        let frameWindow = app.descendants(matching: .any)["reframe-window"]
        XCTAssertTrue(frameWindow.waitForExistence(timeout: 5), "Tapping the cover opens it to be reframed")
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

    /// Reframing a photo that isn't the cover: the dialog's Reframe opens the reframe screen
    /// as the dialog goes, and Done brings back the row with that photo framed.
    func testReframingAnotherPhoto() {
        let app = launch(["-startScreen", "food"])
        let breakfast = labelled(app, startingWith: "Breakfast: Avocado toast and 1 more, 2 photos")
        XCTAssertTrue(breakfast.waitForExistence(timeout: 20))
        breakfast.tap()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "The meal opens")
        edit.tap()
        let cover = framing(app, 0)
        let second = framing(app, 1)
        XCTAssertTrue(second.hasSuffix("-centered"), "The sample's second photo starts unframed: \(second)")

        photo(app, 1).coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.55)).tap()
        let reframe = app.buttons["Reframe"]
        XCTAssertTrue(reframe.waitForExistence(timeout: 5), "The second photo offers Reframe")
        reframe.tap()
        let frameWindow = app.descendants(matching: .any)["reframe-window"]
        XCTAssertTrue(frameWindow.waitForExistence(timeout: 5), "Reframe opens the second photo to frame")
        frameWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: frameWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        snapshot("50b-reframe-second")
        app.buttons["Done"].tap()
        XCTAssertTrue(frameWindow.waitForNonExistence(timeout: 5), "Done goes back to the row")
        XCTAssertEqual(framing(app, 1), second.replacingOccurrences(of: "-centered", with: "-framed"), "The second photo is framed")
        XCTAssertEqual(framing(app, 0), cover, "and the cover is as it was")
    }

    /// Which photo a tile shows and whether it is framed: "photo-<id>-centered" or "-framed".
    private func framing(_ app: XCUIApplication, _ index: Int) -> String {
        let tile = photo(app, index)
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Photo \(index + 1) is in the row")
        let image = tile.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo-'")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        return image.identifier
    }

    /// Making another photo the cover moves it to the front, once.
    func testMakingAnotherPhotoTheCover() {
        let app = launch(["-startScreen", "food"])
        let breakfast = labelled(app, startingWith: "Breakfast: Avocado toast and 1 more, 2 photos")
        XCTAssertTrue(breakfast.waitForExistence(timeout: 20))
        breakfast.tap()
        // The meal's sheet fades in; on a busy simulator Edit comes a moment after the tap.
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "The meal opens")
        edit.tap()
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
