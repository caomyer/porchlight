import XCTest

/// Walks every wall screen with sample data and attaches a screenshot of each,
/// so the real iPad's rendering can be reviewed from the test results.
/// Sample launches use their own storage sandbox and never touch real data.
@MainActor
final class WallTourTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ arguments: [String], settle: TimeInterval = 6) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold"] + arguments
        app.launch()
        // Sample seeding and the first layout take a moment on an older iPad.
        _ = app.otherElements.firstMatch.waitForExistence(timeout: 30)
        Thread.sleep(forTimeInterval: settle)
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

    func testScreens() {
        let screens: [(String, [String])] = [
            ("01-today", ["-startScreen", "today"]),
            ("02-calendar-week", ["-startScreen", "calendar"]),
            ("03-calendar-month", ["-startScreen", "calendar", "-calendarMode", "month"]),
            ("04-companion", ["-startScreen", "companion-1"]),
            ("05-log-walk", ["-startScreen", "today", "-debugCompanionSheet", "log"]),
            ("06-food-week", ["-startScreen", "food"]),
            ("07-food-month", ["-startScreen", "food", "-debugFoodView", "month"]),
            ("08-pitch-in", ["-startScreen", "chores"]),
            ("08b-glow", ["-startScreen", "glow"]),
            ("09-lists", ["-startScreen", "lists"]),
            ("10-ambient", ["-startScreen", "photos", "-ambient.nightEnabled", "NO"]),
            ("11-settings", ["-startScreen", "settings"]),
            ("11b-onboarding-role", ["-onboardingStep", "role"]),
            ("12-onboarding-calendars", ["-onboardingStep", "calendars"]),
            ("13-onboarding-companions", ["-onboardingStep", "companions"]),
            ("14-onboarding-journals", ["-onboardingStep", "journals"]),
            ("15-onboarding-display", ["-onboardingStep", "display"]),
            ("16-onboarding-icloud", ["-onboardingStep", "iCloud"]),
        ]
        for (name, arguments) in screens {
            let app = launch(arguments)
            snapshot(name)
            app.terminate()
        }
    }

    /// The wall's recipes for review (docs/design/dishes.md, "Recipes"), with a recipe as long
    /// as they come (`-sampleFood long`): the bank, the empty bank, the kitchen view at its top
    /// and scrolled, the editor with a card photo, planning from the bank, the dinner editor's
    /// "What we cook" with the long name, and the week's dinners marked 📖.
    func testRecipeScreens() {
        let food = ["-startScreen", "food", "-sampleFood", "long"]
        let screens: [(String, [String])] = [
            ("r01-recipes", food + ["-debugFoodView", "recipes"]),
            ("r02-recipes-empty", ["-startScreen", "food", "-sampleFood", "norecipes", "-debugFoodView", "recipes"]),
            ("r05-editor-card", food + ["-debugFoodView", "recipe-edit"]),
            ("r06-plan", food + ["-debugFoodView", "recipe-plan"]),
        ]
        for (name, arguments) in screens {
            let app = launch(arguments)
            snapshot(name)
            app.terminate()
        }

        let kitchen = launch(food + ["-debugFoodView", "recipe-long"])
        snapshot("r03-kitchen")
        kitchen.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        snapshot("r04-kitchen-scrolled")
        kitchen.terminate()

        let lists = launch(["-startScreen", "lists", "-sampleFood", "long"])
        snapshot("r08-dinners")
        let day = lists.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sunday: ")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10), "Sunday's dinner")
        day.tap()
        let field = lists.textFields["dinner-title"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The dinner editor")
        // The cursor at the end, then the planned words deleted and the new ones typed.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let typed = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count + 2) + "grandma")
        Thread.sleep(forTimeInterval: 1)
        snapshot("r07-what-we-cook")
        lists.terminate()
    }

    /// Draws on today's page with a finger (as Apple Pencil would) and checks the
    /// ink shows in the zoomed editor and, after Done, in the handwritten month.
    func testHandwritingOnDayPage() throws {
        let app = launch(["-startScreen", "food", "-debugFoodView", "write", "-food.allowFingerDrawing", "YES"])
        let canvas = app.descendants(matching: .any)["dayPageCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "The day page canvas should be on screen")
        snapshot("20-write-before")

        // A small zigzag across the empty lower lines of the page.
        let points: [CGVector] = [
            CGVector(dx: 0.15, dy: 0.72), CGVector(dx: 0.30, dy: 0.62), CGVector(dx: 0.45, dy: 0.74),
            CGVector(dx: 0.60, dy: 0.62), CGVector(dx: 0.75, dy: 0.74), CGVector(dx: 0.85, dy: 0.64),
        ]
        for (start, end) in zip(points, points.dropFirst()) {
            canvas.coordinate(withNormalizedOffset: start)
                .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: end))
        }
        Thread.sleep(forTimeInterval: 1)
        snapshot("21-write-after-drawing")

        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
            Thread.sleep(forTimeInterval: 3)
            snapshot("22-month-after-done")
        } else {
            XCTFail("Done button not found")
        }
    }

    /// Opens a logged meal, swaps its dish for another, marks it delivery and saves; the
    /// detail shows the edit. Since dishes the name is the meal's dish lines: Edit takes the
    /// old dish off and names the new one in the dish field.
    func testEditingAMeal() {
        let app = launch(["-startScreen", "food", "-debugFoodView", "detail"])
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "The meal detail should offer Edit")
        edit.tap()

        let field = app.textFields["dish"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Edit names the meal's dishes")
        // Before the keyboard opens: the sheet stays put for it, and iOS 27's taller keyboard
        // covers the row this button is in.
        app.buttons["🛵 Delivery"].tap()
        // Editing adds a kind; the meal was home-cooked, so that comes off.
        if app.buttons["source-home"].isSelected { app.buttons["source-home"].tap() }
        // Today's breakfast is one dish: take it off, then name the new one.
        let old = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'remove-dish-'")).firstMatch
        XCTAssertTrue(old.waitForExistence(timeout: 5), "The meal's dish is a line with a way off")
        old.tap()
        field.tap()
        field.typeText("Leftover curry")
        assertOnScreen(app.staticTexts["Edit meal"], in: app, "The sheet title should stay on screen with the keyboard up")
        assertOnScreen(field, in: app, "The dish field should stay on screen with the keyboard up")
        snapshot("23-meal-edit")

        field.typeText("\n")  // Done adds the dish and puts the keyboard away, revealing Save
        XCTAssertTrue(app.descendants(matching: .any)["dish-line-Leftover curry"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Leftover curry"].waitForExistence(timeout: 5), "The detail should show the new name")
        XCTAssertTrue(app.staticTexts["Delivery"].exists, "The detail should show the new maker")
        XCTAssertFalse(app.textFields["dish"].exists, "Saving should leave edit mode")
        snapshot("24-meal-edited")
    }

    /// Typing into a sheet keeps the field being typed into, and the sheet's title, on screen.
    func testSheetsWithTheKeyboardUp() {
        var app = launch(["-startScreen", "food", "-debugFoodView", "capture"])
        let dish = app.textFields["What was it? e.g. Dan dan noodles"]
        XCTAssertTrue(dish.waitForExistence(timeout: 20))
        type("Dan dan noodles", into: dish)
        assertOnScreen(dish, in: app, "The dish field should stay on screen")
        snapshot("25-capture-keyboard")
        app.terminate()

        app = launch(["-startScreen", "today", "-debugCompanionSheet", "log"])
        let note = app.textFields.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 20))
        type("Met a corgi", into: note)
        assertOnScreen(note, in: app, "The walk note should stay above the keyboard")
        snapshot("26-walk-note-keyboard")
    }

    /// Taps a field and types once it holds the keyboard focus: a busy simulator reports
    /// the focus a moment after the tap, and typing before then fails ("Neither element nor
    /// any descendant has keyboard focus").
    private func type(_ text: String, into field: XCUIElement) {
        field.tap()
        let deadline = Date.now.addingTimeInterval(10)
        while (field.value(forKey: "hasKeyboardFocus") as? Bool) != true, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(field.value(forKey: "hasKeyboardFocus") as? Bool, true, "The field should take the keyboard focus")
        field.typeText(text)
    }

    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication, _ message: String) {
        let screen = app.windows.firstMatch.frame
        // The keyboard's frame leaves out its suggestion bar, which iOS 27 names.
        let bar = app.otherElements["SystemInputAssistantView"].firstMatch
        var keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : screen.maxY
        if bar.exists { keyboardTop = min(keyboardTop, bar.frame.minY) }
        let frame = element.frame
        XCTAssertTrue(frame.minY >= screen.minY && frame.maxY <= keyboardTop, "\(message): \(frame) vs keyboard at \(keyboardTop)")
        // A field must also take touches there, which an older keyboard's bar could block. Text
        // isn't hit-tested on its own on iOS 27 (a sheet's title reports as not hittable with
        // nothing over it), so for text the frame above is the check.
        let covered = element.elementType != .staticText && !element.isHittable
        XCTAssertFalse(covered, "\(message): it is covered")
        if covered {
            // What covers it, for the results.
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "\(message): the screen"
            add(tree)
        }
    }
}
