import SwiftUI
import UIKit

/// "Which one is you?": picks the person this phone belongs to, once. Everything logged
/// from the phone is credited to them, so it never has to ask who did it.
struct WhoAreYouView: View {
    /// The person already picked, when changing it from the You sheet.
    var current: Person.ID?
    let onPick: (Person.ID) -> Void

    @Environment(AppModel.self) private var model
    @State private var choice: Person.ID?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    Text("Which one is you?")
                        .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("What you log from this \(DeviceWords.this) is credited to you.")
                        .phoneFont(.body, 14.5, weight: 500)
                        .foregroundStyle(Theme.muted)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                VStack(spacing: 8) {
                    ForEach(model.people) { person in
                        choiceRow(person)
                    }
                }
                Button(continueTitle) {
                    if let picked { onPick(picked.id) }
                }
                .buttonStyle(PhoneButtonStyle())
                .disabled(picked == nil)
                .padding(.top, 8)
                .accessibilityIdentifier("continue-as")
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { choice = choice ?? current }
    }

    private var picked: Person? { choice.flatMap(model.people.person) }

    private var continueTitle: String {
        picked.map { "Continue as \($0.name)" } ?? "Continue"
    }

    private func choiceRow(_ person: Person) -> some View {
        let isOn = choice == person.id
        return Button { choice = person.id } label: {
            HStack(spacing: 12) {
                PersonAvatar(person)
                Text(person.name)
                    .phoneFont(.body, 15.5, weight: 700)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(isOn ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isOn ? Theme.accent : Theme.line, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("who-\(person.name)")
    }
}

/// How the phone names itself in sentences: "this iPhone". Only words; what the
/// device does is decided by its role, never by its kind.
enum DeviceWords {
    @MainActor static var this: String { UIDevice.current.model }
}
