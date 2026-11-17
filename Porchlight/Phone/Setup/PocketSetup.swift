import SwiftUI

/// A phone with no household, or one being set up here: the welcome's two doors, then the
/// four short steps of starting a household (journey A2). One view for both, so creating
/// the household midway doesn't start the flow over.
struct PocketStart: View {
    @Environment(AppModel.self) private var model
    /// `-debugSetup you|people|companion|done` (with `-resetData`) opens that step.
    @State private var starting = DebugLaunch.setupStep != nil

    var body: some View {
        // A household that isn't set up yet was started here and interrupted: carry on.
        if starting || model.household != nil {
            PocketSetupView(resumes: !starting)
        } else {
            PocketWelcome { starting = true }
        }
    }
}

/// Starting a household on this phone: you and the household, who else lives here, anyone
/// to look after, then ready (`a2you` to `a2done`). The household is created after "Who else
/// lives here", through `HouseholdSetup`, as the wall's setup creates it; this phone is
/// personal and belongs to its first person.
struct PocketSetupView: View {
    /// A household already exists but setup didn't finish: start at the companion step.
    var resumes = false

    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device
    @Environment(CompanionStore.self) private var companions
    @State private var setup = HouseholdSetup()
    @State private var step: Step = .you
    @State private var companion = CompanionDraft.new(species: .dog)
    @State private var didStart = false
    @FocusState private var focused: Field?
    @Environment(\.dynamicTypeSize) private var typeSize

    enum Step: Int, CaseIterable {
        case you, people, companion, done
    }

