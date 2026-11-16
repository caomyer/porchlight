import XCTest

/// Settings > Photo frame: Show picks our photos (shuffled, with a slow drift) or the porch view
/// (a still sky), and Manage handles a big library: select several photos and remove them at once.
@MainActor
final class PhotoFrameTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold"] + arguments
        app.launch()
        return app
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Opens Settings and scrolls until the photo frame's Show switch is comfortably on screen.
    private func openPhotoFrameSettings(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(["-startScreen", "settings"] + extra)
        XCTAssertTrue(app.textFields["Household name"].firstMatch.waitForExistence(timeout: 30))
        let show = element(app, "show-photos")
        let window = app.windows.firstMatch
        for _ in 0..<10 where !(show.exists && show.isHittable && show.frame.maxY < window.frame.maxY - 260) {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        Thread.sleep(forTimeInterval: 1) // let the scroll settle, or the tap only stops it
        XCTAssertTrue(show.isHittable, "The photo frame's Show switch is on screen")
        return app
    }

    private func expectAmbient(_ identifier: String, _ message: String) {
        let app = launch(["-startScreen", "photos", "-ambient.nightEnabled", "NO", "-samplePhotos", "3"])
        XCTAssertTrue(element(app, identifier).waitForExistence(timeout: 30), message)
    }

    func testChoosingThePorchView() {
        var app = openPhotoFrameSettings(["-samplePhotos", "3"])
        // Saved settings carry over between runs, so start from, and end on, Our photos.
        element(app, "show-photos").tap()
        XCTAssertTrue(element(app, "managePhotos").waitForExistence(timeout: 5), "Our photos lists the photos")
        XCTAssertEqual(element(app, "photoCount").label, "3 photos")

        element(app, "show-porchView").tap()
        XCTAssertTrue(element(app, "managePhotos").waitForNonExistence(timeout: 5), "The porch view needs no photo list")
        XCTAssertTrue(element(app, "show-porchView").isSelected)
        snapshot("100-photo-frame-porch-view")
        expectAmbient("porchView", "The idle wall shows the porch view, even with photos added")
        snapshot("101-porch-view")

        app = openPhotoFrameSettings(["-samplePhotos", "3"])
        element(app, "show-photos").tap()
        XCTAssertTrue(element(app, "managePhotos").waitForExistence(timeout: 5))
        snapshot("102-photo-frame-our-photos")
        expectAmbient("photoSlideshow", "Back on Our photos, the idle wall shows the photos")
    }

    func testRemovingSeveralPhotos() {
        let app = openPhotoFrameSettings(["-samplePhotos", "12"])
        element(app, "show-photos").tap()
        let manage = element(app, "managePhotos")
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "photoCount").label, "12 photos")
        manage.tap()

        let photos = app.buttons.matching(identifier: "framePhoto")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 5), "Manage shows every photo")
        XCTAssertTrue(app.staticTexts["12 photos · newest first"].exists)
        element(app, "selectPhotos").tap()
        for index in 0..<3 { photos.element(boundBy: index).tap() }
        let remove = element(app, "removePhotos")
        XCTAssertEqual(remove.label, "Remove 3")
        XCTAssertTrue(photos.element(boundBy: 0).isSelected)
        snapshot("103-manage-photos-selecting")

        remove.tap()
        XCTAssertTrue(app.staticTexts["9 photos · newest first"].waitForExistence(timeout: 5), "Three photos are gone")
        XCTAssertEqual(photos.count, 9)
        XCTAssertFalse(remove.exists, "Removing ends selecting")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertEqual(element(app, "photoCount").label, "9 photos")
    }
}
