import XCTest

/// Recipes on the wall (docs/design/dishes.md, "Recipes"; journey W4 of
/// docs/proposals/dishes-and-recipes.html), one test per journey: adding a recipe to a dish
/// we cook, cooking from the bank, planning a dinner from the bank, and ingredients to the
/// grocery list. Runs on the iPad.
@MainActor
final class WallRecipesTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPhone = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .phone }
        try XCTSkipIf(isPhone, "The wall's tests run on an iPad")
    }

    /// Today at 6:40 pm, so a meal cooked from a recipe is guessed to be dinner whenever the
    /// suite runs (docs/design/testing.md, hard rule 1).
    private static var dinnerTime: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02dT18:40", parts.year!, parts.month!, parts.day!)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.dinnerTime, "-startScreen", "food"] + arguments
        app.launch()
        // The Food page's title, then each test waits for its own first element.
        XCTAssertTrue(app.staticTexts["What we ate"].waitForExistence(timeout: 60), "The Food page opens")
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

    func testAddingARecipeToADishWeCook() {
        let app = launch(["-sampleFood", "norecipes", "-debugFoodView", "recipes"])
        XCTAssertTrue(app.descendants(matching: .any)["wall-recipes-empty"].waitForExistence(timeout: 30))
        snapshot("w4-01-empty")
        tap(app.buttons["wall-add-recipe-Oatmeal"])
        // A text field that grows: iOS 17 shows it as a text view, later iOS as a text field.
        let ingredients = app.descendants(matching: .any).matching(identifier: "recipe-ingredients").firstMatch
        tap(ingredients)
        app.typeText("1 cup oats\n2 cups milk")
        tap(app.buttons["save-recipe"])
        let card = app.buttons["wall-recipe-Oatmeal"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "The bank has it")
        XCTAssertTrue(card.label.contains("cooked twice"), "with the dish's history: \(card.label)")
        snapshot("w4-02-bank")
    }

    func testCookingFromTheBank() {
        let app = launch(["-debugFoodView", "recipe"])
        XCTAssertTrue(app.staticTexts["wall-recipe-title"].waitForExistence(timeout: 30), "The kitchen view opens")
        snapshot("w4-10-kitchen")
        tap(app.buttons["wall-we-made-this"])
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Chicken curry"].waitForExistence(timeout: 10), "The dish is on the meal already")
        snapshot("w4-11-cooking")
        tap(app.buttons["Save"])
        XCTAssertFalse(app.textFields["dish"].waitForExistence(timeout: 3), "Saved")
    }

    func testPlanningADinnerFromTheBank() {
        let app = launch(["-debugFoodView", "recipe"])
        XCTAssertTrue(app.staticTexts["wall-recipe-title"].waitForExistence(timeout: 30))
        tap(app.buttons["wall-plan-recipe"])
        tap(app.buttons["wall-plan-day-0"])
        XCTAssertTrue(app.staticTexts["Chicken curry is planned for tonight"].waitForExistence(timeout: 5))
        snapshot("w4-20-planned")
    }

    func testIngredientsToTheGroceryList() {
        let app = launch(["-debugFoodView", "recipe"])
        XCTAssertTrue(app.staticTexts["wall-recipe-title"].waitForExistence(timeout: 30))
        tap(app.buttons["wall-ingredient-3"])
        tap(app.buttons["wall-ingredient-5"])
        tap(app.buttons["wall-add-to-groceries"])
        XCTAssertTrue(app.staticTexts["🛒 2 items added to groceries"].waitForExistence(timeout: 5))
        snapshot("w4-30-groceries")
        tap(app.buttons["wall-undo-groceries"])
        XCTAssertTrue(app.staticTexts["wall-groceries-hint"].waitForExistence(timeout: 5), "Undo takes them back")
    }
}
