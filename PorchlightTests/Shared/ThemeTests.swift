import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The theme's two looks: the wall's light values stay exactly as they were, and a wash
/// mixes in the look it is asked for, whatever the device's own setting.
@Suite("Theme")
struct ThemeTests {
    private func hex(_ color: Color) -> UInt32 {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(cgColor: color.resolve(in: environment).cgColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded())
    }

    @Test("A light wash is the same mix as before the night look")
    func lightWash() {
        // 30% of the accent (D9653B) over paper surface (FFFCF6).
        #expect(hex(Theme.accent.wash(0.3)) == 0xF4CFBE)
        #expect(hex(PersonColor.blue.color.wash(0.15)) == 0xE4E9EC)
    }

    @Test("A dark wash mixes the night values")
    func darkWash() {
        // Night surface 2A2420 under night accent E67A50 at 50%.
        #expect(hex(Theme.accent.wash(0.5, in: .dark)) == 0x884F38)
    }
}
