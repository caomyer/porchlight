import XCTest

/// The time every UI test gives the app instead of the real one, so that what the sample
/// household holds, which day is today and which week is this week are the same whenever
/// the suite runs (docs/design/testing.md, the hard rule "A test's outcome never depends on
/// the real clock"). A pinned clock stands still.
///
/// `XCUIApplication.porchlight()` hands every launch `midweek` in its environment
/// (`PORCHLIGHT_NOW`), so a test is pinned without asking. A test that needs another time
/// of day passes `-debugCompanionNow` with `at(_:_:)`, which is the same day at that time
/// and takes precedence. The day is never the real one.
///
/// On the real clock the sample household is built backwards from the minute of the
/// launch, and two tests failed on it at midnight UTC on Sunday, November 22, 2026: one
/// opened the Food page at 11:59 pm and the meal it was about to tap moved a day back at
/// midnight, and one opened the week grid six minutes into the week, before any walk.
/// `SampleClockTests` in the unit tests holds what the sample has at this time.
enum UITestClock {
    private static let year = 2026, month = 11, dayOfMonth = 18

    /// A Wednesday at 10:30 in the morning: this week has days behind it and days ahead,
    /// the morning's walk and breakfast are done, and the evening's are still to come.
    static let midweek = at(10, 30)

    /// The pinned day at another time, for `-debugCompanionNow`.
    static func at(_ hour: Int, _ minute: Int) -> String {
        String(format: "%04d-%02d-%02dT%02d:%02d", year, month, dayOfMonth, hour, minute)
    }

    /// A day counted from the pinned one, as "yyyy-MM-dd": `day(-1)` is its yesterday.
    static func day(_ offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let pinned = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))!
        let parts = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: offset, to: pinned)!)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

extension XCTestCase {
    /// Call at the start of a wall test that changes a display setting (what the photo frame
    /// shows, the night's hours, the idle minutes). Those are the device's own, kept in the
    /// simulator's defaults, so they outlive the test and the launch: after this test, pass
    /// or fail, the app is launched once more to forget them (`-debugForgetDisplay YES`),
    /// and the next test starts from a new install's settings.
    @MainActor
    func forgetDisplaySettingsAfterwards() {
        addTeardownBlock { @MainActor in
            let app = XCUIApplication.porchlight()
            app.launchArguments = ["-sampleHousehold", "-debugForgetDisplay", "YES"]
            app.launch()
            _ = app.windows.firstMatch.waitForExistence(timeout: 30)
            app.terminate()
        }
    }
}

extension XCUIApplication {
    /// The app under test, with its logging turned off.
    ///
    /// XCTest's automation support runs inside the app and logs every accessibility
    /// attribute it fetches. On the wall's big screens (Settings, Glow) a test's queries
    /// make it log tens of thousands of lines in seconds; the system then quarantines the
    /// app's logging, and XCTest's own fault path crashes the app (`EXC_BAD_ACCESS` in
    /// `runtime_issue_os_log_fault_callback` under `XCElementSnapshot elementType`), which
    /// the test reports as a lost connection. The app's logs are never read by the tests.
    ///
    /// Toasts stay up for 30 seconds instead of 5: after a tap XCTest waits for the app to
    /// settle, which on a busy simulator can take longer than a toast lasts, so a test
    /// looking for the toast or its Undo would find it already gone.
    ///
    /// On an iPad the device is turned to landscape first, as the wall hangs. A new simulator
    /// boots in portrait, and on iPadOS 27 the app, which runs landscape only, then draws
    /// sideways while the keyboard comes up in portrait across it, and XCTest reports frames
    /// and swipes in the device's portrait coordinates. On iOS 17 the whole screen turned
    /// with the app, so the device's orientation did not matter there.
    static func porchlight() -> XCUIApplication {
        if UIDevice.current.userInterfaceIdiom == .pad, !XCUIDevice.shared.orientation.isLandscape {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        let app = XCUIApplication()
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launchEnvironment["PORCHLIGHT_TOAST_SECONDS"] = "30"
        app.launchEnvironment["PORCHLIGHT_NOW"] = UITestClock.midweek
        // The look the test turned the simulator to, said to the app as well: on iOS 27
        // simulators the simulator's look doesn't reach it (`DebugLaunch.look`).
        app.launchEnvironment["PORCHLIGHT_LOOK"] = XCUIDevice.shared.appearance == .dark ? "dark" : "light"
        return app
    }
}
