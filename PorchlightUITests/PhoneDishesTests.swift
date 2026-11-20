import XCTest

/// Dishes on the phone (docs/design/dishes.md; journeys P3, P4, P5, P7 and P8 of
/// docs/proposals/dishes-and-recipes.html): the Food tab's Dishes view and search, a dish's
/// page, a restaurant's page, everyone's own faces on a meal, renaming into a merge,
/// removing with Undo, and the empty state. Shot in light, dark and at the largest text.
/// Runs only on an iPhone.
@MainActor
final class PhoneDishesTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    override func tearDown() {
        MainActor.assumeIsolated { XCUIDevice.shared.appearance = .light }
        super.tearDown()
    }

    private func launch(_ arguments: [String] = [], household: [String] = ["-sampleHousehold"]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = household + ["-me", "James", "-startScreen", "food"] + arguments
        app.launch()
        waitUntilResponsive(app)
        return app
    }

    private func openDishes(_ app: XCUIApplication) {
        let segment = app.buttons["segment-Dishes"]
        XCTAssertTrue(segment.waitForExistence(timeout: 30))
        segment.tap()
    }

    func testDishesAndAPlace() {
        let app = launch()
        openDishes(app)
        // The upgrade's card shows once per phone, so only on this simulator's first run.
        let ok = app.buttons["dishes-intro-ok"]
        if ok.waitForExistence(timeout: 5) {
            snapshot("dishes-01-intro")
            ok.tap()
            XCTAssertFalse(element(app, beginningWith: "Your diary already knew").exists)
        }
        snapshot("dishes-02-list")

        let pho = app.buttons["dish-Pho tai"]
        reveal(pho, in: app)
        XCTAssertTrue(pho.label.contains("Pho Saigon House") || pho.label.contains("times"), pho.label)
        pho.tap()
        XCTAssertTrue(app.staticTexts["dish-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["dish-title"].label, "Pho tai")
        XCTAssertTrue(app.staticTexts["How we like it"].exists)
        snapshot("dishes-03-dish")

        app.buttons["dish-favorite"].tap()
        XCTAssertTrue(app.buttons["★ Favourite"].waitForExistence(timeout: 5), "Starred")

        app.buttons["dish-place"].tap()
        XCTAssertTrue(app.staticTexts["place-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["place-dish-Pho tai"].exists)
        XCTAssertTrue(app.buttons["place-last-time"].exists, "Last time's order")
        snapshot("dishes-04-place")
    }

    func testSearch() {
        let app = launch()
        openDishes(app)
        let field = app.textFields["dish-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        type("pho", into: field, in: app)
        XCTAssertTrue(app.buttons["dish-Pho tai"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, beginningWith: "Pho Saigon House").exists, "Places are found too")
        snapshot("dishes-05-search")
    }

    func testEveryoneRatesAMeal() {
        let app = launch()
        let meal = element(app, beginningWith: "Pho tai, spring rolls")
        reveal(meal, in: app)
        meal.tap()
        let rate = app.buttons["rate-each"]
        reveal(rate, in: app)
        XCTAssertTrue(app.buttons["meal-dish-Pho tai"].exists, "What we had")
        snapshot("dishes-06-meal")
        rate.tap()
        let faces = app.otherElements["faces-James"]
        XCTAssertTrue(faces.waitForExistence(timeout: 5))
        faces.waitToSettle()
        faces.buttons["meh"].tap()
        XCTAssertTrue(faces.buttons["meh"].isSelected, "James's own face")
        snapshot("dishes-07-rate-each")
        app.buttons["rate-done"].tap()
        XCTAssertTrue(app.buttons["meal-dish-Pho tai"].label.contains("You 😐"), app.buttons["meal-dish-Pho tai"].label)
    }

    func testRenameIntoAMergeAndRemoveWithUndo() {
        let app = launch(["-debugFoodView", "dishes"])
        app.buttons["dishes-intro-ok"].tapIfPresent()
        let knots = app.buttons["dish-Garlic knots"]
        reveal(knots, in: app)
        knots.tap()
        app.buttons["dish-rename"].tap()
        let name = app.textFields["dish-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.waitToSettle()
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Garlic knots".count))
        type("margherita", into: name, in: app)
        app.buttons["save-dish-name"].tap()
        XCTAssertTrue(app.otherElements["merge-offer"].waitForExistence(timeout: 5) || element(app, beginningWith: "Margherita is already").exists)
        snapshot("dishes-08-merge-offer")
        app.buttons["merge"].tap()
        XCTAssertTrue(app.staticTexts["dish-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["dish-title"].label, "Margherita", "The page follows the merge")

        let remove = app.buttons["dish-remove"]
        reveal(remove, in: app)
        remove.tap()
        let confirm = app.buttons["Remove dish"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snapshot("dishes-09-remove")
        confirm.tap()
        tapToastAction(app)
        XCTAssertTrue(app.buttons["dish-Margherita"].waitForExistence(timeout: 5), "Undo puts it back")
    }

    func testEmpty() {
        let app = launch(["-sampleFood", "none"])
        openDishes(app)
        XCTAssertTrue(app.descendants(matching: .any)["dishes-empty"].waitForExistence(timeout: 5))
        snapshot("dishes-10-empty")
    }

    func testNightAndLargestText() {
        XCUIDevice.shared.appearance = .dark
        var app = launch(["-debugFoodView", "dishes"])
        snapshot("dishes-20-list-dark")
        app.terminate()
        app = launch(["-debugFoodView", "dish"])
        XCTAssertTrue(app.staticTexts["dish-title"].waitForExistence(timeout: 10))
        snapshot("dishes-21-dish-dark")
        app.terminate()
        app = launch(["-debugFoodView", "place"])
        XCTAssertTrue(app.staticTexts["place-title"].waitForExistence(timeout: 10))
        snapshot("dishes-22-place-dark")
        app.terminate()

        XCUIDevice.shared.appearance = .light
        let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app = launch(["-debugFoodView", "dish"] + largest)
        XCTAssertTrue(app.staticTexts["dish-title"].waitForExistence(timeout: 10))
        snapshot("dishes-30-dish-largest")
        app.swipeUp()
        snapshot("dishes-31-dish-largest-scrolled")
        app.terminate()
        app = launch(["-debugFoodView", "dishes"] + largest)
        snapshot("dishes-32-list-largest")
    }
}

extension XCUIElement {
    /// Taps when it is there; nothing otherwise.
    func tapIfPresent() {
        if waitForExistence(timeout: 2) { tap() }
    }
}
