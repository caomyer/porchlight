import SwiftUI

/// Household details, people, and this display's behavior.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(DisplaySettings.keepAwakeKey) private var keepAwake = true

    @State private var householdName = ""
    @State private var drafts: [Int64: PersonDraft] = [:]
    @State private var newPerson = PersonDraft(name: "", color: .blue)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings").font(.display(40))

                section("Household") {
                    HStack(spacing: 12) {
                        TextField("Household name", text: $householdName)
                            .font(.body(18, weight: 600))
                            .fieldStyle()
                            .onSubmit { _ = model.renameHousehold(to: householdName) }
                        Button("Save") { _ = model.renameHousehold(to: householdName) }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(householdName == model.household?.name)
                    }
                    .frame(maxWidth: 560)
                }

                section("People") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.people) { person in
                            PersonEditorRow(
                                name: binding(for: person).name,
                                color: binding(for: person).color,
                                canRemove: model.people.count > 1,
                                onRemove: { _ = model.deletePerson(person) }
                            )
                            .onChange(of: drafts[person.id ?? -1]) { _, draft in
                                guard let draft, draft != PersonDraft(name: person.name, color: person.color),
                                      !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                _ = model.updatePerson(person, name: draft.name, color: draft.color)
                            }
                        }
                        HStack(spacing: 12) {
                            PersonEditorRow(name: $newPerson.name, color: $newPerson.color, canRemove: false, onRemove: {})
                            Button {
                                if model.addPerson(newPerson) {
                                    newPerson = PersonDraft(name: "", color: .suggested(for: model.people.count))
                                }
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(newPerson.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                }

                section("This display") {
                    Toggle(isOn: $keepAwake) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep the screen on")
                                .font(.body(17, weight: 600))
                            Text("The iPad never sleeps while Porchlight is open. Use Guided Access (triple-click the Home button) to lock it to this app.")
                                .font(.body(14))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.good)
                    .card(padding: 16)
                    .frame(maxWidth: 720)
                }

                if let error = model.lastError {
                    Text(error)
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(Theme.pagePadding + 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            householdName = model.household?.name ?? ""
            newPerson.color = .suggested(for: model.people.count)
        }
    }

    private func binding(for person: Person) -> Binding<PersonDraft> {
        let id = person.id ?? -1
        return Binding(
            get: { drafts[id] ?? PersonDraft(name: person.name, color: person.color) },
            set: { drafts[id] = $0 }
        )
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content()
        }
    }
}
