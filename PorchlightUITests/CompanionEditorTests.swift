import XCTest

/// Editing a companion from Settings: the sheet must respond to touches, and its
/// "Add routine" button must open the routine editor on top of it.
@MainActor
final class CompanionEditorTests: XCTestCase {
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAddingARoutineFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleHousehold", "-startScreen", "settings"]
        app.launch()

        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 30))
        // Bring the companions section into view if it starts below the fold.
        let window = app.windows.firstMatch
        for _ in 0..<4 where !edit.isHittable {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        edit.tap()

        let addRoutine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add routine'")).firstMatch
        XCTAssertTrue(addRoutine.waitForExistence(timeout: 10), "The companion editor should open")
        snapshot("40-companion-editor")

        // The name field takes typing, so touches reach the sheet.
        let name = app.textFields["e.g. Biscuit"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("!\n")
        // Wait for the field to show it; a busy simulator updates the value late.
        let typed = expectation(for: NSPredicate(format: "value ENDSWITH '!'"), evaluatedWith: name)
        wait(for: [typed], timeout: 5)

        addRoutine.tap()
        XCTAssertTrue(app.staticTexts["New routine"].waitForExistence(timeout: 5), "Add routine should open the routine editor")
        snapshot("41-new-routine")

        let title = app.textFields["e.g. Brush teeth"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Brush teeth\n")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["New routine"].waitForNonExistence(timeout: 5), "Done should close the routine editor")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Brush teeth'")).firstMatch.waitForExistence(timeout: 5),
                      "The new routine should be listed in the companion editor")
        snapshot("42-routine-added")

        // The photo button opens the system picker from inside the sheet.
        app.buttons["Photo"].tap()
        // The wall has no navigation bars; the system picker does.
        let cancelPicker = app.navigationBars.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelPicker.waitForExistence(timeout: 10), "The photo picker should open")
        snapshot("43-photo-picker")
        cancelPicker.tap()
        XCTAssertTrue(cancelPicker.waitForNonExistence(timeout: 5), "Cancel should close the photo picker")

        // Settings has its own Save for the household name; this is the sheet's.
        let save = app.buttons.matching(NSPredicate(format: "label == 'Save' AND enabled == true")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(addRoutine.waitForNonExistence(timeout: 5), "Save should close the companion editor")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Brush teeth'")).firstMatch.waitForExistence(timeout: 5),
                      "Settings should list the saved routine")
        snapshot("44-saved")
    }
}
