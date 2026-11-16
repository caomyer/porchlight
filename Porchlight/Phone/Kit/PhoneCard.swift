import SwiftUI

// Cards and buttons at phone size, in the wall's paper and accent.

extension View {
    /// Paper behind the status bar, so a tab's content scrolls under it instead of
    /// through the clock.
    func paperUnderStatusBar() -> some View {
        overlay(alignment: .top) {
            Theme.background
                .frame(height: 0)
                .ignoresSafeArea(edges: .top)
        }
    }

    /// A paper card: 14 pt inside, 20 pt corners, a soft shadow. A `tint` (a companion's
    /// color) warms it from the top, like the pet card on the wall.
    func phoneCard(tint: Color? = nil) -> some View {
        modifier(PhoneCardStyle(tint: tint))
    }
}

private struct PhoneCardStyle: ViewModifier {
    var tint: Color?
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(Theme.surface)
                    if let tint {
                        shape.fill(LinearGradient(
                            stops: [.init(color: tint.wash(scheme == .dark ? 0.16 : 0.26, over: Theme.surface, in: scheme), location: 0),
                                    .init(color: Theme.surface, location: 0.6)],
                            startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)
                        ))
                    }
                }
                .shadow(color: Color(hex: 0x3C_2814).opacity(0.06), radius: 1, x: 0, y: 1)
            }
            .foregroundStyle(Theme.ink)
    }
}

/// The phone's buttons: a full-width capsule, at least 44 pt tall, that stacks its
/// label onto more lines rather than shrinking it.
struct PhoneButtonStyle: ButtonStyle {
    enum Kind {
        /// The one thing to do: "I walked Yo-Yo".
        case primary
        /// A quieter second choice.
        case ghost
    }

    var kind: Kind = .primary
    /// For a card in a grid of two.
    var small = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .phoneFont(.body, small ? 13.5 : 16, weight: 800)
            .multilineTextAlignment(.center)
            .foregroundStyle(kind == .primary ? Theme.accentInk : Theme.ink)
            .padding(.horizontal, small ? 12 : 16)
            .padding(.vertical, small ? 10 : 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(kind == .primary ? Theme.accent : Theme.surface2, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// A finished state shaped like the button it replaces ("✓ Logged · +2 stars"). Not a
/// button: there is nothing left to tap.
struct DoneCapsule: View {
    let text: String
    var small = false

    var body: some View {
        Text(text)
            .phoneFont(.body, small ? 13.5 : 16, weight: 800)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, small ? 12 : 16)
            .padding(.vertical, small ? 10 : 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.good, in: Capsule())
    }
}

/// A small muted tag: "+2", "🔥 3-day streak".
struct PhoneTag: View {
    let text: String

    var body: some View {
        Text(text)
            .phoneFont(.body, 11.5, weight: 800, relativeTo: .caption)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.surface2, in: Capsule())
            .fixedSize()
    }
}

/// A card's title row: serif title, muted count on the right.
struct PhoneCardHeader: View {
    let title: String
    var meta: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText
                Spacer(minLength: 8)
                metaText
            }
            VStack(alignment: .leading, spacing: 2) {
                titleText
                metaText
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var titleText: some View {
        Text(title).phoneFont(.display, 17, weight: 600, relativeTo: .headline)
    }

    @ViewBuilder
    private var metaText: some View {
        if let meta {
            Text(meta)
                .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
        }
    }
}
