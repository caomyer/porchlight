import SwiftUI

/// One chore on the phone: a box to check for your own, an "I did it" for one anyone
/// can take. A done row is no longer a button; Undo on the toast takes it back.
struct PhoneChoreRow: View {
    enum Kind {
        /// Yours: the whole row checks it off.
        case mine
        /// Anyone's: the capsule on the right takes it.
        case anyone
    }

    let kind: Kind
    let emoji: String?
    let title: String
    /// "this weekend", or "Done 7:05 am" once done.
    let subtitle: String?
    let stars: Int
    let isDone: Bool
    /// Who did it, for a done row anyone could take.
    var doneBy: Person?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if isDone {
            row.accessibilityElement(children: .combine)
        } else {
            switch kind {
            case .mine:
                Button(action: action) { row.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Check off \(title)")
                    .accessibilityValue(subtitle ?? "")
                    .accessibilityAddTraits(.isButton)
            case .anyone:
                row
            }
        }
    }

    private var row: some View {
        let layout = typeSize.isAccessibilitySize && kind == .anyone && !isDone
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            HStack(alignment: .center, spacing: 10) {
                if kind == .mine { ChoreBox(isOn: isDone) }
                VStack(alignment: .leading, spacing: 1) {
                    Text([emoji, title].compactMap { $0 }.joined(separator: " "))
                        .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                        .strikethrough(isDone, color: Theme.muted)
                        .foregroundStyle(isDone ? Theme.muted : Theme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing
        }
        .padding(.vertical, 7)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var trailing: some View {
        switch kind {
        case .mine:
            PhoneTag(text: "+\(stars)")
                .accessibilityLabel("\(stars) \(stars == 1 ? "star" : "stars")")
        case .anyone:
            if isDone {
                PersonAvatar(doneBy, size: .small)
            } else {
                Button(action: action) {
                    Text("I did it")
                        .phoneFont(.body, 12, weight: 800, relativeTo: .caption)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Check off \(title) as yours")
                .accessibilityHint("Earns \(stars) \(stars == 1 ? "star" : "stars")")
            }
        }
    }
}

/// The rounded box of a chore of yours.
private struct ChoreBox: View {
    let isOn: Bool
    @PhoneMetric private var side: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(isOn ? Theme.good : Theme.accent, lineWidth: 2)
            .background(isOn ? Theme.good : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.5, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
