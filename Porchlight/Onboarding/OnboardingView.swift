import SwiftUI

/// First-run setup: name the household, say how this iPad is used, add the people who
/// live here, and finally say plainly where the household lives (journey A1).
struct OnboardingView: View {
    /// "Invite phones now" on the last step: setup ends on Family & devices.
    var onInvite: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device
    @Environment(SyncController.self) private var sync
    @Environment(\.openURL) private var openURL

    private enum Step: Int, CaseIterable {
        case household, role, people, calendars, companions, journals, display, iCloud

        var title: String {
            switch self {
            case .household: "Your household"
            case .role: "This iPad"
            case .people: "People"
            case .calendars: "Calendars"
            case .companions: "Companions"
            case .journals: "Journals"
            case .display: "This display"
            case .iCloud: "iCloud"
            }
        }
    }

    @State private var step: Step = .household
    @AppStorage(DisplaySettings.keepAwakeKey) private var keepAwake = true
    @State private var householdName = ""
    @State private var people: [PersonDraft] = [PersonDraft(name: "", color: .suggested(for: 0))]
    @FocusState private var focusedRow: Int?

    var body: some View {
        HStack(spacing: 0) {
            steps
            VStack(alignment: .leading, spacing: 22) {
                switch step {
                case .household: householdStep
                case .role: roleStep
                case .people: peopleStep
                case .calendars: CalendarOnboardingStep()
                case .companions: CompanionOnboardingStep()
                case .journals: FoodOnboardingStep()
                case .display: displayStep
                case .iCloud: iCloudStep
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.background)
        .ignoresSafeArea(.container, edges: .vertical)
        .onAppear {
            // The household is created after "People"; resume there if setup was interrupted.
            if model.household != nil && step.rawValue < Step.calendars.rawValue { step = .calendars }
            if let name = DebugLaunch.onboardingStep,
               let debugStep = Step.allCases.first(where: { String(describing: $0) == name }) {
                step = debugStep
            }
        }
    }

    // MARK: Steps sidebar

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Logo(size: 34)
                Text("Porchlight").font(.display(21))
            }
            .padding(.bottom, 28)
            ForEach(Step.allCases, id: \.self) { item in
                StepRow(number: item.rawValue + 1, title: item.title, state: state(of: item))
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 32)
        .frame(width: 270)
        .frame(maxHeight: .infinity)
        .background(Theme.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private func state(of item: Step) -> StepRow.State {
        item.rawValue < step.rawValue ? .done : (item == step ? .current : .upcoming)
    }

    // MARK: Step 1

    private var householdStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Welcome home", "Porchlight turns this iPad into your household's wall calendar. First, what should we call your home?")
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Household name")
                TextField("e.g. The Lake House", text: $householdName)
                    .font(.body(20, weight: 600))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit(next)
                    .fieldStyle()
                    .frame(maxWidth: 460)
            }
        }
    }

    // MARK: Step 2

    private var roleStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("How will this \(device.model) be used?", "You can change this later in Settings.")
            DeviceRoleChoice(role: Binding(get: { device.role }, set: { device.setRole($0) }), model: device.model)
                .frame(maxWidth: 620)
        }
    }

    // MARK: Step 3

    private var peopleStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Who lives here?", "Everyone gets a color. It marks their calendar, and who walked the dog or cooked dinner.")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(people.indices, id: \.self) { index in
                    PersonEditorRow(
                        name: $people[index].name,
                        color: $people[index].color,
                        canRemove: people.count > 1,
                        onRemove: { people.remove(at: index) }
                    )
                    .focused($focusedRow, equals: index)
                }
                Button {
                    people.append(PersonDraft(name: "", color: .suggested(for: people.count)))
                    focusedRow = people.count - 1
                } label: {
                    Label("Add someone", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: 620)
        }
    }

    // MARK: Display

    private var displayStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Make it a wall display", "A few settings turn this iPad into a calm, always-on household screen.")
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $keepAwake) {
                    Text("Keep the screen on while Porchlight is open").font(.body(17, weight: 600))
                }
                .tint(Theme.good)
                .card(padding: 16)
                tip("lock", "Lock the iPad to Porchlight", "Settings › Accessibility › Guided Access, then triple-click the Home button while Porchlight is open.")
                tip("bolt.batteryblock", "Be kind to the battery", "An older iPad plugged in all day can swell. A smart plug that charges it a few hours a day keeps it healthy.")
            }
            .frame(maxWidth: 620)
        }
    }

    // MARK: Last step

    /// Where the household lives, said plainly; without iCloud it never blocks.
    @ViewBuilder
    private var iCloudStep: some View {
        let name = model.household?.name ?? "Your household"
        if sync.status == .noAccount {
            heading(
                "Keep it on this \(device.model) for now?",
                "This \(device.model) isn't signed in to iCloud, so phones can't join yet and nothing is backed up. Everything works here. Sign in later and Porchlight moves the household into iCloud."
            )
        } else {
            VStack(alignment: .leading, spacing: 22) {
                heading(
                    "\(name) lives in your iCloud",
                    "Everyone you invite uses it through your iCloud, so it is backed up and works on their phones. Photos are most of it: a busy family adds about 300 MB a year. Nobody else, including us, can see it."
                )
                HStack(spacing: 14) {
                    Text("☁️").font(.system(size: 30)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uses the iCloud account on this \(device.model)").font(.body(17, weight: 700))
                        Text("To use a different Apple ID, change it in \(device.model) Settings first.")
                            .font(.body(14, weight: 600))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(18)
                .frame(maxWidth: 620, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 2))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.wash(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body(16, weight: 700))
                Text(detail).font(.body(14)).foregroundStyle(Theme.muted)
            }
        }
        .card(padding: 16)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let error = model.lastError {
                Text(error)
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            if step == .role || step == .people {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .household }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if step == .iCloud {
                lastButtons
            } else {
                Button("Continue", action: next)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canContinue)
            }
        }
    }

    @ViewBuilder
    private var lastButtons: some View {
        if sync.status == .noAccount {
            Button("Open \(device.model) Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(SecondaryButtonStyle())
            Button("Keep going on this \(device.model)", action: next)
                .buttonStyle(PrimaryButtonStyle())
        } else {
            Button("Invite phones now") {
                onInvite()
                next()
            }
            .buttonStyle(SecondaryButtonStyle())
            Button("Finish", action: next)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var canContinue: Bool {
        switch step {
        case .household:
            !householdName.trimmingCharacters(in: .whitespaces).isEmpty
        case .people:
            people.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        case .role, .calendars, .companions, .journals, .display, .iCloud:
            true
        }
    }

    private func next() {
        guard canContinue else { return }
        switch step {
        case .household:
            step = .role
        case .role:
            step = .people
            focusedRow = 0
        case .people:
            // Blank rows are simply skipped.
            let named = people.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            if model.createHousehold(name: householdName, people: named) { step = .calendars }
        case .calendars:
            step = .companions
        case .companions:
            step = .journals
        case .journals:
            step = .display
        case .display:
            step = .iCloud
        case .iCloud:
            _ = model.finishSetup()
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        OnboardingHeading(title: title, subtitle: subtitle)
    }
}

/// Big title + subtitle at the top of every onboarding step (features use it too).
struct OnboardingHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.display(38))
            Text(subtitle)
                .font(.body(16, weight: 500))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }
}

