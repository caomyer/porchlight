import XCTest

/// Walks every wall screen with sample data and attaches a screenshot of each,
/// so the real iPad's rendering can be reviewed from the test results.
/// Sample launches use their own storage sandbox and never touch real data.
final class WallTourTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ arguments: [String], settle: TimeInterval = 6) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold"] + arguments
        app.launch()
        // Sample seeding and the first layout take a moment on an older iPad.
        _ = app.otherElements.firstMatch.waitForExistence(timeout: 30)
        Thread.sleep(forTimeInterval: settle)
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
            ("08-chores", ["-startScreen", "chores"]),
            ("09-lists", ["-startScreen", "lists"]),
            ("10-ambient", ["-startScreen", "photos", "-ambient.nightEnabled", "NO"]),
            ("11-settings", ["-startScreen", "settings"]),
            ("12-onboarding-calendars", ["-onboardingStep", "calendars"]),
            ("13-onboarding-companions", ["-onboardingStep", "companions"]),
            ("14-onboarding-journals", ["-onboardingStep", "journals"]),
            ("15-onboarding-display", ["-onboardingStep", "display"]),
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
}
