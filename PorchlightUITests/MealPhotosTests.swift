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
        let app = XCUIApplication()
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
        snapshot("60-capture-three-shots")

        app.buttons["Remove photo 2"].tap()
        XCTAssertTrue(photo(app, 2).waitForNonExistence(timeout: 5), "Removing a shot leaves two")
        XCTAssertTrue(app.staticTexts["2 photos ready. Fill in anything else, then Save."].waitForExistence(timeout: 5))

        // Closing would lose the photos, so it asks first.
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Discard 2 photos?"].waitForExistence(timeout: 5), "Closing with unsaved photos should ask")
        snapshot("61-discard-prompt")
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(app.staticTexts["Discard 2 photos?"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(photo(app, 1).exists, "Keeping on editing keeps the photos")

        let dish = app.textFields["What was it? e.g. Dan dan noodles"]
        dish.tap()
        dish.typeText("Sunday roast\n")
        app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Company'")).firstMatch.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to'")).firstMatch.waitForExistence(timeout: 10))
        // The slot is guessed from the time the test runs; the dish and its photos are not.
        let polaroid = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", ": Sunday roast, 2 photos")).firstMatch
        XCTAssertTrue(polaroid.exists, "The saved polaroid should show the meal and its two photos")
        snapshot("62-saved-with-photos")
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
        snapshot("63-detail-paging")

        app.buttons["Edit"].tap()
        XCTAssertTrue(photo(app, 1).waitForExistence(timeout: 5), "Edit shows the photos")
        app.buttons["Remove photo 2"].tap()
        XCTAssertTrue(photo(app, 1).waitForNonExistence(timeout: 5))
        snapshot("64-edit-photos")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["meal-pager"].label.hasSuffix("of 2"), "Cancel keeps both photos")

        app.buttons["Edit"].tap()
        XCTAssertTrue(photo(app, 1).waitForExistence(timeout: 5))
        app.buttons["Remove photo 2"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Edit meal"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["meal-pager"].label, "Avocado toast", "Saving removes the photo")
    }
}
