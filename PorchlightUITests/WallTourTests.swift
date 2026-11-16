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

    /// Opens a logged meal, renames it, marks it delivery and saves; the detail shows the edit.
    func testEditingAMeal() {
        let app = launch(["-startScreen", "food", "-debugFoodView", "detail"])
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "The meal detail should offer Edit")
        edit.tap()

        let title = app.textFields["What was it?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let current = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        title.typeText("Leftover curry")
        app.buttons["🛵 Delivery"].tap()
        assertOnScreen(app.staticTexts["Edit meal"], in: app, "The sheet title should stay on screen with the keyboard up")
        assertOnScreen(title, in: app, "The name field should stay on screen with the keyboard up")
        snapshot("23-meal-edit")

        title.typeText("\n")  // "done" puts the keyboard away, revealing Save
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Leftover curry"].waitForExistence(timeout: 5), "The detail should show the new name")
        XCTAssertTrue(app.staticTexts["Delivery"].exists, "The detail should show the new maker")
        XCTAssertFalse(app.textFields["What was it?"].exists, "Saving should leave edit mode")
        snapshot("24-meal-edited")
    }

    /// Typing into a sheet keeps the field being typed into, and the sheet's title, on screen.
    func testSheetsWithTheKeyboardUp() {
        var app = launch(["-startScreen", "food", "-debugFoodView", "capture"])
        let dish = app.textFields["What was it? e.g. Dan dan noodles"]
        XCTAssertTrue(dish.waitForExistence(timeout: 20))
        dish.tap()
        dish.typeText("Dan dan noodles")
        assertOnScreen(dish, in: app, "The dish field should stay on screen")
        snapshot("25-capture-keyboard")
        app.terminate()

        app = launch(["-startScreen", "today", "-debugCompanionSheet", "log"])
        let note = app.textFields.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 20))
        note.tap()
        note.typeText("Met a corgi")
        assertOnScreen(note, in: app, "The walk note should stay above the keyboard")
        snapshot("26-walk-note-keyboard")
    }

    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication, _ message: String) {
        let screen = app.windows.firstMatch.frame
        let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : screen.maxY
        let frame = element.frame
        XCTAssertTrue(frame.minY >= screen.minY && frame.maxY <= keyboardTop, "\(message): \(frame) vs keyboard at \(keyboardTop)")
        // The keyboard's frame leaves out its suggestion bar; only a hittable field is really in view.
        XCTAssertTrue(element.isHittable, "\(message): it is covered")
    }
}
