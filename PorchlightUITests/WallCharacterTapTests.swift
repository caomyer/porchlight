import XCTest

/// A character's face on the wall, touched on its own pixels (`-sampleCharacter`): the rail's
/// entry and a calendar moment open what they open, as they do with a photo or drawn face. In
/// build 20261124.220829 the rail's entry for a character went dead: a tap gesture on the face
/// inside its Button (docs/design/companion-characters.md, "A mood's animation").
///
/// Touches are real ones at screen points, not accessibility activations, which would go
/// round the gestures.
@MainActor
final class WallCharacterTapTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipUnless(isPad, "The wall's tests run on an iPad")
    }

    private func launch(_ screen: String, _ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-startScreen", screen] + extra
        app.launch()
        return app
    }

    private func touch(_ app: XCUIApplication, at point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    func testTheRailEntryOpensFromItsFaceAndName() {
        let faces: [(String, [String])] = [
            ("character", ["-samplePhoto", "YES", "-sampleCharacter", "YES"]), ("sticker", ["-samplePhoto", "YES", "-sampleSticker", "YES"]),
            ("photo", ["-samplePhoto", "YES"]), ("drawn", []),
        ]
        for (face, arguments) in faces {
            for onFace in [true, false] {
                let app = launch("today", arguments)
                let entry = app.buttons["Yo-Yo"].firstMatch
                XCTAssertTrue(entry.waitForExistence(timeout: 30))
                Thread.sleep(forTimeInterval: 1)
                let f = entry.frame
                // The icon's box sits 8 points under the entry's top, 26 high; the name under it.
                touch(app, at: onFace ? CGPoint(x: f.midX, y: f.minY + 8 + 13) : CGPoint(x: f.midX, y: f.maxY - 8 - 6))
                let week = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Yo-Yo's week")).firstMatch
                XCTAssertTrue(week.waitForExistence(timeout: 5), "a touch on the \(face)'s \(onFace ? "face" : "name") in the rail opens Yo-Yo")
                app.terminate()
            }
        }
    }

    func testACalendarMomentOpensFromItsFace() {
        let app = launch("calendar", ["-samplePhoto", "YES", "-sampleCharacter", "YES"])
        let moment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Yo-Yo", "walk")).firstMatch
        XCTAssertTrue(moment.waitForExistence(timeout: 30), "a walk of Yo-Yo's on the week's grid")
        Thread.sleep(forTimeInterval: 1)
        // The mark is the face itself.
        touch(app, at: CGPoint(x: moment.frame.midX, y: moment.frame.midY))
        let edit = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "a touch on the character's face opens the walk")
    }
}
