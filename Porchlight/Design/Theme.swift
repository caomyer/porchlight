import SwiftUI
import UIKit

// Styles built on the app's own types. The tokens they use are in ThemeTokens.swift,
// which the widget extension shares.

extension PersonColor {
    var color: Color { Color(hex: hex) }

    /// 0xRRGGBB, also what the widgets' summary carries.
    var hex: UInt32 {
        switch self {
        case .blue: 0x4C7BB0
        case .coral: 0xDD7558
        case .sage: 0x5B9F72
        case .ochre: 0xC2933A
        case .plum: 0x8A6AA8
        case .teal: 0x3E8C8C
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
