import SwiftUI

// Small building blocks shared by the Chores, Lists and Settings screens.

/// The page title row: big title, a muted subtitle, and actions on the right.
struct HomeHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 18) {
            Text(title)
                .font(.display(40))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.body(15))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 6) { trailing() }
                .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 6 }
        }
        .frame(minHeight: 56, alignment: .bottom)
    }
}

/// A small outlined capsule button in a page header ("This week", "+ New chore").
struct HeaderChip: View {
    let title: String
    var symbol: String? = nil
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                }
                Text(title).font(.body(13, weight: 600))
            }
            .foregroundStyle(isSelected ? Theme.surface : Theme.ink)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(isSelected ? Theme.ink : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Theme.ink : Theme.line))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The square check box used on chores and list items.
struct CheckBox: View {
    var isOn: Bool
    var color: Color
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 9
    var lineWidth: CGFloat = 2.5
    /// The border color when unchecked; defaults to the color softened toward muted.
    var border: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isOn ? color : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isOn ? color : (border ?? color.wash(0.7, over: Theme.muted)), lineWidth: lineWidth)
            }
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A selectable capsule in an editor ("Every day", a person, "Anyone").
struct ChoiceChip<Leading: View>: View {
    let title: String
    var isSelected: Bool
    var tint: Color = Theme.ink
    @ViewBuilder var leading: () -> Leading
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading()
                Text(title).font(.body(15, weight: 700))
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, Leading.self == EmptyView.self ? 16 : 6)
            .padding(.trailing, 16)
            .frame(height: 42)
            .background(isSelected ? tint.wash(0.16) : Theme.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? tint : .clear, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension ChoiceChip where Leading == EmptyView {
    init(title: String, isSelected: Bool, tint: Color = Theme.ink, action: @escaping () -> Void) {
        self.init(title: title, isSelected: isSelected, tint: tint, leading: { EmptyView() }, action: action)
    }
}

/// A big square field holding one emoji.
struct EmojiField: View {
    @Binding var emoji: String
    var placeholder = "🙂"

    var body: some View {
        TextField("", text: Binding(
            get: { emoji },
            set: { emoji = HomeText.emoji(String($0.suffix(1))) ?? "" }
        ))
        .font(.system(size: 30))
        .multilineTextAlignment(.center)
        .frame(width: 60, height: 54)
        // A faded hint, so an empty field doesn't look like a chosen emoji.
        .background {
            if emoji.isEmpty {
                Text(placeholder).font(.system(size: 30)).opacity(0.3).allowsHitTesting(false)
            }
        }
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .accessibilityLabel("Emoji")
    }
}

/// A "- 3 +" control for small whole numbers.
struct CountStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1
    var suffix: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            button("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
            HStack(spacing: 4) {
                Text("\(value)").font(.display(22)).monospacedDigit()
                if let suffix {
                    Text(suffix).font(.body(14, weight: 700)).foregroundStyle(Theme.muted)
                }
            }
            .frame(minWidth: 56)
            button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
        }
        .padding(4)
        .background(Theme.surface2, in: Capsule())
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(symbol == "plus" ? "More" : "Fewer")
    }
}

/// A labeled group inside an editor sheet.
struct EditorRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label)
            content()
        }
    }
}

/// A red-orange line under a form explaining what went wrong.
struct ErrorLine: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.accent)
        }
    }
}

/// The star used for chore totals and rewards.
struct StarIcon: View {
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: size * 0.9, weight: .semibold))
            .foregroundStyle(PersonColor.ochre.color)
            .accessibilityHidden(true)
    }
}

// MARK: - Wall sheets

extension View {
    /// Presents `WallSheet` over the whole wall (rail included) while `item` is set.
    /// The dim fades in rather than sliding up like a system sheet.
    func wallSheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        width: CGFloat = 640,
        @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        wallCover(item: item) { value in
            FadingWallSheet(width: width, onDismiss: { withoutAnimation { item.wrappedValue = nil } }) {
                content(value)
            }
        }
    }
}

/// Runs a state change with animations turned off, so a wall layer appears in place.
@MainActor
func withoutAnimation(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
}

/// Lets sheet content close itself with the same fade it opened with.
struct CloseWallSheetAction {
    let close: @MainActor () -> Void
    @MainActor func callAsFunction() { close() }
}

extension EnvironmentValues {
    @Entry var closeWallSheet = CloseWallSheetAction(close: {})
}

private struct FadingWallSheet<Content: View>: View {
    let width: CGFloat
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var isVisible = false

    var body: some View {
        WallSheet(width: width, onClose: close) {
            content()
                .environment(\.closeWallSheet, CloseWallSheetAction(close: close))
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.985)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) { isVisible = true }
        }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.15)) {
            isVisible = false
        } completion: {
            onDismiss()
        }
    }
}
