import SwiftUI
import UIKit

/// "Sunday Paper" design tokens. Every color, font and radius in the app comes from here.
enum Theme {
    // MARK: Colors
    static let background = Color(hex: 0xF5EFE4)
    static let surface = Color(hex: 0xFFFCF6)
    static let surface2 = Color(hex: 0xF0E8DA)
    static let rail = Color(hex: 0xEDE4D4)
    static let ink = Color(hex: 0x2A2420)
    static let muted = Color(hex: 0x867A6E)
    static let line = Color(hex: 0xE6DCCB)
    static let accent = Color(hex: 0xD9653B)
    static let accentInk = Color.white
    static let good = Color(hex: 0x5B9F72)
    /// Something paused that needs a look, never an error: sync waiting on iCloud.
    static let warn = Color(hex: 0xB7791F)
    static let warnSoft = Color(hex: 0xF6E7C8)
    static let warnInk = Color(hex: 0x7A5214)

    // MARK: Shape
    static let radius: CGFloat = 20
    static let smallRadius: CGFloat = 12
    static let railWidth: CGFloat = 84
    static let pagePadding: CGFloat = 24
}

extension PersonColor {
    var color: Color {
        switch self {
        case .blue: Color(hex: 0x4C7BB0)
        case .coral: Color(hex: 0xDD7558)
        case .sage: Color(hex: 0x5B9F72)
        case .ochre: Color(hex: 0xC2933A)
        case .plum: Color(hex: 0x8A6AA8)
        case .teal: Color(hex: 0x3E8C8C)
        }
    }

    var label: String {
        switch self {
        case .blue: "Blue"
        case .coral: "Coral"
        case .sage: "Sage"
        case .ochre: "Ochre"
        case .plum: "Plum"
        case .teal: "Teal"
        }
    }
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

// MARK: - Reusable styles

struct CardStyle: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SurfaceShape(cornerRadius: Theme.radius))
    }
}

/// A raised paper surface. The shadow lives on the shape only, so text on top stays crisp.
struct SurfaceShape: View {
    var cornerRadius: CGFloat
    var fill: Color = Theme.surface
    var elevation: CGFloat = 1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .shadow(color: Color(hex: 0x46_2D14).opacity(0.10 * elevation), radius: 12 * elevation, x: 0, y: 6 * elevation)
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body(16, weight: 700))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .background(Theme.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body(15, weight: 700))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.line))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

/// Small uppercase label above a group of controls.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.body(12, weight: 800))
            .tracking(1)
            .foregroundStyle(Theme.muted)
    }
}

/// A person's colored circle with their initial.
struct Avatar: View {
    let initial: String
    let color: Color
    var size: CGFloat = 30
    var ringed = false

    init(person: Person, size: CGFloat = 30, ringed: Bool = false) {
        self.initial = person.initial
        self.color = person.color.color
        self.size = size
        self.ringed = ringed
    }

    init(initial: String, color: Color, size: CGFloat = 30) {
        self.initial = initial
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(initial)
            .font(.body(size * 0.42, weight: 700))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .padding(ringed ? 3 : 0)
            .background(ringed ? Theme.surface : .clear, in: Circle())
            .overlay(ringed ? Circle().stroke(color, lineWidth: 2) : nil)
            .accessibilityHidden(true)
    }
}
