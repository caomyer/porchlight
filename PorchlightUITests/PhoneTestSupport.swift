import XCTest

// One set of helpers for every phone test class (PhoneTests, PhoneTabsTests,
// PhoneHouseholdTests, PhoneRemindersTests, PhoneFoodTests); `waitToSettle` serves the
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
