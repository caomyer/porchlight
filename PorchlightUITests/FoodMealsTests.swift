import XCTest

/// Several dishes in one meal, and eating out with a restaurant picked by search.
/// Sample launches use their own storage sandbox and never touch real data.
@MainActor
final class FoodMealsTests: XCTestCase {
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
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // For local review: `TEST_RUNNER_SHOT_DIR=/some/folder xcodebuild test ...`
        if let folder = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
    }

    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication, _ message: String) {
        let screen = app.windows.firstMatch.frame
        let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : screen.maxY
        let frame = element.frame
        XCTAssertTrue(frame.minY >= screen.minY && frame.maxY <= keyboardTop, "\(message): \(frame) vs keyboard at \(keyboardTop)")
    }

    private func button(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// A dinner with two dishes opens on the first, switches to the second, and offers another.
    func testSeveralDishesInOneMeal() {
        let app = launch(["-startScreen", "food"])
        let stack = app.descendants(matching: .any)["Dinner: Sushi night and 1 more"]
        XCTAssertTrue(stack.waitForExistence(timeout: 20), "Saturday's dinner should show as a stack of two")
        stack.tap()

        XCTAssertTrue(app.staticTexts["Sushi night"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sakura Sushi Bar"].exists, "The detail should name the restaurant")
        let mochi = app.buttons["Mochi"]
        XCTAssertTrue(mochi.exists, "The other dish of the meal should be one tap away")
        snapshot("30-meal-two-dishes")

        mochi.tap()
        XCTAssertTrue(app.staticTexts["Mochi"].waitForExistence(timeout: 5), "Picking the other dish should show it")
        snapshot("31-meal-second-dish")

        app.buttons["Add another dinner dish"].tap()
        XCTAssertTrue(app.textFields["What was it? e.g. Dan dan noodles"].waitForExistence(timeout: 5), "Adding another should open the capture form")
        XCTAssertTrue(app.staticTexts["Dinner"].exists, "The capture form should be for the same meal")
        snapshot("32-another-dinner-dish")
    }

    /// Logs a meal out: picks a restaurant from earlier spots by typing, saves, and sees it named.
    func testDineOutWithARestaurant() {
        let app = launch(["-startScreen", "food", "-debugFoodView", "capture"])
        let dish = app.textFields["What was it? e.g. Dan dan noodles"]
        XCTAssertTrue(dish.waitForExistence(timeout: 20))
        dish.tap()
        dish.typeText("Salmon nigiri\n")

        app.buttons["🍽️ Dine out"].tap()
        let restaurant = app.textFields["Restaurant"]
        XCTAssertTrue(restaurant.waitForExistence(timeout: 5), "Dining out should ask where")
        restaurant.tap()
        restaurant.typeText("Saku")
        let spot = button(app, startingWith: "Sakura Sushi Bar")
        XCTAssertTrue(spot.waitForExistence(timeout: 10), "A place eaten at before should be suggested while typing")
        Thread.sleep(forTimeInterval: 1)
        assertOnScreen(restaurant, in: app, "The restaurant field should stay above the keyboard")
        assertOnScreen(spot, in: app, "Suggestions should stay above the keyboard")
        snapshot("33-restaurant-suggestions")

        spot.tap()
        XCTAssertTrue(app.buttons["Restaurant: Sakura Sushi Bar"].waitForExistence(timeout: 5), "The picked restaurant should show as a card")
        snapshot("34-restaurant-picked")
        // The photo button sits 24pt above the viewfinder's bottom, which lines up with the form's.
        let photo = app.buttons["Choose a photo"]
        if photo.exists {
            XCTAssertLessThanOrEqual(app.buttons["Save"].frame.maxY, photo.frame.maxY + 26, "Save should stay inside the sheet")
        }

        app.buttons["Save"].tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "out at Sakura Sushi Bar")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "The saved note should say where it was eaten")
        snapshot("35-dine-out-saved")
    }

    /// Live Maps suggestions appear while typing a new restaurant (needs the network).
    func testLiveRestaurantSearch() throws {
        let app = launch(["-startScreen", "food", "-debugFoodView", "capture"])
        let dish = app.textFields["What was it? e.g. Dan dan noodles"]
        XCTAssertTrue(dish.waitForExistence(timeout: 20))
        app.buttons["🛵 Delivery"].tap()
        let restaurant = app.textFields["Restaurant"]
        XCTAssertTrue(restaurant.waitForExistence(timeout: 5))
        restaurant.tap()
        restaurant.typeText("Pizza")
        let suggestions = app.descendants(matching: .any)["Restaurant suggestions"]
        XCTAssertTrue(suggestions.waitForExistence(timeout: 10))
        let offline = app.staticTexts["Can't reach Maps. The name you type is saved as is."]
        Thread.sleep(forTimeInterval: 4)
        snapshot("36-live-suggestions")
        if offline.exists { throw XCTSkip("Maps is not reachable from this simulator") }
        XCTAssertGreaterThan(suggestions.buttons.count, 0, "Maps should suggest places for \"Pizza\"")
    }

    /// Editing a meal into a dinner out: the restaurant field stays above the keyboard and the
    /// detail names the place after saving.
    func testEditingAMealIntoDiningOut() {
        let app = launch(["-startScreen", "food", "-debugFoodView", "detail"])
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        edit.tap()
        app.buttons["🍽️ Dine out"].tap()
        let restaurant = app.textFields["Restaurant"]
        XCTAssertTrue(restaurant.waitForExistence(timeout: 5))
        restaurant.tap()
        restaurant.typeText("Corner Bistro")
        Thread.sleep(forTimeInterval: 2)
        assertOnScreen(restaurant, in: app, "The restaurant field should move above the keyboard")
        snapshot("37-edit-dine-out")
        restaurant.typeText("\n")
        XCTAssertTrue(app.buttons["Restaurant: Corner Bistro"].waitForExistence(timeout: 5), "A typed name should be kept as the restaurant")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Dine out"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Corner Bistro"].exists, "The detail should name the restaurant")
        snapshot("38-edit-dine-out-saved")
    }

    /// Today's plates show a two-dish breakfast as a stack; its sheet offers another dish.
    func testSeveralDishesOnTodaysPlates() {
        let app = launch(["-startScreen", "today"])
        let plate = button(app, startingWith: "Breakfast: Oat latte and 1 more")
        XCTAssertTrue(plate.waitForExistence(timeout: 20), "Today's breakfast should show as a stack of two")
        snapshot("39-today-plates")
        plate.tap()
        XCTAssertTrue(app.buttons["Avocado toast"].waitForExistence(timeout: 5), "The other breakfast dish should be one tap away")
        app.buttons["Add another breakfast dish"].tap()
        XCTAssertTrue(app.textFields["What was it? e.g. Dan dan noodles"].waitForExistence(timeout: 5), "Adding another should open the capture form")
        XCTAssertTrue(app.staticTexts["Breakfast"].exists, "The capture form should be for breakfast")
    }

    /// Swiping a two-dish cell in the week brings the other dish to the top; tapping opens it.
    func testSwipingBetweenDishesInTheWeek() {
        let app = launch(["-startScreen", "food"])
        let stack = app.descendants(matching: .any)["Dinner: Sushi night and 1 more"]
        XCTAssertTrue(stack.waitForExistence(timeout: 20))
        stack.swipeLeft()
        let next = app.descendants(matching: .any)["Dinner: Mochi and 1 more"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Swiping should bring the other dish to the top")
        snapshot("40-week-swiped")
        next.swipeRight()
        XCTAssertTrue(stack.waitForExistence(timeout: 5), "Swiping back should return to the first dish")
        stack.swipeLeft()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5), "Tapping should open the dish on top")
        XCTAssertTrue(app.staticTexts["Mochi"].exists)
    }

    /// The month's day sheet lists the day's meals; one tap opens the same meal sheet as the week.
    func testOpeningAMealFromTheMonth() {
        let app = launch(["-startScreen", "food", "-debugFoodView", "write"])
        let meal = app.buttons["Breakfast: Avocado toast"]
        XCTAssertTrue(meal.waitForExistence(timeout: 20), "The day sheet should list the day's meals")
        snapshot("41-month-day-meals")
        meal.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5), "A meal from the month should open its sheet")
        XCTAssertTrue(app.staticTexts["Avocado toast"].exists)
        XCTAssertFalse(app.staticTexts["Writing on today's page"].exists, "The day sheet should give way to the meal")
        snapshot("42-month-meal-opened")
    }

    /// Notes go on the day's one shared page, opened from the capture form.
    func testWritingDayNotesFromTheCaptureForm() {
        let app = launch(["-startScreen", "food", "-debugFoodView", "capture"])
        let write = app.buttons["Write on today's page"]
        XCTAssertTrue(write.waitForExistence(timeout: 20), "The capture form should offer the day's page")
        snapshot("43-capture-day-notes")
        write.tap()
        XCTAssertTrue(app.staticTexts["Writing on today's page"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Log a meal on this day"].exists, "Writing from a meal keeps the meal list out of the way")
        snapshot("44-capture-writing-notes")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.textFields["What was it? e.g. Dan dan noodles"].waitForExistence(timeout: 5), "Done should return to the meal form")
    }
}
