import XCTest

/// Dishes on the wall (docs/design/dishes.md; journeys W2 and W3 of
/// docs/proposals/dishes-and-recipes.html): the Dishes view beside Week and Month, a dish's
/// sheet, a restaurant's sheet, and everyone giving their own face after dinner. The wall
/// keeps its one light look, so there is no night version. Runs on the iPad.
@MainActor
final class WallDishesTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPhone = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .phone }
        try XCTSkipIf(isPhone, "The wall's tests run on an iPad")
    }

    override func tearDown() {
        MainActor.assumeIsolated { XCUIDevice.shared.appearance = .light }
        super.tearDown()
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "food"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["What we ate"].waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDishesAPlaceAndADish() {
        let app = launch()
        app.buttons["Dishes"].tap()
        let pho = app.buttons["wall-dish-Pho tai"]
        XCTAssertTrue(pho.waitForExistence(timeout: 10))
        snapshot("wall-dishes-01-view")

        let place = app.buttons["wall-place-Pho Saigon House"]
        XCTAssertTrue(place.exists, "Ordering in? lists our places")
        place.tap()
        XCTAssertTrue(app.staticTexts["wall-place-title"].waitForExistence(timeout: 5))
        snapshot("wall-dishes-02-place")

        app.buttons["wall-place-dish-Pho tai"].tap()
        XCTAssertTrue(app.staticTexts["wall-dish-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["wall-dish-title"].label, "Pho tai")
        XCTAssertTrue(app.staticTexts["How we like it"].exists || app.staticTexts["HOW WE LIKE IT"].exists)
        snapshot("wall-dishes-03-dish")
        app.buttons["wall-dish-favorite"].tap()
    }

    func testEveryoneSaysHowItWas() {
        let app = launch()
        let plate = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Pho tai")).firstMatch
        XCTAssertTrue(plate.waitForExistence(timeout: 10))
        plate.tap()
        let rate = app.buttons["wall-rate-each"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        snapshot("wall-dishes-04-meal")
        rate.tap()
        XCTAssertTrue(app.staticTexts["wall-rate-title"].waitForExistence(timeout: 5))
        let faces = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wall-faces-")).element(boundBy: 0)
        XCTAssertTrue(faces.exists)
        faces.buttons["meh"].tap()
        XCTAssertTrue(faces.buttons["meh"].isSelected)
        snapshot("wall-dishes-05-rate")
        app.buttons["wall-rate-done"].tap()
        XCTAssertTrue(app.buttons["wall-rate-each"].waitForExistence(timeout: 5))
    }
}
