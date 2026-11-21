import SwiftUI
import UIKit

/// "Which one is you?": picks the person this phone belongs to, once. Everything logged
/// from the phone is credited to them, so it never has to ask who did it.
///
/// People without a phone of their own come first; people who have one are dimmed but can
/// still be picked (one person, two phones); "I'm new here" adds a person (journey A4).
struct WhoAreYouView: View {
    /// The person already picked, when changing it from the You sheet.
    var current: Person.ID?
    /// Where this step sits in a longer flow, as dots.
    var progress: (count: Int, index: Int)?
    let onPick: (Person.ID) -> Void
    /// Adds the new person and continues as them; by default, into the current household.
    var onAddMe: ((PersonDraft) throws -> Void)?

    @Environment(AppModel.self) private var model
    @State private var choice: Choice?
    @State private var newMe = PersonDraft(name: "", color: .blue)
    @State private var failure: String?
    @FocusState private var nameFocused: Bool

    private enum Choice: Hashable {
        case person(Person.ID)
        case new
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let progress {
                    StepDots(count: progress.count, index: progress.index)
                }
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
                    ForEach(ordered, id: \.person.id) { entry in
                        personRow(entry.person, device: entry.device)
                    }
                    newRow
                }
                if let failure {
                    Text(failure)
                        .phoneFont(.body, 13, weight: 600)
                        .foregroundStyle(Theme.accent)
                }
                Button(continueTitle, action: finish)
                    .buttonStyle(PhoneButtonStyle())
                    .disabled(!canContinue)
                    .padding(.top, 8)
                    .accessibilityIdentifier("continue-as")
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 16)
            .padding(.top, progress == nil ? 48 : 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Scrolled text never shows under the clock: these screens stand alone, outside
        // the tabs, so they keep their content inside the safe area as well as painting
        // paper behind the status bar.
        .clipped()
        .paperUnderStatusBar()
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            choice = choice ?? current.map(Choice.person)
            newMe.color = .suggested(for: model.people.count)
        }
    }

    /// People without a phone of their own first, then those with one, each in the
    /// household's order.
    private var ordered: [(person: Person, device: Device?)] {
        let entries = model.people.map { ($0, model.snapshot.devices(of: $0.id).first) }
        return entries.filter { $0.1 == nil } + entries.filter { $0.1 != nil }
    }

    private var picked: Person? {
        guard case let .person(id)? = choice else { return nil }
        return model.people.person(id)
    }

    private var newName: String { newMe.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canContinue: Bool {
        switch choice {
        case .person?: picked != nil
        case .new?: !newName.isEmpty
        case nil: false
        }
    }

    private var continueTitle: String {
        switch choice {
        case .person?: picked.map { "Continue as \($0.name)" } ?? "Continue"
        case .new?: newName.isEmpty ? "Continue" : "Continue as \(newName)"
        case nil: "Continue"
        }
    }

    private func finish() {
        switch choice {
        case .person?:
            if let picked { onPick(picked.id) }
        case .new?:
            do {
                if let onAddMe {
                    try onAddMe(newMe)
                } else if let household = model.household {
                    onPick(try model.database.addPerson(newMe, to: household.id).id)
                }
            } catch {
                failure = error.userMessage
            }
        case nil:
            break
        }
    }

    private func personRow(_ person: Person, device: Device?) -> some View {
        let isOn = choice == .person(person.id)
        return Button { choice = .person(person.id) } label: {
            ChoiceRow(isOn: isOn, title: person.name, detail: device.map { "On \($0.name)" } ?? "Hasn't joined yet") {
                PersonAvatar(person)
            }
            .opacity(device != nil && !isOn ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("who-\(person.name)")
    }

    private var newRow: some View {
        let isOn = choice == .new
        return VStack(spacing: 0) {
            Button {
                // Picking it shows the name field, which takes the keyboard once it is there
                // (below). Asking for the focus here, in the same update that adds the field,
                // asks before the field exists.
                if isOn { nameFocused = true } else { choice = .new }
            } label: {
                ChoiceRow(isOn: isOn, title: "I'm new here", detail: "Add yourself with a name and color") {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface2, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("who-new")
            if isOn {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Your name", text: $newMe.name)
                        .phoneFont(.body, 15.5, weight: 600)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                        .accessibilityIdentifier("new-name")
                        // Once the field is on screen, a turn of the main loop after it was added.
                        .task { nameFocused = true }
                    PhoneColorChoice(selection: $newMe.color)
                }
                .padding(.top, 10)
            }
        }
    }
}

/// One choice in a list of choices: a leading mark, a title and a line under it, with the
/// accent border when it is the one picked.
struct ChoiceRow<Leading: View>: View {
    let isOn: Bool
    let title: String
    var detail: String?
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 3) {
                Text(title).phoneFont(.body, 15.5, weight: 700)
                if let detail {
                    Text(detail)
                        .phoneFont(.body, 12.5, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
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
}

/// The person colors at phone size: each swatch is a 44 pt target.
struct PhoneColorChoice: View {
    @Binding var selection: PersonColor

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PersonColor.allCases, id: \.self) { option in
                Button { selection = option } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 30, height: 30)
                        .padding(3)
                        .overlay(Circle().strokeBorder(selection == option ? Theme.ink : .clear, lineWidth: 2))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// How the phone names itself in sentences: "this iPhone". Only words; what the
/// device does is decided by its role, never by its kind.
enum DeviceWords {
    @MainActor static var this: String { UIDevice.current.model }
}