    private enum Field: Hashable {
        case household, myName, person(Int), companion
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepDots(count: Step.allCases.count, index: step.rawValue)
                    .frame(maxWidth: .infinity)
                switch step {
                case .you: youStep
                case .people: peopleStep
                case .companion: companionStep
                case .done: PocketSetupDone()
                }
                if let error = model.lastError ?? companions.lastError, step != .done {
                    Text(error)
                        .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.accent)
                }
                // At accessibility sizes the buttons would cover half the screen if pinned,
                // so they end the page instead.
                if typeSize.isAccessibilitySize { buttons }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if !typeSize.isAccessibilitySize { buttons }
        }
        // Standing outside the tabs, it keeps scrolled text out from under the clock.
        .clipped()
        .background(Theme.background)
        .paperUnderStatusBar()
        .onAppear(perform: start)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private func start() {
        guard !didStart else { return }
        didStart = true
        model.lastError = nil
        if resumes { step = .companion }
        #if DEBUG
        if let name = DebugLaunch.setupStep, let debugStep = Step.allCases.first(where: { "\($0)" == name }) {
            if setup.householdName.isEmpty {
                setup.householdName = "The Lake House"
                setup.people = [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral), PersonDraft(name: "Ava", color: .sage)]
            }
            if debugStep.rawValue > Step.people.rawValue, model.household == nil {
                setup.create(app: model, device: device, owner: 0)
            }
            if debugStep == .companion { companion.name = "Yo-Yo" }
            step = debugStep
        }
        #endif
    }

    // MARK: You and the household

    private var youStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Let's start with you", "You'll be the first person in the household, and its owner.")
            field("Household name") {
                TextField("e.g. The Lake House", text: $setup.householdName)
                    .textContentType(.organizationName)
                    .focused($focused, equals: .household)
                    .submitLabel(.next)
                    .onSubmit { focused = .myName }
                    .accessibilityIdentifier("household-name")
            }
            field("Your name") {
                TextField("e.g. James", text: $setup.people[0].name)
                    .textContentType(.givenName)
                    .focused($focused, equals: .myName)
                    .submitLabel(.done)
                    .accessibilityIdentifier("my-name")
            }
            VStack(alignment: .leading, spacing: 4) {
                label("Your color")
                PhoneColorChoice(selection: $setup.people[0].color)
            }
        }
    }

    // MARK: Who else lives here

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Who else lives here?", "Anyone you'll credit for walks, chores or meals. They don't need the app, and anyone with a phone can be invited when you're done.")
            VStack(spacing: 10) {
                ForEach(Array(setup.people.indices.dropFirst()), id: \.self) { index in
                    personRow(index)
                }
                Button {
                    focused = .person(setup.addPerson())
                } label: {
                    Label("Add someone", systemImage: "plus")
                        .phoneFont(.body, 15, weight: 700)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("add-someone")
            }
        }
    }

    private func personRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Avatar(
                    initial: setup.people[index].name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?",
                    color: setup.people[index].color.color,
                    size: 34
                )
                .accessibilityHidden(true)
                TextField("Name", text: $setup.people[index].name)
                    .phoneFont(.body, 16, weight: 600)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .person(index))
                    .submitLabel(.done)
                    .accessibilityIdentifier("person-name-\(index)")
                Button { setup.removePerson(at: index) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 30)
                        .background(Theme.surface2, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(setup.people[index].name.isEmpty ? "this person" : setup.people[index].name)")
            }
            PhoneColorChoice(selection: $setup.people[index].color)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Anyone to look after

    private var companionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Anyone to look after?", "Pets and plants. Each gets its own routines and reminders.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Species.allCases, id: \.self) { species in
                    PhoneSpeciesTile(species: species, isOn: companion.species == species) { choose(species) }
                }
            }
            field("Name") {
                TextField(companion.species == .plant ? "e.g. Fiddle fig" : "e.g. Yo-Yo", text: $companion.name)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .companion)
                    .submitLabel(.done)
                    .accessibilityIdentifier("companion-name")
            }
            Text(routinesLine)
                .phoneFont(.body, 13, weight: 500, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choose(_ species: Species) {
        let name = companion.name
        companion = .new(species: species)
        companion.name = name
    }

    /// "Suggested routines: walk twice a day and feed twice a day. Change them any time."
    private var routinesLine: String {
        let calendar = model.calendar
        let routines = companion.routines.map { "\($0.title.lowercased()) \($0.routine().cadenceText(calendar: calendar).lowercased())" }
        guard !routines.isEmpty else { return "Add its routines in Household, from You, any time." }
        return "Suggested routines: \(ListFormat.join(routines)). Change them any time in Household, from You."
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 8) {
            switch step {
            case .you:
                Button("Continue") { go(to: .people) }
                    .buttonStyle(PhoneButtonStyle())
                    .disabled(!setup.hasName || setup.people[0].name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("setup-continue")
            case .people:
                Button("Continue", action: create)
                    .buttonStyle(PhoneButtonStyle())
                    .accessibilityIdentifier("setup-continue")
                Button("Back") { go(to: .you) }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
            case .companion:
                Button("Continue", action: saveCompanion)
                    .buttonStyle(PhoneButtonStyle())
                    .disabled(companion.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("setup-continue")
                Button("Skip for now") { go(to: .done) }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
                    .accessibilityIdentifier("setup-skip")
            case .done:
                Button("Go to Today") { _ = model.finishSetup() }
                    .buttonStyle(PhoneButtonStyle())
                    .accessibilityIdentifier("go-to-today")
            }
        }
        .padding(.horizontal, typeSize.isAccessibilitySize ? 0 : 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    private func go(to next: Step) {
        focused = nil
        model.lastError = nil
        step = next
    }

    /// Creates the household with everyone named so far; this phone is its first person's.
    private func create() {
        focused = nil
        if model.household == nil {
            // The first row is me; it always has a name by now.
            guard setup.create(app: model, device: device, owner: 0) != nil else { return }
        }
        go(to: .companion)
    }

    private func saveCompanion() {
        focused = nil
        companions.lastError = nil
        guard companions.save(companion) != nil else { return }
        go(to: .done)
    }

    // MARK: Pieces

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .phoneFont(.body, 14.5, weight: 500)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            content()
                .phoneFont(.body, 16, weight: 600)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
        }
    }
}

/// A species to choose, as a tile: its emoji and name.
struct PhoneSpeciesTile: View {
    let species: Species
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(species.emoji).phoneFont(.body, 24).accessibilityHidden(true)
                Text(species.label).phoneFont(.body, 15, weight: 700, relativeTo: .subheadline)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(isOn ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isOn ? Theme.accent : Theme.line, lineWidth: isOn ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(species.label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// "The Lake House is ready" (`a2done`): where it lives, in `HouseholdHome`'s words; invite
/// whoever else lives here; a spare iPad can be the family's shared screen.
private struct PocketSetupDone: View {
    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(SyncController.self) private var sync
    @Environment(DeviceSettings.self) private var device
    @State private var invite: HouseholdInvite?
    @State private var failure: String?

    var body: some View {
        let household = model.household?.name ?? "Your household"
        let others = model.people.filter { $0.id != me }
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 8) {
                Text("✨").font(.system(size: 44)).accessibilityHidden(true)
                Text("\(household) is ready")
                    .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(whereLine(others))
                    .phoneFont(.body, 14.5, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setup-home")
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    PhoneCardHeader(title: "Invite", meta: others.count == 1 ? "1 person" : "\(others.count) people")
                    if let reason = home.inviteBlocker(device: DeviceWords.this) ?? sharing.unavailableReason ?? failure {
                        Text(reason)
                            .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(others) { person in
                        AdaptiveRow(spacing: 12) {
                            HStack(spacing: 12) {
                                PersonAvatar(person)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.name).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                                    Text("Send an invite by Messages or AirDrop")
                                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                                        .foregroundStyle(Theme.muted)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button("Invite", action: openInvite)
                                .phoneFont(.body, 12.5, weight: 800, relativeTo: .caption)
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1))
                                .frame(minHeight: 44)
                                .disabled(!canInvite)
                                .opacity(canInvite ? 1 : 0.4)
                                .accessibilityLabel("Invite \(person.name)")
                        }
                        .padding(.vertical, 6)
                    }
                }
                .phoneCard()
            }
            VStack(alignment: .leading, spacing: 6) {
                PhoneCardHeader(title: "Got a spare iPad?")
                Text(spareIPadLine)
                    .phoneFont(.body, 13.5, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .phoneCard()
        }
        .sheet(item: $invite) { InviteSheet(invite: $0, onDone: { invite = nil }) }
    }

    private var me: Person.ID? {
        model.household.flatMap { device.me(in: $0.id) }
    }

    private var home: HouseholdHome {
        HouseholdHome.from(sync.status, isOwner: true, ownerName: nil)
    }

    /// How a spare iPad joins: a join code from this phone where it can make one.
    private var spareIPadLine: String {
        let join = sharing.service.supportsJoinSeats
            ? "choose \u{201C}Join one\u{201D}, and scan the code from You › Invite someone › Show a code on this \(DeviceWords.this)"
            : "choose \u{201C}Join one\u{201D}, and open an invite you send it"
        return "Open Porchlight on it, \(join). Then make it a shared screen to put the whole family's day on the wall."
    }

    private var canInvite: Bool {
        home.inviteBlocker(device: DeviceWords.this) == nil && sharing.unavailableReason == nil
    }

    /// "It's stored in your iCloud. Invite Mia so her phone shows the same day."
    private func whereLine(_ others: [Person]) -> String {
        let place = "It's \(home.whereText(device: DeviceWords.this))."
        guard !others.isEmpty else { return place + " Invite someone any time from You." }
        let names = ListFormat.join(others.map(\.name))
        return place + (canInvite ? " Invite \(names) so their phones show the same day." : " Once it's in iCloud you can invite \(names).")
    }

    private func openInvite() {
        guard let household = model.household else { return }
        failure = nil
        Task {
            do {
                invite = try await sharing.service.invite(household)
            } catch {
                failure = error.userMessage
            }
        }
    }
}
