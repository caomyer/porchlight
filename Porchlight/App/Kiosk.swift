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

/// When the wall goes to Ambient: after so many minutes without a touch, 0 for never, and
/// never while Ambient is already showing or Settings is open. The wall asks this of the
/// time of its last touch; it holds no clock of its own, so the rule is tested with dates
/// handed in (`IdleRuleTests`), not by waiting.
struct IdleRule: Equatable {
    /// Minutes without a touch before Ambient (0 = never).
    var minutes: Int
    /// How long one of those minutes lasts (`DisplaySettings.secondsPerIdleMinute`).
    var secondsPerMinute: Double = 60

    /// How long without a touch, in seconds; nil when the wall never goes idle.
    var timeout: TimeInterval? {
        minutes > 0 ? Double(minutes) * secondsPerMinute : nil
    }

    /// Whether the wall should go to Ambient now.
    func isIdle(lastTouch: Date, now: Date, showingAmbient: Bool, inSettings: Bool) -> Bool {
        guard let timeout, !showingAmbient, !inSettings else { return false }
        return now.timeIntervalSince(lastTouch) >= timeout
    }

    /// How often the wall asks: four times a minute, so Ambient comes within a quarter of a
    /// minute of its time.
    var checkEvery: TimeInterval { secondsPerMinute / 4 }
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
