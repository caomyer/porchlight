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

    /// Scrolls a little at a time until `element` is wholly in view, above the tab bar and
    /// the keyboard when they are up: up the page when it is above the screen (a test that
    /// looked further down first), else down. A tap never relies on XCUITest scrolling for
    /// it, which on iOS 27, under the floating tab bar, can stop short and tap nothing.
    ///
    /// It gives up after 14 drags, or as soon as two drags in a row move nothing (the page
    /// is at its end, or the element isn't on it), and then fails naming the element; it
    /// never scrolls forever.
    func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        func visible() -> CGRect {
            let window = app.windows.firstMatch.frame
            let tabBar = app.tabBars.firstMatch
            let keyboard = app.keyboards.firstMatch
            // A tab bar behind a full-screen cover still exists, but covers nothing.
            let bottom = min(tabBar.exists && tabBar.isHittable ? tabBar.frame.minY : window.maxY, keyboard.exists ? keyboard.frame.minY : window.maxY)
            return CGRect(x: window.minX, y: window.minY, width: window.width, height: bottom - window.minY)
        }
        func inView() -> Bool { element.exists && element.isHittable && visible().contains(element.frame) }
        var still = 0
        for _ in 0..<14 where !inView() {
            let before = element.exists ? element.frame : app.windows.firstMatch.frame
            let above = element.exists && element.frame.minY < visible().minY
            let (from, to) = above ? (0.45, 0.7) : (0.7, 0.45)
            // Within what shows: a drag that starts on the keyboard moves nothing.
            let area = visible()
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: area.midX, dy: area.minY + area.height * from))
            start.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: area.midX, dy: area.minY + area.height * to)))
            let after = element.exists ? element.frame : app.windows.firstMatch.frame
            still = after == before ? still + 1 : 0
            if still >= 2 { break }
        }
        // Fails only when it can't be tapped where it is.
        // (A sheet's bottom button can reach past the screen's edge and still be tapped.)
        if !(element.exists && element.isHittable) {
            XCTFail("Couldn't bring \(element) into view (exists: \(element.exists), frame: \(element.frame), visible: \(visible()))", file: file, line: line)
        }
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
        for _ in 0..<3 {
            if !hasFocus(field, within: 1) {
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