private struct StepRow: View {
    enum State { case done, current, upcoming }

    let number: Int
    let title: String
    let state: State

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(state == .done ? Theme.good : .clear)
                Circle()
                    .stroke(borderColor, lineWidth: 2)
                if state == .done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.body(13, weight: 700)).foregroundStyle(state == .current ? Theme.accent : Theme.muted)
                }
            }
            .frame(width: 28, height: 28)
            Text(title)
                .font(.body(15, weight: 700))
                .foregroundStyle(state == .upcoming ? Theme.muted : Theme.ink)
            Spacer()
        }
        .padding(10)
        .background {
            if state == .current {
                SurfaceShape(cornerRadius: 12, elevation: 0.7)
            }
        }
    }

    private var borderColor: Color {
        switch state {
        case .done: Theme.good
        case .current: Theme.accent
        case .upcoming: Theme.line
        }
    }
}

/// Name field plus color choice for one person. Shared by onboarding and Settings.
struct PersonEditorRow: View {
    @Binding var name: String
    @Binding var color: PersonColor
    var canRemove: Bool
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Avatar(
                initial: name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?",
                color: color.color,
                size: 44
            )
            TextField("Name", text: $name)
                .font(.body(18, weight: 600))
                .textInputAutocapitalization(.words)
                .fieldStyle()
            ColorChoice(selection: $color)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(canRemove ? 1 : 0)
            .disabled(!canRemove)
            .accessibilityLabel("Remove \(name)")
        }
        .padding(12)
        .background(SurfaceShape(cornerRadius: Theme.smallRadius + 4, elevation: 0.7))
    }
}

struct ColorChoice: View {
    @Binding var selection: PersonColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PersonColor.allCases, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 26, height: 26)
                        .padding(3)
                        .overlay(Circle().stroke(selection == option ? Theme.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
    }
}

extension View {
    /// The bordered text-field look used across setup and settings.
    func fieldStyle() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).stroke(Theme.line))
            .foregroundStyle(Theme.ink)
            .tint(Theme.accent)
    }
}
