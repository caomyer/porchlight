import SwiftUI

/// Two or three views of one tab ("Diary · Dishes"), in the paper's colors: the chosen one
/// lifts onto the card color. Each segment is at least 44 pt tall and its words grow with
/// Dynamic Type.
struct PhoneSegments<Choice: Hashable>: View {
    let choices: [Choice]
    @Binding var selection: Choice
    let title: (Choice) -> String

    init(choices: [Choice], selection: Binding<Choice>, title: @escaping (Choice) -> String) {
        self.choices = choices
        _selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(choices, id: \.self) { choice in
                let isOn = choice == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = choice }
                } label: {
                    Text(title(choice))
                        .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
                        .foregroundStyle(isOn ? Theme.ink : Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Theme.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("segment-\(title(choice))")
            }
        }
        .padding(3)
        .frame(minHeight: 44)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
