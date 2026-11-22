import XCTest

/// Recipes on the phone (docs/design/dishes.md, "Recipes"; journey P6 of
/// docs/proposals/dishes-and-recipes.html), one test per journey: adding a recipe to a dish
/// we cook, cooking from the bank, planning a dinner from the bank, and ingredients to the
/// grocery list. The pages' looks are PocketRecipesScreenTests'; the words and rules are
/// RecipeLogicTests', RecipeBankTests' and RecipeDatabaseTests'. Runs only on an iPhone.
@MainActor
final class PhoneRecipesTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    /// The pinned day (`UITestClock`) at 6:40 pm, so a meal cooked from a recipe is guessed to be dinner.
    private static var dinnerTime: String {
        UITestClock.at(18, 40)
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.dinnerTime, "-me", "James", "-startScreen", "food"] + arguments
        app.launch()
        waitUntilResponsive(app)
        return app
    }

    private func openRecipe(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["recipe-title"].waitForExistence(timeout: 30), "The recipe's page opens")
    }

    /// The bank is empty but knows what we cook; a new recipe named like a dish we cook joins
    /// it, and the bank then shows it with that dish's history.
    func testAddingARecipeToADishWeCook() {
        let app = launch(["-sampleFood", "norecipes", "-debugFoodView", "recipes"])
        XCTAssertTrue(app.descendants(matching: .any)["recipes-empty"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["add-recipe-Oatmeal"].exists, "You cook these often")
        snapshot("recipes-01-empty")
        app.buttons["new-recipe"].tap()
        let name = app.textFields["recipe-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        type("oatmeal", into: name, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["recipe-joins"].waitForExistence(timeout: 5), "It joins the dish we cook")
        // A text field that grows: iOS 17 shows it as a text view, later iOS as a text field.
        let ingredients = app.descendants(matching: .any).matching(identifier: "recipe-ingredients").firstMatch
        ingredients.tap()
        app.typeText("• 1 cup oats\n• 2 cups milk")
        snapshot("recipes-02-editor")
        app.buttons["save-recipe"].tap()
        let row = app.buttons["recipe-Oatmeal"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The bank has it")
        XCTAssertTrue(row.label.contains("cooked twice"), "with the dish's history: \(row.label)")
        row.tap()
        openRecipe(app)
        XCTAssertTrue(element(app, beginningWith: "1 cup oats").exists, "pasted bullets are gone")
    }

    /// "We made this" opens Snap with Home-cooked and the dish on it; saved, the recipe's page
    /// counts one more time.
    func testCookingFromTheBank() {
        let app = launch(["-debugFoodView", "recipe", "-debugCamera", "sample", "-cameraAccess", "allowed"])
        openRecipe(app)
        let before = app.staticTexts["recipe-cooked"].label
        app.buttons["we-made-this"].tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 5))
        app.buttons["shutter"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Chicken curry"].waitForExistence(timeout: 5), "The dish is on the meal already")
        snapshot("recipes-10-cooking")
        let save = app.buttons["save-meal"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.otherElements["toast"].waitForExistence(timeout: 8))
        let cooked = app.staticTexts["recipe-cooked"]
        XCTAssertTrue(cooked.waitForExistence(timeout: 5))
        XCTAssertNotEqual(cooked.label, before, "One more time: \(before) then \(cooked.label)")
    }

    /// "Plan it" picks a day; Lists › Dinners then has the dish that day.
    func testPlanningADinnerFromTheBank() {
        let app = launch(["-debugFoodView", "recipe"])
        openRecipe(app)
        app.buttons["plan-recipe"].tap()
        let tonight = app.buttons["plan-day-0"]
        XCTAssertTrue(tonight.waitForExistence(timeout: 5))
        snapshot("recipes-20-plan")
        tonight.tap()
        XCTAssertTrue(element(app, beginningWith: "Chicken curry planned for").waitForExistence(timeout: 8), "It says when")
        app.tabBars.buttons["Lists"].tap()
        let dinners = app.buttons["This week's dinners"]
        XCTAssertTrue(dinners.waitForExistence(timeout: 5))
        dinners.tap()
        let planned = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ": Chicken curry")).firstMatch
        XCTAssertTrue(planned.waitForExistence(timeout: 5), "Tonight's dinner is the curry")
        XCTAssertEqual(planned.value as? String, "Has a recipe")
        snapshot("recipes-21-dinners")
        // Another day, planned from what we cook.
        let sunday = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sunday: ")).firstMatch
        sunday.tap()
        let curry = app.buttons["dinner-dish-Chicken curry"]
        XCTAssertTrue(curry.waitForExistence(timeout: 5), "What we cook")
        snapshot("recipes-23-what-we-cook")
        reveal(curry, in: app)
        curry.tap()
        app.buttons["Save"].tap()
        let sundayCurry = app.buttons["Sunday: Chicken curry"]
        XCTAssertTrue(sundayCurry.waitForExistence(timeout: 5), "Sunday is the curry too")
        XCTAssertEqual(sundayCurry.value as? String, "Has a recipe")
        // "What does it need?" starts from the recipe's ingredients, without their amounts.
        app.buttons.matching(identifier: "Add what Chicken curry needs to groceries").firstMatch.tap()
        let needs = app.descendants(matching: .any).matching(identifier: "needs").firstMatch
        XCTAssertTrue(needs.waitForExistence(timeout: 5))
        let typed = needs.value as? String ?? ""
        XCTAssertTrue(typed.hasPrefix("Chicken thighs, Onion, Garlic, Ginger"), "From the recipe: \(typed)")
        snapshot("recipes-22-needs")
    }

    /// Picked ingredients go to the grocery list without their amounts; Undo takes them back.
    func testIngredientsToTheGroceryList() {
        let app = launch(["-debugFoodView", "recipe"])
        openRecipe(app)
        for index in [3, 5] {
            let ingredient = app.buttons["ingredient-\(index)"]
            reveal(ingredient, in: app)
            ingredient.tap()
        }
        let add = app.buttons["add-to-groceries"]
        reveal(add, in: app)
        XCTAssertTrue(add.label.contains("Add 2"), add.label)
        snapshot("recipes-30-picked")
        add.tap()
        XCTAssertTrue(element(app, beginningWith: "2 items added to groceries").waitForExistence(timeout: 8))
        XCTAssertTrue(element(app, beginningWith: "Ginger and coconut milk").exists || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Ginger and coconut milk")).firstMatch.exists,
                      "What to buy, not how much")
        app.tabBars.buttons["Lists"].tap()
        XCTAssertTrue(app.buttons["Ginger"].waitForExistence(timeout: 5), "On the grocery list")
        XCTAssertTrue(app.buttons["Coconut milk"].exists)
    }
}
