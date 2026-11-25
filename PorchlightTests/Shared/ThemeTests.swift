import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The theme's two looks: the wall's light values stay exactly as they were, and a wash
/// mixes in the look it is asked for, whatever the device's own setting.
@Suite("Theme")
struct ThemeTests {
    private func hex(_ color: Color, in scheme: ColorScheme = .light) -> UInt32 {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(cgColor: color.resolve(in: environment).cgColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded())
    }

    @Test("A light wash is the same mix as before the night look")
    func lightWash() {
        // 30% of the accent (D9653B) over paper surface (FFFCF6).
        #expect(hex(Theme.accent.wash(0.3)) == 0xF4CFBE)
        #expect(hex(PersonColor.blue.color.wash(0.2)) == 0xDBE2E8)
    }

    @Test("A dark wash mixes the night values")
    func darkWash() {
        // Night surface 2A2420 under night accent E67A50 at 50%.
        #expect(hex(Theme.accent.wash(0.5, in: .dark)) == 0x884F38)
    }

    @Test("A wash with no look of its own follows the look it is drawn in: the night mix at night, the light mix by day")
    func washFollowsTheLook() {
        for color in [Theme.ink, Theme.accent, PersonColor.blue.color, PersonColor.coral.color] {
            for opacity in [0.12, 0.16, 0.3] {
                #expect(hex(color.wash(opacity), in: .dark) == hex(color.wash(opacity, in: .dark), in: .dark), "night: \(opacity)")
                #expect(hex(color.wash(opacity), in: .light) == hex(color.wash(opacity, in: .light)), "day: \(opacity)")
            }
        }
        // The chore editor's chosen chip: ink at 16% over the night surface is dark, not the
        // light look's near white.
        let chip = hex(Theme.ink.wash(0.16), in: .dark)
        let lightness = (Double(chip >> 16 & 0xFF) * 0.2126 + Double(chip >> 8 & 0xFF) * 0.7152 + Double(chip & 0xFF) * 0.0722) / 255
        #expect(lightness < 0.4, "a chosen chip at night is dark: \(lightness)")
    }
}
