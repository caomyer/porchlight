import XCTest

/// Dish lines in Snap and Edit on the phone (docs/design/dishes.md, "The editor"; frames
/// P1, P2 and P3 of docs/proposals/dishes-and-recipes.html): a restaurant meal with two
/// dishes from "Last time here", a home meal typed with a suggestion, a meal that is only a
/// photo, and an edit that adds and takes off a dish. Also the form in the night look and
/// at the largest text. Runs only on an iPhone.
@MainActor
final class PhoneDishEditorTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    override func tearDown() {
        MainActor.assumeIsolated { XCUIDevice.shared.appearance = .light }
        super.tearDown()
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-me", "James", "-startScreen", "food", "-debugCamera", "sample", "-cameraAccess", "allowed"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["What we ate"].waitForExistence(timeout: 60))
        waitUntilResponsive(app)
        return app
    }

    /// Snap a meal, take the sample shot, and wait for the details.
    private func snap(_ app: XCUIApplication) {
        app.buttons["snap-meal"].tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 10))
        app.buttons["shutter"].tap()
        XCTAssertTrue(app.textFields["dish"].waitForExistence(timeout: 10), "A shot goes straight to the details")
    }

    private func tapWhenSettled(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) should be there")
        reveal(element, in: app)
        element.waitToSettle()
        element.tap()
    }

    /// Picks a restaurant the household has eaten at from the field's suggestions.
    private func pickPlace(_ name: String, in app: XCUIApplication) {
        let field = app.textFields["Restaurant"]
        tapWhenSettled(field, in: app)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        tapWhenSettled(row, in: app)
    }

    /// Done on the keyboard: what is typed becomes a dish, and Save is uncovered.
    private func done(_ app: XCUIApplication) {
        let field = app.textFields["dish"]
        if app.keyboards.firstMatch.exists, field.exists { field.typeText("\n") }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
    }

    private func save(_ app: XCUIApplication) {
        done(app)
        let save = app.buttons["save-meal"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.otherElements["toast"].waitForExistence(timeout: 10), "Saved, with a toast")
        tapToastAction(app)
        let pager = app.otherElements["meal-pager"].exists ? app.otherElements["meal-pager"] : app.buttons["meal-pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10), "Open goes to the new meal")
    }

    func testRestaurantMealWithTwoDishesFromLastTime() {
        let app = launch()
        snap(app)
        tapWhenSettled(app.buttons["source-dineOut"], in: app)
        pickPlace("Pho Saigon House", in: app)
        snapshot("editor-01-where-first")

        tapWhenSettled(app.buttons["dish-chip-Pho tai"], in: app)
        tapWhenSettled(app.buttons["dish-chip-Spring rolls"], in: app)
        XCTAssertTrue(app.otherElements["dish-line-Pho tai"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["dish-line-Pho tai"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Spring rolls"].exists)
        XCTAssertFalse(app.buttons["dish-chip-Pho tai"].exists, "A chip goes once its dish is on the meal")
        XCTAssertFalse(app.staticTexts["Would eat again?"].exists, "Faces are on the dishes now")
        let faces = app.descendants(matching: .any)["dish-faces-Pho tai"]
        tapWhenSettled(faces.buttons["new favorite"], in: app)
        XCTAssertTrue(faces.buttons["new favorite"].isSelected)
        snapshot("editor-02-two-dishes")

        save(app)
        let pho = app.buttons["meal-dish-Pho tai"]
        reveal(pho, in: app)
        XCTAssertTrue(pho.exists && app.buttons["meal-dish-Spring rolls"].exists, "What we had lists both")
        XCTAssertTrue(pho.label.contains("🤩") || pho.label.contains("new favorite"), pho.label)
    }

    func testHomeMealTypedWithASuggestion() {
        let app = launch()
        snap(app)
        XCTAssertTrue(app.buttons["source-home"].isSelected, "A new meal starts home-cooked")
        let field = app.textFields["dish"]
        type("chi", into: field, in: app)
        let curry = app.buttons["dish-suggestion-Chicken curry"]
        XCTAssertTrue(curry.waitForExistence(timeout: 5), "What we cook is suggested as you type")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(app.textFields["dish"].isHittable, "The field stays over the keyboard with its suggestions above it")
        XCTAssertTrue(curry.isHittable, "The suggestion is in view")
        snapshot("editor-03-suggestions")
        curry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Chicken curry"].waitForExistence(timeout: 5))
        let next = app.textFields["dish"]
        tapWhenSettled(next, in: app)
        type("Rice", into: next, in: app)
        snapshot("editor-04-home-typed")
        save(app)
        let curryRow = app.buttons["meal-dish-Chicken curry"]
        reveal(curryRow, in: app)
        XCTAssertTrue(curryRow.exists)
        XCTAssertTrue(app.buttons["meal-dish-Rice"].exists, "What was typed and never added is the last dish")
    }

    func testAPhotoAloneIsAWholeMeal() {
        let app = launch()
        snap(app)
        let again = app.staticTexts["Would eat again?"]
        reveal(again, in: app)
        XCTAssertTrue(again.exists, "With no dish, the meal keeps its own face")
        snapshot("editor-05-photo-only")
        save(app)
        XCTAssertFalse(app.buttons["rate-each"].exists, "No dishes, no What we had")
    }

    func testEditAddsAndTakesOffADish() {
        let app = launch()
        let meal = element(app, beginningWith: "Pho tai, spring rolls")
        reveal(meal, in: app)
        meal.tap()
        tapWhenSettled(app.buttons["edit-meal"], in: app)
        let remove = app.buttons["remove-dish-Spring rolls"]
        tapWhenSettled(remove, in: app)
        XCTAssertFalse(app.descendants(matching: .any)["dish-line-Spring rolls"].exists)
        type("Iced coffee", into: app.textFields["dish"], in: app)
        snapshot("editor-06-edit")
        done(app)
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Iced coffee"].waitForExistence(timeout: 5), "Done adds what was typed")
        let save = app.buttons["save-edit"]
        reveal(save, in: app)
        save.tap()
        let coffee = app.buttons["meal-dish-Iced coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["meal-dish-Spring rolls"].exists)
        XCTAssertTrue(app.buttons["meal-dish-Pho tai"].exists, "The dish left on keeps its line")
    }

    func testTheFormAtNightAndAtTheLargestText() {
        XCUIDevice.shared.appearance = .dark
        var app = launch()
        snap(app)
        tapWhenSettled(app.buttons["source-dineOut"], in: app)
        pickPlace("Pho Saigon House", in: app)
        tapWhenSettled(app.buttons["dish-chip-Pho tai"], in: app)
        tapWhenSettled(app.buttons["dish-chip-Spring rolls"], in: app)
        snapshot("editor-20-dark")
        app.terminate()

        XCUIDevice.shared.appearance = .light
        app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        snap(app)
        type("Pho tai", into: app.textFields["dish"], in: app)
        app.textFields["dish"].typeText("\n")
        tapWhenSettled(app.textFields["dish"], in: app)
        type("Spring rolls", into: app.textFields["dish"], in: app)
        app.textFields["dish"].typeText("\n")
        tapWhenSettled(app.textFields["dish"], in: app)
        let line = app.descendants(matching: .any)["dish-line-Pho tai"]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "Return adds the dish")
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Spring rolls"].exists)
        // Typing, the field and what it suggests stay over the keyboard at this size too.
        let field = app.textFields["dish"]
        type("Ri", into: field, in: app)
        let keyboardTop = app.keyboards.firstMatch.frame.minY
        XCTAssertTrue(field.isHittable && field.frame.maxY <= keyboardTop, "The field is over the keyboard: \(field.frame) vs \(keyboardTop)")
        snapshot("editor-30-largest")
    }
}
