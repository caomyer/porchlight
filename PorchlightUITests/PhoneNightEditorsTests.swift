import XCTest

/// The phone's editor sheets in the night look, read from the screen: a chosen chip is a
/// dark tint the light words stand out on, never the light look's pale wash. In build
/// 20261125.034137 the chore editor's chosen chips were near white with light words on them
/// (`Color.wash` mixed in the light look unless told otherwise). Review shots of every editor.
@MainActor
final class PhoneNightEditorsTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = true
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    override func tearDown() {
        MainActor.assumeIsolated { restoreLightLook() }
        super.tearDown()
    }

    private func launch(_ dark: Bool, _ extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", UITestClock.at(17, 20), "-me", "James"] + extra
        app.launch()
        if extra.contains("-startScreen") {
            _ = app.otherElements.firstMatch.waitForExistence(timeout: 60)
        } else {
            XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        }
        waitUntilResponsive(app)
        return app
    }

    /// How light the screen is just inside a chip's trailing edge, from 0 (black) to 1 (white).
    private func fillLightness(of chip: XCUIElement) -> CGFloat {
        lightness(at: CGPoint(x: chip.frame.maxX - 8, y: chip.frame.midY))
    }

    /// Whether the app is drawn in the night look at all: the sheet's paper by the left edge.
    /// On iOS 27 simulators (the CI runners' and a Mac's), `XCUIDevice.appearance` doesn't
    /// change the look and every screen stays light; then the chips can't be judged here, and
    /// `PocketEditorsScreenTests` judges them in a hosted window whose look is its own.
    private func requireNight(_ app: XCUIApplication) throws {
        try XCTSkipUnless(isNight(app), "The simulator didn't take the night look; see PocketEditorsScreenTests")
    }

    private func isNight(_ app: XCUIApplication) -> Bool {
        lightness(at: CGPoint(x: 10, y: app.windows.firstMatch.frame.midY)) < 0.5
    }

    private func lightness(at spot: CGPoint) -> CGFloat {
        let shot = XCUIScreen.main.screenshot().image
        guard let cg = shot.cgImage else { return -1 }
        let scale = CGFloat(cg.width) / shot.size.width
        let point = CGPoint(x: spot.x * scale, y: spot.y * scale)
        guard let pixel = cg.cropping(to: CGRect(x: point.x.rounded(), y: point.y.rounded(), width: 1, height: 1)) else { return -1 }
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (0.2126 * CGFloat(bytes[0]) + 0.7152 * CGFloat(bytes[1]) + 0.0722 * CGFloat(bytes[2])) / 255
    }

    /// Every chosen chip on screen (a capsule button 42 points high) is dark at night.
    private func chosenChipsAreDark(_ app: XCUIApplication, _ screen: String, expecting least: Int = 1) {
        // The tab bar's chosen tab is not a chip.
        let tabs = Set(app.tabBars.buttons.allElementsBoundByIndex.map(\.frame.debugDescription))
        let chosen = app.buttons.matching(NSPredicate(format: "isSelected == true")).allElementsBoundByIndex
            .filter { $0.frame.height > 36 && $0.frame.height < 48 && $0.frame.width > 48 && app.windows.firstMatch.frame.contains($0.frame) }
            .filter { !tabs.contains($0.frame.debugDescription) }
        XCTAssertGreaterThanOrEqual(chosen.count, least, "\(screen): chosen chips on screen")
        for chip in chosen {
            let lightness = fillLightness(of: chip)
            XCTAssertLessThan(lightness, 0.4, "\(screen), \(chip.label): a chosen chip is dark at night, not \(lightness)")
        }
    }

    func testANewChoreAtNight() throws {
        let app = launch(true)
        app.buttons["see-all"].tap()
        XCTAssertTrue(app.staticTexts["Pitch in"].waitForExistence(timeout: 5))
        app.buttons["add-chore"].tap()
        XCTAssertTrue(app.staticTexts["New chore"].waitForExistence(timeout: 5))
        try requireNight(app)
        let once = app.buttons["Just once"]
        once.tap()
        XCTAssertTrue(once.isSelected)
        snapshot("night-01-new-chore")
        chosenChipsAreDark(app, "new chore", expecting: 2)
        app.buttons["Some days"].tap()
        snapshot("night-02-some-days")
        chosenChipsAreDark(app, "some days", expecting: 2)
    }

    /// The same sheet by day, unchanged: a review shot beside the night one.
    func testANewChoreByDay() {
        let app = launch(false)
        app.buttons["see-all"].tap()
        XCTAssertTrue(app.staticTexts["Pitch in"].waitForExistence(timeout: 5))
        app.buttons["add-chore"].tap()
        XCTAssertTrue(app.staticTexts["New chore"].waitForExistence(timeout: 5))
        app.buttons["Some days"].tap()
        snapshot("day-02-some-days")
    }

    func testTheHouseholdsEditorsAtNight() {
        for (page, row, shot) in [("chores", "chore-", "night-03-chore"), ("rewards", "reward-", "night-04-reward")] {
            let app = launch(true, ["-startScreen", "you", "-debugYouPage", page])
            let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", row)).firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 10), "a row on \(page)")
            first.tap()
            Thread.sleep(forTimeInterval: 1)
            snapshot(shot)
            if isNight(app) { chosenChipsAreDark(app, page) }
            if page == "rewards" {
                // Beside the goal, three buttons once broke their words letter by letter.
                for title in ["Save", "Start over", "Archive"] {
                    let button = app.buttons[title]
                    reveal(button, in: app)
                    XCTAssertLessThan(button.frame.height, 70, "\(title) is one line")
                    XCTAssertGreaterThan(button.frame.width, app.windows.firstMatch.frame.width / 2, "\(title) spans the sheet, as the chore editor's do")
                }
            }
            app.terminate()
        }
        let app = launch(true, ["-startScreen", "you", "-debugYouPage", "companion"])
        Thread.sleep(forTimeInterval: 2)
        snapshot("night-05-companion")
        app.terminate()
    }

    func testADinnerAtNight() {
        let app = launch(true)
        app.open(URL(string: "porchlight://lists")!)
        let dinners = app.buttons["This week's dinners"]
        XCTAssertTrue(dinners.waitForExistence(timeout: 10))
        dinners.tap()
        XCTAssertTrue(app.staticTexts["Dinners"].waitForExistence(timeout: 5))
        snapshot("night-06-dinners")
        let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add")).firstMatch
        if day.waitForExistence(timeout: 3) {
            day.tap()
            Thread.sleep(forTimeInterval: 1)
            snapshot("night-07-dinner")
        }
    }
}
