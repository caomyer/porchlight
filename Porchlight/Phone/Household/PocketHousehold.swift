import SwiftUI

// Household setup from the phone (journeys F1 and F2): You › Household reaches everything the
// wall can set up, through the wall's own editors laid out for a compact width. Pages push
// inside the You sheet, so an editor never stacks a second sheet on it.

/// The hub (`f1hub`): the household's name, its people, then companions, chores, rewards,
/// lists and the food diary, each with a word on what's there.
struct PocketHouseholdHub: View {
    @Environment(AppModel.self) private var model
    @Environment(CompanionStore.self) private var companions
    @Environment(HomeStore.self) private var home
    @Environment(FoodStore.self) private var food
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(SyncController.self) private var sync
    @Environment(DeviceSettings.self) private var device
    @State private var name = ""
    @State private var adding = false
    @State private var newPerson = PersonDraft(name: "", color: .blue)
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(small: model.household?.name, title: "Household")
                PhoneList { nameRow }
                people
                PhoneList {
                    link(.companions, "🐾", "Companions", companionsLine, id: "household-companions")
                    RowDivider()
                    link(.chores, "☑️", "Chores", choresLine, id: "household-chores")
                    RowDivider()
                    link(.rewards, "🎁", "Rewards", rewardsLine, id: "household-rewards")
                    RowDivider()
                    link(.lists, "📝", "Lists", listsLine, id: "household-lists")
                }
                PocketFoodDiaryCard()
                Text("The same editors as the wall. Changes show on every device in the household.")
                    .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Household")
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        .onAppear {
            name = model.household?.name ?? ""
            newPerson.color = .suggested(for: model.people.count)
            model.lastError = nil
        }
    }

    // MARK: Name

    private var nameRow: some View {
        HStack(spacing: 12) {
            Text("🏡").phoneFont(.body, 20).accessibilityHidden(true)
            TextField("Household name", text: $name)
                .phoneFont(.body, 15, weight: 700, relativeTo: .subheadline)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(rename)
                .accessibilityIdentifier("household-name-field")
            if name != model.household?.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Save", action: rename)
                    .buttonStyle(TakeButtonStyle())
                    .accessibilityIdentifier("save-household-name")
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 50)
    }

    private func rename() {
        guard name != model.household?.name else { return }
        if !model.renameHousehold(to: name) { name = model.household?.name ?? "" }
    }

    // MARK: People

    private var people: some View {
        let roster = FamilyRoster(
            snapshot: model.snapshot, members: sharing.members, thisDevice: model.thisDeviceId,
            thisUserName: sync.userName ?? sharing.userName, onSharedScreen: device.role == .sharedScreen
        )
        return VStack(alignment: .leading, spacing: 4) {
            AdaptiveRow {
                PhoneCardHeader(title: "People", meta: roster.summary)
                Button(adding ? "Cancel" : "+ Add") {
                    adding.toggle()
                    focused = adding
                }
                .buttonStyle(TakeButtonStyle())
                .accessibilityIdentifier("add-person")
            }
            .padding(.top, 10)
            if adding { addPersonFields }
            ForEach(Array(roster.rows.filter { $0.person != nil }.enumerated()), id: \.element.id) { index, row in
                if index > 0 || adding { RowDivider() }
                NavigationLink(value: YouPage.person(row.person!.id)) {
                    HStack(spacing: 8) {
                        PersonStateRow(row: row)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("person-\(row.title)")
            }
            if let error = model.lastError {
                Text(error)
                    .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.accent)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var addPersonFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Their name", text: $newPerson.name)
                .phoneFont(.body, 15.5, weight: 600)
                .textInputAutocapitalization(.words)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(addPerson)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                .accessibilityIdentifier("new-person-name")
            PhoneColorChoice(selection: $newPerson.color)
            Button("Add to the household", action: addPerson)
                .buttonStyle(PhoneButtonStyle())
                .disabled(newPerson.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("save-new-person")
        }
        .padding(.vertical, 8)
    }

    private func addPerson() {
        guard model.addPerson(newPerson) else { return }
        newPerson = PersonDraft(name: "", color: .suggested(for: model.people.count))
        adding = false
    }

    // MARK: The rest

    private func link(_ page: YouPage, _ emoji: String, _ title: String, _ detail: String, id: String) -> some View {
        NavigationLink(value: page) {
            InfoRow(emoji: emoji, title: title, detail: detail, chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var companionsLine: String {
        let names = companions.companions.map(\.name)
        return names.isEmpty ? "Pets and plants, with their routines" : ListFormat.join(names)
    }

    private var choresLine: String {
        let count = home.activeChores.count
        return count == 0 ? "None yet" : count == 1 ? "1 chore" : "\(count) chores"
    }

    private var rewardsLine: String {
        let rewards = home.snapshot.rewards.filter { !$0.archived }.map(\.title)
        return rewards.isEmpty ? "Something to save stars for" : ListFormat.join(Array(rewards.prefix(3)))
    }

    private var listsLine: String {
        let lists = home.snapshot.lists.map(\.title)
        return lists.isEmpty ? "Groceries and to-dos" : ListFormat.join(lists)
    }
}

/// What an empty tab says right after a household starts: what goes here, and one way to
/// set it up, which opens You on the right page.
struct PocketSetUpCard: View {
    let emoji: String
    let title: String
    let detail: String
    let action: String
    let page: YouPage

    @Environment(\.openYou) private var openYou

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveRow(spacing: 12, alignment: .top) {
                Text(emoji).phoneFont(.body, 26).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).phoneFont(.display, 18, weight: 600, relativeTo: .headline)
                    Text(detail)
                        .phoneFont(.body, 13.5, weight: 500, relativeTo: .subheadline)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action) { openYou?(page) }
                .buttonStyle(PhoneButtonStyle(kind: .ghost))
                .accessibilityIdentifier("set-up-\(page)")
        }
        .phoneCard()
    }
}

private extension String {
    /// "Used today" from "used today".
    var capitalizedSentence: String { prefix(1).uppercased() + dropFirst() }
}

/// A page's small line and serif title, as every page under You has.
struct PageTitle: View {
    var small: String?
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let small {
                Text(small)
                    .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
            }
            Text(title)
                .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// The food diary's switch and its meals, as the wall's Settings has them.
private struct PocketFoodDiaryCard: View {
    @Environment(FoodStore.self) private var food

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { food.isEnabled }, set: { food.setEnabled($0) })) {
                HStack(spacing: 12) {
                    Text("🍽️").phoneFont(.body, 20).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Food diary").phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                        Text(food.isEnabled ? "Snap meals here and on the wall" : "Off: the Food tab stays empty")
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.good)
            .frame(minHeight: 44)
            .accessibilityIdentifier("food-diary-switch")
            if food.isEnabled {
                FlowLayout(spacing: 6, lineSpacing: 0) {
                    ForEach(MealSlot.known, id: \.name) { slot in
                        let isOn = food.slots.contains(slot.name)
                        PhoneChoice(title: "\(slot.emoji) \(slot.name)", isOn: isOn) {
                            // At least one meal stays.
                            if !isOn || food.slots.count > 1 { food.setSlot(slot.name, on: !isOn) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - A person (f2person)

/// One person: name and color, their phone (invite, or remove it for the owner), and
/// archiving, which keeps their history and hides them from new things.
struct PocketPersonPage: View {
    let personId: Person.ID

    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(SyncController.self) private var sync
    @Environment(DeviceSettings.self) private var device
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PersonDraft(name: "", color: .blue)
    @State private var loaded = false
    @State private var confirmArchive = false
    @State private var confirmRemove = false
    @State private var failure: String?
    @State private var isRemoving = false

    var body: some View {
        if let person = model.people.first(where: { $0.id == personId }) {
            let row = roster.rows.first { $0.person?.id == personId }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Avatar(initial: initial, color: draft.color.color, size: 52).accessibilityHidden(true)
                        PageTitle(small: model.household?.name, title: draft.name.isEmpty ? person.name : draft.name)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Name", text: $draft.name)
                            .phoneFont(.body, 16, weight: 600)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                            .accessibilityIdentifier("person-name")
                        PhoneColorChoice(selection: $draft.color)
                    }
                    if let row { phoneCard(row, person: person) }
                    if canArchive(person) {
                        Button { confirmArchive = true } label: {
                            InfoRow(emoji: "🗄️", title: "Archive \(person.name)", detail: "Keeps their history, hides them from new things")
                                .padding(.horizontal, 14)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("archive-person")
                    }
                    if let error = failure ?? model.lastError {
                        Text(error)
                            .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                            .foregroundStyle(Theme.accent)
                    }
                    Button("Save") { save(person) }
                        .buttonStyle(PhoneButtonStyle())
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft == PersonDraft(name: person.name, color: person.color))
                        .accessibilityIdentifier("save-person")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(person.name)
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                model.lastError = nil
                draft = PersonDraft(name: person.name, color: person.color)
            }
            .confirmationDialog("Archive \(person.name)?", isPresented: $confirmArchive, titleVisibility: .visible) {
                Button("Archive \(person.name)", role: .destructive) {
                    if model.removePerson(person) { dismiss() }
                }
            } message: {
                Text("Everything \(person.name) logged keeps their name and color. They leave pickers and chores, and their own rewards are put away.")
            }
            .confirmationDialog(row.map { RemoveDevicesWords(row: $0, householdName: householdName).title } ?? "", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { remove(row) }
            } message: {
                Text(row.map { RemoveDevicesWords(row: $0, householdName: householdName).body } ?? "")
            }
        }
    }

    private var householdName: String { model.household?.name ?? "the household" }

    private var initial: String {
        draft.name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    private var roster: FamilyRoster {
        FamilyRoster(
            snapshot: model.snapshot, members: sharing.members, thisDevice: model.thisDeviceId,
            thisUserName: sync.userName ?? sharing.userName, onSharedScreen: device.role == .sharedScreen
        )
    }

    /// Not yourself, and never the last person.
    private func canArchive(_ person: Person) -> Bool {
        person.id != me?.id && model.people.count > 1
    }

    /// "Own phone": their devices and, for the owner, removing them; or an invite.
    private func phoneCard(_ row: FamilyRoster.Row, person: Person) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PhoneCardHeader(title: "Own phone")
                .padding(.top, 10)
            switch row.state {
            case .joined:
                ForEach(row.devices) { phone in
                    InfoRow(emoji: "📱", title: phone.name, detail: FamilyRoster.seen(phone.seenAt, now: .now, calendar: model.calendar).capitalizedSentence)
                }
                if row.removable != nil {
                    RowDivider()
                    Button { confirmRemove = true } label: {
                        InfoRow(emoji: "🚪", title: "Remove \(RemoveDevicesWords(row: row, householdName: householdName).what)", detail: "\(person.name) stays in the household, with their history")
                    }
                    .buttonStyle(.plain)
                    .disabled(isRemoving)
                    .accessibilityIdentifier("remove-devices")
                }
            case .invited:
                InfoRow(emoji: "✉️", title: "Invited", detail: "Hasn't joined yet. Resend from Invite someone, on You.")
            case .noPhone:
                NavigationLink(value: YouPage.invite) {
                    InfoRow(emoji: "📱", title: "Not yet", detail: "Invite when \(person.name) gets one", chevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("invite-person")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func save(_ person: Person) {
        if model.updatePerson(person, name: draft.name, color: draft.color) { dismiss() }
    }

    private func remove(_ row: FamilyRoster.Row?) {
        guard let household = model.household, let participant = row?.removable else { return }
        isRemoving = true
        failure = nil
        Task {
            do {
                try await sharing.remove(participant, from: household)
            } catch {
                failure = RemoveDevicesWords.failure(device: DeviceWords.this)
            }
            isRemoving = false
        }
    }
}

// MARK: - Companions

/// The household's companions, each opening the wall's companion editor.
struct PocketCompanionsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(CompanionStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(small: model.household?.name, title: "Companions")
                PhoneList {
                    ForEach(Array(store.snapshot.companions.enumerated()), id: \.element.id) { index, companion in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: YouPage.companion(companion.id)) {
                            HStack(spacing: 12) {
                                CompanionFace(look: store.snapshot.look(of: companion), size: 34)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(companion.name).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                                    Text(routinesLine(companion))
                                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                                        .foregroundStyle(Theme.muted)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("companion-\(companion.name)")
                    }
                    if !store.snapshot.companions.isEmpty { RowDivider() }
                    NavigationLink(value: YouPage.companion(nil)) {
                        InfoRow(emoji: "➕", title: store.companions.isEmpty ? "Add a pet or plant" : "Add a companion", detail: "With routines like walks, feeds or watering", chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("add-companion")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("Companions")
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
    }

    private func routinesLine(_ companion: Companion) -> String {
        let routines = store.snapshot.routines(of: companion.id).map { "\($0.title) \($0.cadenceText(calendar: model.calendar))" }
        return routines.isEmpty ? companion.species.label : routines.joined(separator: " · ")
    }
}

// MARK: - Chores

/// Every chore, as the wall's board lists them, each opening the wall's chore editor.
struct PocketChoresPage: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store

    var body: some View {
        let active = store.activeChores
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(small: model.household?.name, title: "Chores")
                PhoneList {
                    ForEach(Array(active.enumerated()), id: \.element.id) { index, chore in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: YouPage.chore(chore.id)) {
                            InfoRow(emoji: chore.emoji ?? "☑️", title: chore.title, detail: detail(chore), chevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chore-\(chore.title)")
                    }
                    if !active.isEmpty { RowDivider() }
                    NavigationLink(value: YouPage.chore(nil)) {
                        InfoRow(emoji: "➕", title: "New chore", detail: "Whose it is, how often, and its stars", chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("new-chore")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("Chores")
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
    }

    /// "Mia · Every Monday · ⭐ 2".
    private func detail(_ chore: Chore) -> String {
        let owner = chore.ownerId.flatMap { model.everyone.person($0) }?.name ?? "Anyone"
        return [owner, ChoreSchedule.describe(chore, today: store.today, calendar: store.calendar), "⭐ \(chore.stars)"].joined(separator: " · ")
    }
}

// MARK: - Rewards

struct PocketRewardsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store

    var body: some View {
        let rewards = store.snapshot.rewards
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(small: model.household?.name, title: "Rewards")
                PhoneList {
                    ForEach(Array(rewards.enumerated()), id: \.element.id) { index, reward in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: YouPage.reward(reward.id)) {
                            InfoRow(emoji: reward.emoji ?? "🎁", title: reward.title, detail: detail(reward), chevron: true)
                        }
                        .buttonStyle(.plain)
                        .opacity(reward.archived ? 0.6 : 1)
                        .accessibilityIdentifier("reward-\(reward.title)")
                    }
                    if !rewards.isEmpty { RowDivider() }
                    NavigationLink(value: YouPage.reward(nil)) {
                        InfoRow(emoji: "➕", title: "New reward", detail: "A treat that chores' stars count toward", chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("new-reward")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("Rewards")
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
    }

    /// "For Mia · 12 of 30 stars", "Archived".
    private func detail(_ reward: Reward) -> String {
        if reward.archived { return "Archived" }
        let who = reward.ownerId.flatMap { model.everyone.person($0) }.map { "For \($0.name)" } ?? "Together"
        return "\(who) · \(store.earned(toward: reward)) of \(StarWords.count(reward.targetStars))"
    }
}

// MARK: - Lists

/// The household's lists: rename, add one (groceries or to-do), and delete one.
struct PocketListsSetupPage: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @State private var title = ""
    @State private var kind: ListKind = .todo
    @State private var deleting: HomeList?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(small: model.household?.name, title: "Lists")
                PhoneList {
                    ForEach(Array(store.snapshot.lists.enumerated()), id: \.element.id) { index, list in
                        if index > 0 { RowDivider() }
                        HStack(spacing: 8) {
                            InfoRow(emoji: list.kind == .grocery ? "🛒" : "📝", title: list.title, detail: "\(store.items(in: list).count) items · \(list.kind.label)")
                            Button { deleting = list } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(list.title)")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    PhoneCardHeader(title: "New list")
                    TextField("e.g. Costco", text: $title)
                        .phoneFont(.body, 15.5, weight: 600)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                        .accessibilityIdentifier("new-list-title")
                    FlowLayout(spacing: 6, lineSpacing: 0) {
                        PhoneChoice(title: "🛒 Grocery", isOn: kind == .grocery) { kind = .grocery }
                        PhoneChoice(title: "📝 To-do", isOn: kind == .todo) { kind = .todo }
                    }
                    Button("Add list", action: add)
                        .buttonStyle(PhoneButtonStyle())
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("add-list")
                    if let error = store.lastError {
                        Text(error).phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote).foregroundStyle(Theme.accent)
                    }
                }
                .phoneCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Lists")
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        .confirmationDialog("Delete \(deleting?.title ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete list and its items", role: .destructive) {
                if let deleting { store.delete(deleting) }
                deleting = nil
            }
        } message: {
            Text("It goes from every device in the household.")
        }
    }

    private func add() {
        if store.createList(title: title, kind: kind) { title = "" }
    }
}

// MARK: - Editors as pages

/// One of the wall's editors as a page under You; closing it (Save, Delete) goes back.
struct PocketEditorPage<Editor: View>: View {
    let title: String
    @ViewBuilder var editor: () -> Editor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            editor()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .environment(\.closeWallSheet, CloseWallSheetAction { dismiss() })
        .navigationTitle(title)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
    }
}
