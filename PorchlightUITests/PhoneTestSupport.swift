import XCTest

// One set of helpers for every phone test class (PhoneTests, PhoneTabsTests, PhoneWeekTests,
// PhoneHouseholdTests, PhoneRemindersTests, PhoneFoodTests, PhoneSetupTests); `waitToSettle` serves the
// wall's sheets too.

extension XCUIElement {
    /// Waits for an element in a sheet that is still sliding up to come to rest: a tap
    /// computed mid-slide can land outside the sheet and close it.
    func waitToSettle() {
        var last = frame
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.15)
            let now = frame
            if now == last && isHittable { return }
            last = now
        }
    }
}

/// The phone test classes' shared helpers; a class adopts them by conforming.
@MainActor
protocol PhoneTestHelpers: XCTestCase {}

/// Puts the simulator back in the light look after a test that turned it dark, quitting the
/// app first. Turned back with the app still open, the app redraws every screen it holds in
/// the new look while the next test's launch is quitting it; on a busy hosted Mac that quit
/// once took 70 seconds and the launch failed ("Failed to terminate"). A test that left the
/// look alone costs nothing here.
@MainActor
func restoreLightLook() {
    guard XCUIDevice.shared.appearance != .light else { return }
    XCUIApplication().terminate()
    XCUIDevice.shared.appearance = .light
}

@MainActor
extension PhoneTestHelpers {
    /// Attaches a screenshot of the whole screen, kept with the results.
    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls the page down a screenful, then checks that the band of the status bar just
    /// under the Dynamic Island is one flat color: paper, with nothing scrolled under the
    /// clock. Attaches the screenshot as `name`.
    func expectPaperUnderStatusBar(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        Thread.sleep(forTimeInterval: 1)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let image = screenshot.image.cgImage else { return XCTFail("No screenshot", file: file, line: line) }
        let scale = CGFloat(image.width) / app.windows.firstMatch.frame.width
        // Between the island's bottom (about 48 pt) and the safe area's (59 pt), across the
        // middle of the screen, clear of the clock and the battery.
        let xs = stride(from: Int(CGFloat(image.width) * 0.12), to: Int(CGFloat(image.width) * 0.88), by: 3).map { $0 }
        let colors = [51, 56].flatMap { row in
            let pixels = pixelRow(image, y: Int(CGFloat(row) * scale))
            return xs.map { Array(pixels[$0 * 4 ..< $0 * 4 + 3]) }
        }
        let first = colors[0]
        let off = colors.filter { color in zip(color, first).contains { abs(Int($0) - Int($1)) > 6 } }
        XCTAssertTrue(off.isEmpty, "\(name): something shows under the status bar (\(off.count) of \(colors.count) samples differ)", file: file, line: line)
    }

    /// One row of the image, four bytes (RGBA) a pixel. Drawn once a row: drawing the whole
    /// screenshot once for each of some 600 pixels took 17 minutes on a busy hosted Mac.
    private func pixelRow(_ image: CGImage, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: 1, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return bytes
    }

