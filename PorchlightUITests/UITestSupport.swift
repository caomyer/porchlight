import XCTest

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
    static func porchlight() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launchEnvironment["PORCHLIGHT_TOAST_SECONDS"] = "30"
        return app
    }
}
