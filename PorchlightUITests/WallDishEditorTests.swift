import XCTest

/// Dish lines in the wall's capture sheet and its Edit (docs/design/dishes.md, "The
/// editor"; frame W1 of docs/proposals/dishes-and-recipes.html): a restaurant meal with
/// two dishes from "Last time here", a home meal typed with a suggestion, a meal that is
/// only its photos, and an edit that adds and takes off a dish. Runs on the iPad.
@MainActor
final class WallDishEditorTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPhone = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .phone }
        try XCTSkipIf(isPhone, "The wall's tests run on an iPad")
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "food"] + arguments
        app.launch()
        _ = app.otherElements.firstMatch.waitForExistence(timeout: 30)
        Thread.sleep(forTimeInterval: 3)
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) should be there")
        element.waitToSettle()
        element.tap()
    }

    private var capture: [String] { ["-debugFoodView", "capture"] }

    func testRestaurantMealWithTwoDishesFromLastTime() {
        let app = launch(capture)
        tap(app.buttons["source-dineOut"])
        tap(app.textFields["Restaurant"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pho Saigon House")).firstMatch)
        tap(app.buttons["dish-chip-Pho tai"])
        tap(app.buttons["dish-chip-Spring rolls"])
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Spring rolls"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Would eat again?"].exists && app.staticTexts["WOULD EAT AGAIN?"].exists, "Faces are on the dishes")
        tap(app.descendants(matching: .any)["dish-faces-Pho tai"].buttons["new favorite"])
        // The count and last time's face are texts of their own, so neither is cut to fit the
        // other (XCTest can't see an ellipsis; the screenshot shows them whole).
        for name in ["Pho tai", "Spring rolls"] {
            let line = app.descendants(matching: .any)["dish-line-\(name)"]
            let count = line.staticTexts["dish-count-\(name)"], last = line.staticTexts["dish-last-\(name)"]
            XCTAssertTrue(count.exists && count.label.hasSuffix("time here"), "\(name): \(count.label)")
            XCTAssertTrue(last.exists && last.label.hasPrefix("last time "), "\(name): \(last.label)")
        }
        // A long name wraps instead of being cut.
        let long = "Slow-braised beef brisket with star anise"
        let field = app.textFields["dish"]
        tap(field)
        field.typeText(long + "\n")
        let longLine = app.descendants(matching: .any)["dish-line-\(long)"]
        XCTAssertTrue(longLine.waitForExistence(timeout: 5))
        XCTAssertTrue(longLine.staticTexts[long].exists)
        snapshot("wall-editor-01-two-dishes")
        tap(app.buttons["Save"])
        XCTAssertFalse(app.buttons["dish-chip-Pho tai"].waitForExistence(timeout: 3), "The sheet saved and closed")
    }

    func testHomeMealTypedWithASuggestion() {
        let app = launch(capture)
        let field = app.textFields["dish"]
        tap(field)
        field.typeText("chi")
        tap(app.buttons["dish-suggestion-Chicken curry"])
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Chicken curry"].waitForExistence(timeout: 5))
        app.textFields["dish"].tap()
        app.textFields["dish"].typeText("Rice")
        snapshot("wall-editor-02-home")
        // Done adds the dish and puts the keyboard away, uncovering Save.
        app.textFields["dish"].typeText("\n")
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Rice"].waitForExistence(timeout: 5))
        tap(app.buttons["Save"])
        XCTAssertFalse(app.textFields["dish"].waitForExistence(timeout: 3), "Saved")
    }

    func testAPhotoAloneIsAWholeMeal() {
        let app = launch(capture)
        XCTAssertTrue(app.textFields["dish"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Would eat again?"].exists || app.staticTexts["WOULD EAT AGAIN?"].exists, "With no dish, the meal keeps its own face")
        snapshot("wall-editor-03-nothing-named")
        tap(app.buttons["Save"])
        XCTAssertFalse(app.textFields["dish"].waitForExistence(timeout: 3), "Saved with no dish")
    }

    func testEditAddsAndTakesOffADish() {
        let app = launch(["-debugFoodView", "detail-pho"])
        tap(app.buttons["Edit"])
        tap(app.buttons["remove-dish-Spring rolls"])
        let field = app.textFields["dish"]
        tap(field)
        field.typeText("Iced coffee")
        snapshot("wall-editor-04-edit")
        field.typeText("\n")
        tap(app.buttons["Save"])
        XCTAssertTrue(app.descendants(matching: .any)["wall-meal-dish-Iced coffee"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["wall-meal-dish-Spring rolls"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["wall-meal-dish-Pho tai"].exists)
    }
}
