import XCTest

/// A character's face on the phone, touched on its own pixels (`-sampleCharacter`): a face
/// inside a card, a row or a choice never takes the touch from it, and a face that is the tap
/// target plays (docs/design/companion-characters.md, "A mood's animation"). In build
/// 20261124.220829 the grid card went dead: a tap gesture on the face inside its Button.
/// And "Done" tapped before the animations came keeps them all.
///
/// Touches are real ones at screen points (`coordinate(...).tap()`), not accessibility
/// activations, which would go round the gestures. Motion is measured from the screen: the
/// face's square, photographed a few times a second, must show more than one picture.
@MainActor
final class PhoneCharacterTapTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    private func launch(at hour: Int, _ minute: Int, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", UITestClock.at(hour, minute), "-me", "James", "-samplePhoto", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        waitUntilResponsive(app)
        return app
    }

    private func touch(_ app: XCUIApplication, at point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    private func opened(_ app: XCUIApplication) -> Bool {
        element(app, beginningWith: "Yo-Yo's week").waitForExistence(timeout: 5)
    }

    /// How many different pictures `rect` of the screen shows over `seconds`.
    private func pictures(in rect: CGRect, for seconds: TimeInterval) -> Int {
        let start = Date.now
        var seen = Set<Data>()
        while Date.now.timeIntervalSince(start) < seconds {
            let shot = XCUIScreen.main.screenshot().image
            guard let cg = shot.cgImage else { continue }
            let scale = CGFloat(cg.width) / shot.size.width
            let area = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
            if let crop = cg.cropping(to: area), let png = UIImage(cgImage: crop).pngData() { seen.insert(png) }
        }
        return seen.count
    }

    /// The center stage's face, from the week's title under it.
    private func stage(_ app: XCUIApplication) -> CGRect {
        let title = element(app, beginningWith: "Yo-Yo's week").frame
        return CGRect(x: title.midX - 84, y: title.minY - 8 - 168 - 4, width: 168, height: 168)
    }

    func testAGridCardOpensFromItsFace() {
        let app = launch(at: 17, 20, ["-sampleCharacter", "YES", "-sampleCompanions", "2"])
        let card = app.buttons["week-Yo-Yo"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let face = CGPoint(x: card.frame.minX + 16 + 17, y: card.frame.minY + 16 + 17)
        touch(app, at: face)
        XCTAssertTrue(opened(app), "a touch on the character opens its week")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        touch(app, at: CGPoint(x: card.frame.midX, y: card.frame.midY))
        XCTAssertTrue(opened(app), "and so does one on its name")
    }

    func testAnAllSetCardOpensFromItsFace() {
        let app = launch(at: 23, 30, ["-sampleCharacter", "YES"])
        let card = app.buttons["week-Yo-Yo"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("all set"), "night: the card has folded to all set")
        touch(app, at: CGPoint(x: card.frame.minX + 16 + 23, y: card.frame.midY))
        XCTAssertTrue(opened(app), "a touch on the character opens its week")
    }

    func testTheCompanionsListOpensFromAFace() {
        let app = launch(at: 17, 20, ["-sampleCharacter", "YES"])
        let you = app.buttons["you"]
        you.waitToSettle()
        you.tap()
        let household = app.buttons["household"]
        XCTAssertTrue(household.waitForExistence(timeout: 5))
        reveal(household, in: app)
        household.tap()
        let companions = app.buttons["household-companions"]
        XCTAssertTrue(companions.waitForExistence(timeout: 5))
        reveal(companions, in: app)
        companions.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Yo-Yo")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // The 34 point face at the row's leading edge.
        touch(app, at: CGPoint(x: row.frame.minX + 17, y: row.frame.midY))
        XCTAssertTrue(app.navigationBars["Yo-Yo"].waitForExistence(timeout: 5), "a touch on the character opens Yo-Yo")
    }

    func testAFaceSheetChoiceSelectsFromItsFace() {
        let app = launch(at: 17, 20, ["-sampleCharacter", "YES"])
        let card = app.buttons["week-Yo-Yo"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let change = app.buttons["change-face"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        reveal(change, in: app)
        change.tap()
        let photo = app.buttons["face-photo"]
        let character = app.buttons["face-character"]
        XCTAssertTrue(character.waitForExistence(timeout: 5) && character.isSelected)
        // Each row's 44 point face at its leading edge.
        touch(app, at: CGPoint(x: photo.frame.minX + 22, y: photo.frame.midY))
        XCTAssertTrue(photo.waitForSelection(), "a touch on the photo's face chooses it")
        touch(app, at: CGPoint(x: character.frame.minX + 22, y: character.frame.midY))
        XCTAssertTrue(character.waitForSelection(), "and one on the character's face chooses the character")
    }

    func testTheFacesThatAreTheirOwnTapTargetPlayOnATap() {
        let app = launch(at: 17, 20, ["-sampleCharacter", "YES"])
        let card = app.buttons["week-Yo-Yo"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        // The Today card's 84 point face, beside the name; between turns, so only a tap moves it.
        let today = CGRect(x: card.frame.minX - 10 - 84, y: card.frame.midY - 42, width: 84, height: 84)
        Thread.sleep(forTimeInterval: 4)
        touch(app, at: CGPoint(x: today.midX, y: today.midY))
        XCTAssertGreaterThan(pictures(in: today, for: 2), 1, "a tap on Today's face plays it")
        XCTAssertTrue(card.exists && !element(app, beginningWith: "Yo-Yo's week").exists, "and opens nothing")
        card.tap()
        XCTAssertTrue(opened(app))
        let page = stage(app)
        Thread.sleep(forTimeInterval: 4)
        touch(app, at: CGPoint(x: page.midX, y: page.midY))
        XCTAssertGreaterThan(pictures(in: page, for: 2), 1, "a tap on center stage plays it")
    }

    /// Draws Yo-Yo on the stand-in relay with `script`, up to the meet screen.
    private func meet(_ script: String) -> (XCUIApplication, XCUIElement) {
        let app = launch(at: 17, 20, ["-debugStickerSubject", "dog", "-debugCharacterService", script])
        let card = app.buttons["week-Yo-Yo"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let offer = app.buttons["character-offer"]
        XCTAssertTrue(offer.waitForExistence(timeout: 5))
        offer.tap()
        let draw = app.buttons["character-draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 15))
        draw.tap()
        let pick = app.buttons["character-pick"]
        XCTAssertTrue(pick.waitForExistence(timeout: 15))
        pick.tap()
        let done = app.buttons["character-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        return (app, done)
    }

    /// The stand-in relay takes 8 seconds an animation: every still is there at once, and Done
    /// waits until the movements have come, each mood saying it is still drawing; then the
    /// character saved moves in the evening's mood. In James's build Done came with the stills
    /// and the animations still on their way were dropped.
    func testDoneWaitsForTheAnimationsAndKeepsThemAll() {
        let (app, done) = meet("slow-animations")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(done.isEnabled, "the stills are drawn, the movements are not: Done waits")
        XCTAssertTrue(app.descendants(matching: .any)["character-mood-asleep"].label.contains("Drawing..."), "and the moods say they are drawing")
        snapshot("character-meet-waiting-for-movement")
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: done)
        wait(for: [enabled], timeout: 20)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertGreaterThan(pictures(in: stage(app), for: 12), 1, "the evening's mood moves: its animation was kept")
    }

    /// With no animations at all, Done still comes, and the character rests on its stills.
    func testWithoutAnimationsDoneSavesTheStills() {
        let (app, done) = meet("noAnimations")
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: done)
        wait(for: [enabled], timeout: 15)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertEqual(pictures(in: stage(app), for: 12), 1, "a still that never moves")
    }
}

private extension XCUIElement {
    func waitForSelection(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if isSelected { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
}
