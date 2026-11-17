import Foundation
import Testing
@testable import Porchlight

/// Which build a device runs, as Settings and You show it.
@Suite("App version")
struct AppVersionTests {
    @Test("The version and the commit's build number, as one quiet line")
    func text() {
        #expect(AppVersion.text(["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "20261117.061840"]) == "Porchlight 0.1.0 (20261117.061840)")
        #expect(AppVersion.text([:]) == "Porchlight ? (?)")
    }

    @Test("The app's own bundle carries the marketing version from project.yml")
    func bundled() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["CFBundleShortVersionString"] as? String == "0.1.0")
        #expect(info["CFBundleVersion"] as? String != nil)
    }
}
