import SwiftUI
import UIKit

/// "Sunday Paper" design tokens. Every color, font and radius in the app comes from here.
/// This file stands alone (SwiftUI and UIKit only), so the widget extension draws with the
/// same values; styles and views built on the app's data live in Theme.swift.
///
/// Colors have a night value too, the warm dark palette the phone shows when the system
/// is in dark mode. The wall forces the light look, so it only ever sees the first value.
enum Theme {
    // MARK: Colors
    static let background = Color(light: 0xF5EFE4, dark: 0x1E1A17)
    static let surface = Color(light: 0xFFFCF6, dark: 0x2A2420)
    static let surface2 = Color(light: 0xF0E8DA, dark: 0x352E29)
    static let rail = Color(light: 0xEDE4D4, dark: 0x24201C)
    static let ink = Color(light: 0x2A2420, dark: 0xF2EAE0)
    static let muted = Color(light: 0x867A6E, dark: 0xA89A8C)
    static let line = Color(light: 0xE6DCCB, dark: 0x3B332D)
    static let accent = Color(light: 0xD9653B, dark: 0xE67A50)
    static let accentInk = Color.white
    static let good = Color(hex: 0x5B9F72)
    /// Something paused that needs a look, never an error: sync waiting on iCloud.
    static let warn = Color(light: 0xB7791F, dark: 0xD9A441)
    /// A selected pill or a claimed row: the accent laid softly on paper.
    static let accentSoft = Color(light: 0xFDF1EA, dark: 0x4A2E22)
    /// Done things: a filled care slot, an all-clear banner.
    static let goodSoft = Color(light: 0xE3EFE2, dark: 0x263A2D)
    static let goodInk = Color(light: 0x2F6343, dark: 0xA9D6B6)
    /// Something that needs a look, like care that was never logged.
    static let warnSoft = Color(light: 0xF6E7C8, dark: 0x3D3122)
    static let warnInk = Color(light: 0x7A5214, dark: 0xE8C27E)
    /// The one color for what can't be undone: removing someone's devices.
    static let danger = Color(light: 0xB54A3A, dark: 0xD4705E)
    /// The undo toast floats above both looks, so it stays dark in both.
    static let toast = Color(light: 0x2A2420, dark: 0x3B332D)
    static let toastInk = Color(hex: 0xFFFCF6)
    static let toastMuted = Color(hex: 0xD8CDBF)
    static let toastAction = Color(hex: 0xF2B59A)

    // MARK: Shape
    static let radius: CGFloat = 20
    static let smallRadius: CGFloat = 12
    static let railWidth: CGFloat = 84
    static let pagePadding: CGFloat = 24
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A color that follows the light or dark look it is drawn in.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typography

/// The bundled variable fonts. We set the weight and optical-size axes
/// directly so every size renders exactly like the design.
enum Typeface {
    case display  // Fraunces
    case body     // DM Sans
    case hand     // Caveat

    fileprivate var postScriptName: String {
        switch self {
        case .display: "Fraunces-Regular"
        case .body: "DMSans-9ptRegular"
        case .hand: "Caveat-Regular"
        }
    }

    fileprivate var opticalSizeRange: ClosedRange<CGFloat>? {
        switch self {
        case .display: 9...144
        case .body: 9...40
        case .hand: nil
        }
    }
}

extension Font {
    /// Fraunces, used for titles and big numbers.
    static func display(_ size: CGFloat, weight: CGFloat = 600) -> Font {
        .custom(.display, size: size, weight: weight)
    }

    /// DM Sans, used for everything else.
    static func body(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        .custom(.body, size: size, weight: weight)
    }

    /// Caveat, used for handwriting-style captions.
    static func hand(_ size: CGFloat, weight: CGFloat = 600) -> Font {
        .custom(.hand, size: size, weight: weight)
    }

    static func custom(_ face: Typeface, size: CGFloat, weight: CGFloat) -> Font {
        Font(UIFont.variable(face, size: size, weight: weight) as CTFont)
    }
}

extension UIFont {
    private static let weightAxis = 0x7767_6874  // 'wght'
    private static let opticalSizeAxis = 0x6F70_737A  // 'opsz'

    static func variable(_ face: Typeface, size: CGFloat, weight: CGFloat) -> UIFont {
        var axes: [Int: CGFloat] = [weightAxis: weight]
        if let range = face.opticalSizeRange {
            axes[opticalSizeAxis] = min(max(size, range.lowerBound), range.upperBound)
        }
        let descriptor = UIFontDescriptor(name: face.postScriptName, size: size)
            .addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes])
        return UIFont(descriptor: descriptor, size: size)
    }
}