    /// Taps the toast's action (Undo, I went too) once the toast has finished sliding in:
    /// a tap computed mid-slide misses it, and the toast goes by itself.
    func tapToastAction(_ app: XCUIApplication) {
        let action = app.buttons["toast-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.waitToSettle()
        action.tap()
    }

    /// The first element whose label begins with `part`.
    /// Waits, up to `timeout`, until the app answers two looks at its screen in a row
    /// promptly. The first launch after a simulator boots can spend seconds drawing its first
    /// frame (the color emoji font is read in from the runtime's disk image), and a tap sent
    /// then times out ("Timed out while synthesizing event"); a look at the screen waits for
    /// the same main thread, so a prompt answer means a tap will land.
    func waitUntilResponsive(_ app: XCUIApplication, timeout: TimeInterval = 60) {
        let deadline = Date.now.addingTimeInterval(timeout)
        var prompt = 0
        while Date.now < deadline {
            let asked = Date.now
            _ = app.windows.firstMatch.exists
            prompt = Date.now.timeIntervalSince(asked) < 2 ? prompt + 1 : 0
            if prompt >= 2 { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("The app should answer promptly within \(Int(timeout)) seconds of launching")
    }

    func element(_ app: XCUIApplication, beginningWith part: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", part)).firstMatch
    }

    /// Scrolls until `element` is wholly in view, above the tab bar and the keyboard when
    /// they are up: up the page when it is above the screen (a test that looked further down
    /// first), else down. A tap never relies on XCUITest scrolling for it, which on iOS 27,
    /// under the floating tab bar, can stop short and tap nothing.
    ///
    /// Far from the target each drag is long and quick and lets the page coast; near it, each
    /// covers the distance still to go and holds at the end so the page doesn't coast past. It tells
    /// stuck from far: it stops when two drags in a row move nothing (the page is at its end)
    /// or when four in a row bring the element no closer, and the number of drags is capped
    /// by the distance it started from, so a page of any honest length is reachable and the
    /// loop always ends. Then it fails naming the element if it still can't be tapped.
    func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Every question to the app costs a round trip, so each drag asks only what it needs:
        // the window and what floats over the page's bottom once, then per drag the keyboard
        // and the element.
        let window = app.windows.firstMatch.frame
        let floor = pageFloor(in: app, window: window)
        let keyboard = app.keyboards.firstMatch
        func visible() -> CGRect {
            let bottom = min(floor, keyboard.exists ? keyboard.frame.minY : window.maxY)
            return CGRect(x: window.minX, y: window.minY, width: window.width, height: bottom - window.minY)
        }
        /// Where the element is now, nil when it isn't on the page (a lazy list loads it later).
        func frame() -> CGRect? {
            guard element.exists else { return nil }
            let frame = element.frame
            return frame.isEmpty ? nil : frame
        }
        /// How far it still is from what shows: positive below, negative above.
        func distance(_ frame: CGRect?, _ area: CGRect) -> CGFloat? {
            guard let frame else { return nil }
            if frame.maxY > area.maxY { return frame.maxY - area.maxY }
            if frame.minY < area.minY { return frame.minY - area.minY }
            return 0
        }
        /// What moves when the page does, for an element that isn't on it yet.
        let landmark = app.staticTexts.element(boundBy: 0)

        var area = visible()
        var now = frame()
        let height = max(area.height, 1)
        let cap = min(max(14, Int((abs(distance(now, area) ?? 0) / (height * 0.5)).rounded(.up)) + 8), 200)
        var still = 0, farther = 0
        var best = abs(distance(now, area) ?? .greatestFiniteMagnitude)
        for _ in 0..<cap {
            var gap = distance(now, area)
            if let now, area.contains(now) {
                if element.isHittable { break }
                // In view yet under something that floats (a Snap button over the tab bar):
                // bring it toward the middle.
                gap = now.midY - area.midY
            }
            let down = (gap ?? 1) >= 0
            // Far away (or not on the page yet), a long quick drag that lets the page coast;
            // near, the remaining distance and a little, held so it stops where it should.
            let far = abs(gap ?? .greatestFiniteMagnitude) > area.height * 1.5
            let travel = far ? area.height * 0.7 : min(max(abs(gap ?? area.height) + 24, area.height * 0.2), area.height * 0.6)
            let middle = area.minY + area.height / 2
            let (from, to) = down ? (middle + travel / 2, middle - travel / 2) : (middle - travel / 2, middle + travel / 2)
            let before = now ?? (landmark.exists ? landmark.frame : .zero)
            // Within what shows: a drag that starts on the keyboard moves nothing.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: area.midX, dy: from)).press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: area.midX, dy: to)),
                withVelocity: far ? .fast : .default,
                thenHoldForDuration: far ? 0 : 0.1
            )
            area = visible()
            now = frame()
            still = (now ?? (landmark.exists ? landmark.frame : .zero)) == before ? still + 1 : 0
            if still >= 2 { break }
            if let gap = distance(now, area).map(abs) {
                if gap < best { best = gap; farther = 0 } else { farther += 1 }
                if farther >= 4 { break }
            }
        }
        // Fails only when it can't be tapped where it is.
        // (A sheet's bottom button can reach past the screen's edge and still be tapped.)
        if !(element.exists && element.isHittable) {
            XCTFail("Couldn't bring \(element) into view (exists: \(element.exists), frame: \(element.frame), visible: \(visible()))", file: file, line: line)
        }
    }

    /// Where the page stops showing at the bottom: the top of the tab bar, and of a bar that
    /// floats over the page above it ("Snap a meal") which the page scrolls under. Neither
    /// counts under a sheet or a full-screen cover, which hide them without removing them:
    /// a sheet is marked by the region that dismisses it, and a cover leaves the tab bar
    /// unhittable. XCUITest calls a row under a floating bar hittable, so its frame is what tells.
    private func pageFloor(in app: XCUIApplication, window: CGRect) -> CGFloat {
        if app.otherElements["PopoverDismissRegion"].exists { return window.maxY }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.exists, tabBar.isHittable else { return window.maxY }
        let floating = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["snap-meal"])).firstMatch
        return floating.exists ? min(tabBar.frame.minY, floating.frame.minY) : tabBar.frame.minY
    }

    /// Types into a field a key at a time and checks it all arrived, trying again from a
    /// cleared field if not: on a busy simulator a fast `typeText` can drop keys, and so
    /// can typing while a field that focuses itself is still taking focus.
    ///
    /// Each key waits for the field to hold the keyboard focus, which on a slow simulator
    /// (iOS 26 especially) it reports a moment after each key, and a field the app focused
    /// itself is not tapped again: a tap computed from the new layout can land on what the
    /// screen still shows there, like the "Add someone" a new row is replacing.
    func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The field should be there to type into")
        for attempt in 0..<3 {
            // A field can hold the focus while its keys go nowhere (the keyboard's session
            // not yet joined to it): after a try that didn't arrive, tap it to join them again.
            if attempt > 0 || !hasFocus(field, within: 1) {
                field.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
                guard hasFocus(field, within: 10) else { continue }
            }
            let current = field.value as? String ?? ""
            if !current.isEmpty, current != field.placeholderValue {
                app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            for character in text {
                guard hasFocus(field, within: 10) else { break }
                app.typeText(String(character))
            }
            if field.value as? String == text { return }
        }
        XCTFail("Every key of \"\(text)\" should arrive in the field")
    }

    /// Whether `field` holds the keyboard focus, or comes to within `seconds`.
    private func hasFocus(_ field: XCUIElement, within seconds: TimeInterval) -> Bool {
        let deadline = Date.now.addingTimeInterval(seconds)
        repeat {
            if field.exists, (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date.now < deadline
        return false
    }
}
