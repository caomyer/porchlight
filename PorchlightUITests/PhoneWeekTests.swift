import XCTest

/// A companion's week on the phone, in parity with the wall's companion page: the paw
/// trail's dots do what the wall's do, every routine (walks, meals, water) has its own
/// trail and diary, and the page holds up in the night look, at the largest text size
/// and for a first week. Runs only on an iPhone (`scripts/test.sh --phone`).
///
/// Time is pinned to 5:20 pm today, like PhoneTests: this morning's walk is done, the
/// evening walk and dinner are open, and the sample skipped the morning walk four days
/// ago and yesterday's dinner.
@MainActor
final class PhoneWeekTests: XCTestCase, PhoneTestHelpers {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipIf(isPad, "The phone tests run on an iPhone")
    }

    override func tearDown() {
        MainActor.assumeIsolated { restoreLightLook() }
        super.tearDown()
    }

    private static var evening: String {
        UITestClock.at(17, 20)
    }

    private static let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    /// Yo-Yo's water bowl too. A launch argument reaches UserDefaults only with a value.
    private static let water = ["-sampleWater", "YES"]

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.porchlight()
        app.launchArguments = ["-sampleHousehold", "-debugCompanionNow", Self.evening, "-me", "James"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["Hi, James"].waitForExistence(timeout: 60))
        waitUntilResponsive(app)
        return app
    }

    private func openWeek(_ app: XCUIApplication, of name: String = "Yo-Yo") {
        let card = app.buttons["week-\(name)"]
        reveal(card, in: app)
        card.tap()
        XCTAssertTrue(element(app, beginningWith: "\(name)'s week").waitForExistence(timeout: 10), "Tapping a card opens its week")
    }

    /// A trail dot, scrolled into view.
    private func dot(_ app: XCUIApplication, _ routine: String, day: Int, slot: Int) -> XCUIElement {
        let dot = app.buttons["trail-\(routine)-\(day)-\(slot)"]
        XCTAssertTrue(dot.waitForExistence(timeout: 5), "\(routine) day \(day) slot \(slot) is a button")
        reveal(dot, in: app)
        return dot
    }

    /// Closes the care sheet by dragging its grabber to the bottom of the screen, and waits
    /// for it to go. A swipe on a sheet open at full height only lowers it to its smaller
    /// height. The sheet's Save button marks it: the page has its own "Log a walk" button,
    /// so the sheet's title can't.
    private func closeSheet(_ app: XCUIApplication) {
        let save = app.buttons["save-care"]
        for _ in 0..<3 where save.exists {
            let grabber = app.buttons["Sheet Grabber"]
            let start = grabber.exists
                ? grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                : app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
            _ = save.waitForNonExistence(timeout: 3)
        }
        XCTAssertTrue(save.waitForNonExistence(timeout: 10), "The sheet closes")
    }

    // MARK: The paw trail

    /// Mirrors the wall's trail: a logged dot opens its walk to fix, a missed one logs it
    /// for its own day, and one still open today starts a new walk.
    func testTappingThePawTrail() {
        let app = launch()
        openWeek(app)

        let morning = dot(app, "Walk", day: 6, slot: 0)
        XCTAssertTrue(morning.label.hasPrefix("Morning walk, "), morning.label)
        snapshot("week-10-trail")
        morning.tap()
        let edit = app.staticTexts["Edit walk"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "A logged dot opens its walk to fix")
        XCTAssertTrue(app.staticTexts["Fix who, when or how it went"].exists)
        snapshot("week-11-trail-edit")
        closeSheet(app)

        let missed = dot(app, "Walk", day: 2, slot: 0)
        XCTAssertTrue(missed.label.hasSuffix("missed"), missed.label)
        missed.tap()
        XCTAssertTrue(app.staticTexts["YO-YO · MORNING WALK"].waitForExistence(timeout: 5), "A missed dot logs that morning's walk")
        snapshot("week-12-trail-missed")
        closeSheet(app)

        let evening = dot(app, "Walk", day: 6, slot: 1)
        XCTAssertTrue(evening.label.hasSuffix("to do"), evening.label)
        evening.tap()
        XCTAssertTrue(app.staticTexts["YO-YO · EVENING WALK"].waitForExistence(timeout: 5), "Tonight's open dot starts a walk")
        XCTAssertTrue(app.buttons["save-care"].exists)
        snapshot("week-13-trail-new")
        closeSheet(app)
    }

    // MARK: Earlier weeks

    /// The week pager Food's diary has: last week's trail and numbers, a dot still opening its
    /// walk to fix, the streak said to be today's, and back to this week.
    func testEarlierWeeks() {
        let app = launch()
        openWeek(app)
        let back = app.buttons["week-back"]
        reveal(back, in: app)
        back.tap()
        let name = app.descendants(matching: .any)["week-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5) && name.label.hasPrefix("Last week, "), name.label)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "streak today")).firstMatch.exists, "the streak is today's, and says so")
        snapshot("week-20-last-week")
        let dot = self.dot(app, "Walk", day: 6, slot: 0)
        dot.tap()
        XCTAssertTrue(app.staticTexts["Edit walk"].waitForExistence(timeout: 5), "last week's dot opens its walk to fix")
        closeSheet(app)
        let this = app.buttons["week-this"]
        reveal(this, in: app)
        this.tap()
        XCTAssertTrue(name.label.hasPrefix("This week, "), name.label)
    }

    /// Last week at the largest text size in the night look: the pager and the page whole.
    func testEarlierWeekLooks() {
        XCUIDevice.shared.appearance = .dark
        let app = launch(Self.largest)
        openWeek(app)
        let back = app.buttons["week-back"]
        reveal(back, in: app)
        back.tap()
        XCTAssertTrue(app.descendants(matching: .any)["week-name"].label.hasPrefix("Last week, "))
        snapshot("week-21-last-week-largest-dark")
    }

    // MARK: Every routine

    /// Meals have their own trail and diary: yesterday's skipped dinner shows in both, and
    /// a dinner logged from the trail appears in both.
    func testAMealInTheDiaryAndTheTrail() {
        let app = launch()
        openWeek(app)
        let feed = app.buttons["routine-Feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 5), "Each routine has its week")
        feed.tap()
        XCTAssertTrue(feed.isSelected)
        XCTAssertTrue(element(app, beginningWith: "Meal diary").waitForExistence(timeout: 5))
        XCTAssertTrue(dot(app, "Feed", day: 5, slot: 1).label.hasSuffix("missed"), "Yesterday's dinner was skipped")
        snapshot("week-20-meals")

        let dinner = dot(app, "Feed", day: 6, slot: 1)
        XCTAssertTrue(dinner.label.hasPrefix("Dinner, "), dinner.label)
        XCTAssertTrue(dinner.label.hasSuffix("to do"), dinner.label)
        dinner.tap()
        XCTAssertTrue(app.staticTexts["YO-YO · DINNER"].waitForExistence(timeout: 5), "Tonight's open dinner starts a meal")
        // The sheet's Save button marks it: the page has a "Log a meal" button of its own.
        let save = app.buttons["save-care"]
        reveal(save, in: app)
        save.waitToSettle()
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10), "Saving closes the sheet")
        XCTAssertTrue(app.staticTexts["Meal logged"].waitForExistence(timeout: 10), "The toast says it was logged")
        XCTAssertTrue(app.buttons["trail-Feed-6-1"].label.hasSuffix("James"), "Tonight's dinner is in the trail, mine")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Today 5:20'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "and in the diary")
        reveal(row, in: app)
        snapshot("week-21-meal-logged")

        let chef = element(app, beginningWith: "Chef of the week")
        reveal(chef, in: app)
        XCTAssertTrue(chef.exists, "The meals' podium")
        snapshot("week-22-meals-podium")
    }

    /// Water has its week too.
    func testWater() {
        let app = launch(Self.water)
        openWeek(app)
        app.buttons["routine-Water"].tap()
        XCTAssertTrue(element(app, beginningWith: "Water diary").waitForExistence(timeout: 5), "A dog's bowl, not a plant's watering")
        XCTAssertEqual(app.buttons["log-routine"].label, "Log a refill")
        XCTAssertTrue(dot(app, "Water", day: 4, slot: 0).label.hasSuffix("missed"), "Two days ago's water was skipped")
        snapshot("week-30-water")
    }

    // MARK: Looks

    /// The real page in the night look at the largest text size, for what only it shows: each
    /// routine's tab and its log button can be scrolled to and reached, with walks, meals and
    /// water. One launch. How the whole page looks and fits in each look is
    /// `PocketWeekScreenTests` (unit bundle), which hosts and draws it; this test used to
    /// scroll the page top to bottom and back nine times over three launches, six to twelve
    /// minutes, and failed twice on a scroll that fell short.
    func testWeekLooks() {
        XCUIDevice.shared.appearance = .dark
        let app = launch(Self.water + Self.largest)
        let window = app.windows.firstMatch.frame
        openWeek(app)
        snapshot("week-40-largest-dark-top")
        for routine in ["Walk", "Feed", "Water"] {
            let tab = app.buttons["routine-\(routine)"]
            reveal(tab, in: app)
            XCTAssertTrue(window.contains(tab.frame), "\(routine)'s tab is whole on screen: \(tab.frame)")
            tab.tap()
            XCTAssertTrue(tab.isSelected, "\(routine) is picked")
            let log = app.buttons["log-routine"]
            reveal(log, in: app)
            XCTAssertTrue(log.isHittable && window.contains(log.frame), "The log button is whole on screen")
            snapshot("week-41-largest-dark-\(routine.lowercased())")
        }
    }

    /// Log a walk from the companion page, on a 24-hour clock, and open its time: the card
    /// is whole wherever the pill sits, its suggestions uncut, and every key and Done in
    /// reach. Once the card came up above a pill in the middle of the screen with less room
    /// than it needs, and the system cut it at both ends: no 0, no delete, no Done.
    func testTheTimeCardIsWhole() {
        let app = launch(["-AppleLocale", "en_GB"])
        openWeek(app)
        let log = app.buttons["log-routine"]
        reveal(log, in: app)
        log.tap()
        let time = app.buttons["exact-time"]
        XCTAssertTrue(time.waitForExistence(timeout: 5), "The care sheet has its time")
        time.tap()
        let done = app.buttons["time-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The time card opens")
        snapshot("week-60-time-card")
        let window = app.windows.firstMatch.frame
        for key in ["key-0", "key-delete", "key-1", "time-done"] {
            let button = app.buttons[key]
            XCTAssertTrue(button.exists && button.isHittable, "\(key) is in reach")
            XCTAssertTrue(window.contains(button.frame), "\(key) is whole on screen: \(button.frame)")
        }
        // The first suggestion, whole and inside the card with the keys below it.
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Just'")).firstMatch
        XCTAssertTrue(chip.exists && chip.isHittable, "The first suggestion is in reach")
        XCTAssertTrue(window.contains(chip.frame), "and whole on screen: \(chip.frame)")
        let hour = app.buttons["time-hour"]
        XCTAssertLessThan(chip.frame.maxY, hour.frame.minY, "above the time, not cut by the card's edge")

        // Typing 0 works: the minutes become 10.
        XCTAssertFalse(app.buttons["PM"].exists, "a 24-hour clock")
        let startHour = hour.value as? String ?? ""
        app.buttons["time-minute"].tap()
        app.buttons["key-1"].tap()
        app.buttons["key-0"].tap()
        XCTAssertEqual(app.buttons["time-minute"].value as? String, "10")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done closes the card")
        XCTAssertTrue((time.value as? String)?.hasPrefix("\(startHour):10") == true, "and the walk starts at \(startHour):10: \(time.value ?? "")")
    }

    /// The photo sticker from the companion's page (docs/design/companion-characters.md): the
    /// page's quiet link to the face, the sheet with the photo and the sticker cut from it, the
    /// sticker ticked and shown once used, and switching faces back and forth, which redraws
    /// nothing. The cut-out is a drawn stand-in (`-debugStickerSubject`) and the photo is drawn
    /// in code (`-samplePhoto`).
    func testMakingThePhotoStickerAndSwitchingFaces() {
        let app = launch(["-samplePhoto", "YES", "-debugStickerSubject", "dog"])
        openWeek(app)
        XCTAssertFalse(app.buttons["character-offer"].exists, "no offer while this build can't draw")
        let change = app.buttons["change-face"]
        reveal(change, in: app)
        XCTAssertEqual(change.label, "Change Yo-Yo's character or photo")
        change.tap()
        let photo = app.buttons["face-photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "The face sheet lists the faces there are")
        XCTAssertTrue(photo.isSelected, "the photo shows now")
        XCTAssertFalse(app.buttons["face-sticker"].exists)
        snapshot("face-01-sheet")
        app.buttons["make-sticker"].tap()
        let use = app.buttons["use-sticker"]
        XCTAssertTrue(use.waitForExistence(timeout: 15), "It cuts Yo-Yo out")
        XCTAssertTrue(app.images["sticker-preview"].exists, "and shows the sticker beside the photo")
        XCTAssertTrue(app.staticTexts["Porchlight cut Yo-Yo out of the photo on this phone. Nothing is sent anywhere."].exists)
        snapshot("face-02-sticker")
        use.tap()
        let sticker = app.buttons["face-sticker"]
        XCTAssertTrue(sticker.waitForExistence(timeout: 5), "Back on the faces, the sticker is one of them")
        XCTAssertTrue(sticker.isSelected, "and shows")
        snapshot("face-03-sticker-chosen")
        photo.tap()
        XCTAssertTrue(photo.isSelected, "The photo again")
        sticker.tap()
        XCTAssertTrue(sticker.isSelected, "and the sticker again, at once: nothing is cut again")
        XCTAssertFalse(app.staticTexts["sticker-cutting"].exists)
        app.buttons["face-done"].tap()
        XCTAssertTrue(sticker.waitForNonExistence(timeout: 5), "Done closes the sheet")
        app.swipeDown()
        app.swipeDown()
        snapshot("face-04-page")
    }

    /// Drawing a character on the stand-in relay (`-debugCharacterService draws`): the offer
    /// on the page, the consent with the photo and its cut-out side by side, three tries,
    /// the four moods, and the character shown and chosen once done.
    func testDrawingACharacter() {
        let app = launch(["-samplePhoto", "YES", "-debugStickerSubject", "dog", "-debugCharacterService", "draws"])
        openWeek(app)
        let offer = app.buttons["character-offer"]
        XCTAssertTrue(offer.waitForExistence(timeout: 5), "The page offers a character for a dog with a photo")
        XCTAssertEqual(offer.label, "Draw Yo-Yo")
        snapshot("character-01-offer")
        offer.tap()
        let draw = app.buttons["character-draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 15), "The consent comes once Yo-Yo is cut out")
        XCTAssertTrue(app.images["character-cutout"].exists, "with the cut-out beside the photo")
        // Longer than an identifier query takes, so matched by its label.
        let consent = "Only the cut-out of Yo-Yo goes to OpenAI to be drawn. The rest of the photo stays on this phone. OpenAI doesn't train on it and deletes it within 30 days."
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", consent)).firstMatch.exists, "it says what is sent, and to whom")
        snapshot("character-02-consent")
        draw.tap()
        let pick = app.buttons["character-pick"]
        XCTAssertTrue(pick.waitForExistence(timeout: 15), "Three tries to pick from")
        XCTAssertEqual(app.buttons["character-try-again"].label, "None of these: try again (2 left)")
        app.buttons["character-try-1"].tap()
        snapshot("character-03-pick")
        pick.tap()
        let done = app.buttons["character-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Meet Yo-Yo")
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: done)
        wait(for: [enabled], timeout: 20)
        snapshot("character-04-meet")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done closes the sheet")
        XCTAssertFalse(offer.exists, "and the offer has gone")
        let change = app.buttons["change-face"]
        reveal(change, in: app)
        change.tap()
        let character = app.buttons["face-character"]
        XCTAssertTrue(character.waitForExistence(timeout: 5))
        XCTAssertTrue(character.isSelected, "the character shows, for the whole household")
        snapshot("character-05-chosen")
    }

    /// A character and a photo sticker (`-sampleCharacter`, `-sampleSticker`, drawn in code)
    /// wherever Yo-Yo shows on the phone, light and dark: Today and Yo-Yo's page, standing on
    /// the card with no disc behind them, and no offer once there is one. Review shots.
    func testTheCharacterEverywhereOnThePhone() {
        for face in ["Character", "Sticker"] {
            for dark in [false, true] {
                XCUIDevice.shared.appearance = dark ? .dark : .light
                let app = launch(["-samplePhoto", "YES", "-sample\(face)", "YES"])
                let look = "\(face.lowercased())-\(dark ? "dark" : "light")"
                snapshot("face-30-phone-today-\(look)")
                openWeek(app)
                XCTAssertFalse(app.buttons["character-offer"].exists, "no offer once Yo-Yo has a \(face.lowercased())")
                snapshot("face-31-phone-page-\(look)")
                app.terminate()
            }
        }
        XCUIDevice.shared.appearance = .light
    }

    /// From the page's header, the same face sheet as the wall hero's: for a companion with a
    /// character and two rounds left, the faces with the character ticked, a new character to
    /// draw, a sticker to make, and removing the character, which asks first and says the rounds.
    func testChangingTheCharacterFromThePage() {
        let app = launch(["-samplePhoto", "YES", "-sampleCharacter", "YES", "-debugCharacterService", "draws"])
        openWeek(app)
        let change = app.buttons["change-face"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), "The header links to the face")
        XCTAssertEqual(change.label, "Change Yo-Yo's character or photo")
        snapshot("face-40-phone-header")
        change.tap()
        let character = app.buttons["face-character"]
        XCTAssertTrue(character.waitForExistence(timeout: 5))
        XCTAssertTrue(character.isSelected, "the character shows")
        for face in ["photo", "drawn"] { XCTAssertTrue(app.buttons["face-\(face)"].exists, "\(face) is a face to choose") }
        XCTAssertEqual(app.buttons["draw-character"].label, "Draw a new character")
        XCTAssertEqual(app.buttons["make-sticker"].label, "Make a photo sticker")
        let remove = app.buttons["remove-character"]
        XCTAssertTrue(remove.exists)
        snapshot("face-41-phone-sheet")
        remove.tap()
        let detail = "Its moods are deleted on every device. Drawing another one uses a round of tries again. 2 rounds are left."
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", detail)).firstMatch.waitForExistence(timeout: 5),
                      "it asks first, and says the rounds left")
        snapshot("face-42-phone-remove")
    }

    /// Today and the page with each kind of face (a character and a sticker drawn in code, a
    /// photo drawn in code, the drawn face), light and dark, and at the largest text. Review
    /// shots of the faces' presence (docs/design/companion-characters.md, "Where it stands").
    func testFacesOnTodayAndThePage() {
        let faces: [(String, [String])] = [
            ("character", ["-samplePhoto", "YES", "-sampleCharacter", "YES"]), ("sticker", ["-samplePhoto", "YES", "-sampleSticker", "YES"]),
            ("photo", ["-samplePhoto", "YES"]), ("drawn", []),
        ]
        for (face, arguments) in faces {
            for look in ["light", "dark", "largest"] {
                XCUIDevice.shared.appearance = look == "dark" ? .dark : .light
                let app = launch(arguments + (look == "largest" ? Self.largest : []))
                snapshot("presence-today-\(face)-\(look)")
                openWeek(app)
                snapshot("presence-page-\(face)-\(look)")
                app.terminate()
            }
        }
        XCUIDevice.shared.appearance = .light
    }

    /// A companion added today: the first week, never a zero, in the wall's words.
    func testAFirstWeek() {
        let app = launch(["-sampleCompanions", "4"])
        openWeek(app, of: "Pip")
        XCTAssertTrue(element(app, beginningWith: "Pip's week").exists)
        XCTAssertTrue(element(app, beginningWith: "Mood, Waiting for first meal").exists, "No mood before the first meal")
        snapshot("week-50-first-week")
        let empty = element(app, beginningWith: "Nothing logged this week yet. The first meal starts the story.")
        reveal(empty, in: app)
        XCTAssertTrue(empty.exists)
        let podium = element(app, beginningWith: "No meals yet this week. The podium is wide open.")
        reveal(podium, in: app)
        XCTAssertTrue(podium.exists)
        snapshot("week-51-first-week-end")
    }
}
