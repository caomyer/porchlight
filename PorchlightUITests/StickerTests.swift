import XCTest

/// The photo sticker on the wall (docs/design/companion-characters.md): from the companion
/// page's hero, the sheet shows the photo and the sticker cut from it, and using it puts the
/// sticker where the photo was, until "Back to the photo". The cut-out is a drawn stand-in
/// (`-debugStickerSubject`), since subject lifting may not run in the simulator; the photo
/// is drawn in code (`-samplePhoto`). The phone's journey is in `PhoneWeekTests`.
@MainActor
final class StickerTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-samplePhoto", "YES", "-startScreen", "companion-1"] + arguments
        app.launch()
        _ = app.otherElements.firstMatch.waitForExistence(timeout: 30)
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMakingThePhotoStickerAndChoosingFaces() {
        let app = launch(["-debugStickerSubject", "middle"])
        let change = app.buttons["change-face"]
        XCTAssertTrue(change.waitForExistence(timeout: 40), "The hero links to the face")
        XCTAssertEqual(change.label, "Change Yo-Yo's character or photo")
        snapshot("face-10-wall-hero")
        change.tap()
        let photo = app.buttons["face-photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertTrue(photo.isSelected)
        app.buttons["make-sticker"].tap()
        let use = app.buttons["use-sticker"]
        XCTAssertTrue(use.waitForExistence(timeout: 15), "The sheet cuts Yo-Yo out")
        XCTAssertTrue(app.images["sticker-preview"].exists, "and shows the sticker beside the photo")
        XCTAssertTrue(app.staticTexts["Porchlight cut Yo-Yo out of the photo on this iPad. Nothing is sent anywhere."].exists)
        snapshot("face-11-wall-sticker")
        use.tap()
        let sticker = app.buttons["face-sticker"]
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        XCTAssertTrue(sticker.isSelected, "the sticker shows")
        snapshot("face-12-wall-sticker-chosen")
        app.buttons["face-done"].tap()
        XCTAssertTrue(sticker.waitForNonExistence(timeout: 5))
        snapshot("face-13-wall-hero-sticker")

        // The photo again: the sticker stays, to choose another time.
        change.tap()
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        XCTAssertTrue(photo.isSelected)
        XCTAssertTrue(app.buttons["face-sticker"].exists, "the sticker stays, to choose again")
    }

    func testNoSubjectSaysWhyAndKeepsThePhoto() {
        let app = launch(["-debugStickerSubject", "none"])
        let change = app.buttons["change-face"]
        XCTAssertTrue(change.waitForExistence(timeout: 40))
        change.tap()
        let make = app.buttons["make-sticker"]
        XCTAssertTrue(make.waitForExistence(timeout: 5))
        make.tap()
        let failed = app.staticTexts["sticker-failed"]
        XCTAssertTrue(failed.waitForExistence(timeout: 15))
        XCTAssertEqual(failed.label, "Porchlight couldn't find Yo-Yo in this photo. Try one where Yo-Yo stands out from the background.")
        XCTAssertTrue(app.buttons["sticker-photo"].exists, "with another photo to try")
        XCTAssertFalse(app.buttons["use-sticker"].exists)
        snapshot("face-14-wall-no-subject")
    }
}
