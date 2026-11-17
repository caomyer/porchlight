import SwiftUI
import UIKit

/// Display preferences that belong to this device, not the household.
enum DisplaySettings {
    static let keepAwakeKey = "display.keepAwake"
    /// Minutes without a touch before the wall switches to Ambient mode (0 = never).
    static let ambientMinutesKey = "display.ambientMinutes"
    static let defaultAmbientMinutes = 10

    /// How many seconds one of those minutes lasts: 60, except in a Debug build launched with
    /// `-debugIdleSecondsPerMinute N`, so a UI test of Ambient takes seconds, not minutes.
    static var secondsPerIdleMinute: Double {
        #if DEBUG
        let seconds = UserDefaults.standard.double(forKey: "debugIdleSecondsPerMinute")
        if seconds > 0 { return seconds }
        #endif
        return 60
    }
}

/// Wall-display behavior: never sleep while Porchlight is open, and hide the
/// status bar and home indicator. Pair with Guided Access to lock the iPad to the app.
private struct KioskMode: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DisplaySettings.keepAwakeKey) private var keepAwake = true

    func body(content: Content) -> some View {
        content
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onAppear(perform: apply)
            .onChange(of: scenePhase) { apply() }
            .onChange(of: keepAwake) { apply() }
    }

    private func apply() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && scenePhase == .active
    }
}

extension View {
    func kioskMode() -> some View {
        modifier(KioskMode())
    }
}
