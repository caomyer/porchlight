import SwiftUI

/// One line of news at the top of Today, in plain words with at most one fix:
/// care that was never logged, or "nothing else for you today".
struct StatusBanner: View {
    enum Tone {
        /// Needs a look.
        case warn
        /// Calm good news.
        case good
        /// Just so you know.
        case info

        var background: Color {
            switch self {
            case .warn: Theme.warnSoft
            case .good: Theme.goodSoft
            case .info: Theme.surface2
            }
        }

        var ink: Color {
            switch self {
            case .warn: Theme.warnInk
            case .good: Theme.goodInk
            case .info: Theme.ink
            }
        }
    }

    let tone: Tone
    let emoji: String
    let title: String
    var detail: String?
    /// The one fix, e.g. "Log it". The whole banner is the button.
    var action: (title: String, run: () -> Void)?
    /// "Not now": the banner stays away once dismissed.
    var onDismiss: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            if let action {
                Button(action: action.run) { content(actionTitle: action.title) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ". "))
                    .accessibilityHint(action.title)
                    .accessibilityAddTraits(.isButton)
            } else {
                content(actionTitle: nil)
                    .accessibilityElement(children: .combine)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tone.ink.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not now")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, onDismiss == nil ? 12 : 0)
        .padding(.vertical, onDismiss == nil ? 10 : 0)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(tone.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func content(actionTitle: String?) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            Text(emoji).phoneFont(.body, 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .phoneFont(.body, 13, weight: 700, relativeTo: .subheadline)
                if let detail {
                    Text(detail)
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .opacity(0.85)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                Text(actionTitle)
                    .phoneFont(.body, 13, weight: 800, relativeTo: .subheadline)
                    .foregroundStyle(Theme.accent)
            }
        }
        .foregroundStyle(tone.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, onDismiss == nil ? 0 : 10)
        .contentShape(Rectangle())
    }
}
