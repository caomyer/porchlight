import XCTest

// One set of helpers for every phone test class (PhoneTests, PhoneTabsTests,
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
        let colors = [51, 56].flatMap { row in xs.map { pixel(image, x: $0, y: Int(CGFloat(row) * scale)) } }
        let first = colors[0]
        let off = colors.filter { color in zip(color, first).contains { abs(Int($0) - Int($1)) > 6 } }
        XCTAssertTrue(off.isEmpty, "\(name): something shows under the status bar (\(off.count) of \(colors.count) samples differ)", file: file, line: line)
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return Array(bytes.prefix(3))
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
    func element(_ app: XCUIApplication, beginningWith part: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", part)).firstMatch
    }

    /// Scrolls a little at a time until `element` is wholly in view, above the tab bar
    /// when there is one.
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let tabBar = app.tabBars.firstMatch
        let bottom = tabBar.exists ? tabBar.frame.minY : window.maxY
        let visible = CGRect(x: window.minX, y: window.minY, width: window.width, height: bottom - window.minY)
        for _ in 0..<14 where !(element.exists && element.isHittable && visible.contains(element.frame)) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
    }

    /// Types into a field a key at a time and checks it all arrived, trying again from a
    /// cleared field if not: on a busy simulator a fast `typeText` can drop keys, and so
    /// can typing while a field that focuses itself is still taking focus.
    func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 {
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            let current = field.value as? String ?? ""
            if !current.isEmpty, current != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            for character in text {
                field.typeText(String(character))
            }
            if field.value as? String == text { return }
        }
        XCTFail("Every key of \"\(text)\" should arrive in the field")
    }
}
