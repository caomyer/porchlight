import SwiftUI

/// "You", from the avatar on every tab: who you are (and a way to change it), the
/// household (and setting it up), inviting someone, the people and their devices, its
/// storage, this device's name, role, calendars and notifications, sync, and leaving.
struct YouSheet: View {
    /// The page to open on, when a tab sent someone here ("Set up the household").
    var start: YouPage?

    init(start: YouPage? = nil) {
        self.start = start
        // Pages under Household go back to it.
        _path = State(initialValue: start.map { $0 == .household || $0 == .storage ? [$0] : [.household, $0] } ?? [])
    }

    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(SyncController.self) private var sync
    @Environment(CalendarStore.self) private var calendars
    @Environment(HomeStore.self) private var home
    @Environment(CompanionStore.self) private var companions
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss

    @State private var path: [YouPage] = []
    /// The sharing sheet, presented from the You sheet itself: one presented from a page
    /// pushed inside it would take the You sheet down with it when it closes.
    @State private var invite: HouseholdInvite?
    /// "Leave The Lake House?", or, for its owner, why they can't.
    @State private var leaving = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 18) {
                    identity
                    if sync.decision != nil {
                        SyncDecisionCard()
                    }
                    PhoneList {
                        if let household = model.household {
                            Button { path.append(.household) } label: {
                                InfoRow(emoji: "🏡", title: household.name, detail: "People, companions, chores, rewards, lists", chevron: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("household")
                            RowDivider()
                            Button { path.append(.storage) } label: {
                                InfoRow(emoji: "☁️", title: "iCloud storage", detail: homeLine, chevron: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("household-home")
                            RowDivider()
                        }
                        Button { path.append(.invite) } label: {
                            InfoRow(emoji: "✉️", title: "Invite someone", detail: inviteLine, chevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("invite-someone")
                    }
                    PeopleCard(roster: roster)
                    PhoneList {
                        Button { path.append(.deviceName) } label: {
                            InfoRow(emoji: "📱", title: device.name(me: me), detail: roleLine, chevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("this-device")
                        if device.role == .personal {
                            RowDivider()
                            Button { path.append(.whoAreYou) } label: {
                                InfoRow(emoji: "🙋", title: "This \(DeviceWords.this) is \(me?.name ?? "me")", detail: "Change who you are here", chevron: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("change-me")
                        }
                        RowDivider()
                        Button { path.append(.calendars) } label: {
                            InfoRow(emoji: "📅", title: "Calendars", detail: calendarsLine, chevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("calendars")
                        RowDivider()
                        Button { path.append(.notifications) } label: {
                            InfoRow(emoji: "🔔", title: "Notifications", detail: "Your routines · chores", chevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notifications")
                    }
                    // The phone's own switch, so "Turn on iCloud sync" always has a place to go.
                    PhoneList {
                        Toggle(isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) })) {
                            HStack(spacing: 12) {
                                Text("☁️").phoneFont(.body, 20).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Sync with iCloud").phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                                    Text(sync.status.phoneSummary(device: DeviceWords.this))
                                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                                        .foregroundStyle(Theme.muted)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.good)
                        .disabled(!sync.isAvailable || sync.decision != nil)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("sync-switch")
                        SyncDetails(compact: true)
                            .padding(.bottom, 8)
                    }
                    if let household = model.household {
                        PhoneList {
                            Button { leaving = true } label: {
                                InfoRow(emoji: "🚪", title: "Leave \(household.name)", detail: sharing.members.isOwner ? "It's yours, so it stays with you" : "Your history stays with the household")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("leave-household")
                        }
                    }
                    // Which build this phone runs, quietly, last.
                    Text(AppVersion.text)
                        .phoneFont(.body, 11.5, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("app-version")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            // Names the way back from every page, "‹ You", without a title on this one.
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .phoneFont(.body, 15, weight: 700)
                        .foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationDestination(for: YouPage.self) { page in
                Group {
                    switch page {
                    case .whoAreYou:
                        WhoAreYouView(current: me?.id) { picked in
                            if let household = model.household { device.setMe(picked, in: household.id) }
                            path.removeAll()
                        }
                    case .invite:
                        InvitePage(roster: roster, present: { invite = $0 })
                    case .joinCode:
                        JoinCodePage()
                    case .deviceName:
                        DeviceNamePage(onDone: { path.removeAll() })
                    case .calendars:
                        PocketCalendars()
                    case .notifications:
                        PocketNotifications()
                    case .household:
                        PocketHouseholdHub()
                    case let .person(id):
                        PocketPersonPage(personId: id)
                    case .companions:
                        PocketCompanionsPage()
                    case let .companion(id):
                        PocketCompanionPage(companionId: id)
                    case .chores:
                        PocketChoresPage()
                    case let .chore(id):
                        PocketEditorPage(title: id == nil ? "New chore" : "Chore") {
                            ChoreEditor(chore: id.flatMap { id in home.snapshot.chores.first { $0.id == id } }, newOwner: me?.id)
                        }
                    case .rewards:
                        PocketRewardsPage()
                    case let .reward(id):
                        PocketEditorPage(title: id == nil ? "New reward" : "Reward") {
                            RewardEditor(reward: id.flatMap { id in home.snapshot.rewards.first { $0.id == id } })
                        }
                    case .lists:
                        PocketListsSetupPage()
                    case .storage:
                        PocketStoragePage()
                    }
                }
                .background(Theme.background)
            }
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.background)
        .sheet(item: $invite) { InviteSheet(invite: $0, onDone: { invite = nil }) }
        .sheet(isPresented: $leaving) {
            PocketLeaveSheet(onManage: {
                leaving = false
                path = [.household]
            }, onLeft: { dismiss() })
        }
        #if DEBUG
        .onAppear {
            // `-debugYouPage household|storage|leave|companions|chores|rewards|lists` opens a page.
            switch UserDefaults.standard.string(forKey: "debugYouPage") {
            case "household": path = [.household]
            case "storage": path = [.storage]
            case "leave": leaving = true
            case "companions": path = [.household, .companions]
            case "companion": path = [.household, .companions, .companion(companions.companions.first?.id)]
            case "chores": path = [.household, .chores]
            case "rewards": path = [.household, .rewards]
            case "lists": path = [.household, .lists]
            case "person": path = [.household] + (model.people.last.map { [.person($0.id)] } ?? [])
            default: break
            }
        }
        #endif
        .task { await sharing.refresh(model.household) }
    }

    private var roster: FamilyRoster {
        FamilyRoster(
            snapshot: model.snapshot, members: sharing.members, thisDevice: model.thisDeviceId,
            thisUserName: sync.userName ?? sharing.userName, onSharedScreen: device.role == .sharedScreen
        )
    }

    private var identity: some View {
        VStack(spacing: 6) {
            PersonAvatar(me, size: .large)
            Text(me?.name ?? "This \(DeviceWords.this)")
                .phoneFont(.display, 24, weight: 600, relativeTo: .title)
                .accessibilityAddTraits(.isHeader)
            if let household = model.household {
                let isOwner = sharing.members.isOwner && !sharing.members.participants.isEmpty
                Text(([household.name] + (isOwner ? ["owner"] : []) + [device.role == .personal ? "this \(DeviceWords.this) credits you" : "a shared screen"]).joined(separator: " · "))
                    .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Where the household lives now: "Stored in James's iCloud", "On this iPhone only".
    private var homeLine: String {
        let home = HouseholdHome.from(
            sync.status, isOwner: sharing.members.isOwner,
            ownerName: sharing.ownerName(people: model.everyone, devices: model.devices)
        )
        let text = home.whereText(device: DeviceWords.this)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Mia hasn't joined yet", or how to invite.
    private var inviteLine: String {
        if let waiting = roster.rows.first(where: { $0.person != nil && $0.state != .joined }) {
            return "\(waiting.title) hasn't joined yet"
        }
        return sharing.members.isOwner ? "Send a link, or show a code" : "Only the owner can add people"
    }

    /// "2 shown on Today", or why there are none.
    private var calendarsLine: String {
        switch calendars.access {
        case .notDetermined: return "Choose which show on Today"
        case .denied: return "Access is off"
        case .granted:
            let shown = calendars.mappings.filter(\.source.isShown).count
            return shown == 0 ? "None shown on Today" : "\(shown) shown on Today"
        }
    }

    private var roleLine: String {
        switch device.role {
        case .personal: "Personal: what you log is credited to you"
        case .sharedScreen: "Shared screen: asks who did it"
        }
    }
}

enum YouPage: Hashable {
    case whoAreYou, invite, joinCode, deviceName, calendars, notifications
    /// Household setup (F1, F2) and storage (E4).
    case household, person(Person.ID), companions, companion(Companion.ID?), chores, chore(Chore.ID?)
    case rewards, reward(Reward.ID?), lists, storage
}

/// A list card in the You sheet.
struct PhoneList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The household's people and how each uses Porchlight.
private struct PeopleCard: View {
    let roster: FamilyRoster

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PhoneCardHeader(title: "People", meta: roster.summary)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(Array(roster.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { RowDivider() }
                PersonStateRow(row: row)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("people-card")
    }
}

/// A person with how they use Porchlight: their devices, invited, or no phone yet.
struct PersonStateRow: View {
    let row: FamilyRoster.Row
    var action: (title: String, run: () -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            HStack(spacing: 12) {
                if let person = row.person {
                    PersonAvatar(person)
                } else {
                    Image(systemName: "envelope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface2, in: Circle())
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                    Text(row.detail)
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(TakeButtonStyle())
                    .accessibilityLabel("\(action.title) \(row.title)")
            } else {
                PhoneStatePill(state: row.state)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// "Joined", "Invited", "No phone", at phone size.
struct PhoneStatePill: View {
    let state: FamilyRoster.Row.State

    var body: some View {
        let (text, ink, fill): (String, Color, Color) = switch state {
        case .joined: ("Joined", Theme.goodInk, Theme.goodSoft)
        case .invited: ("Invited", Theme.accent, Theme.accentSoft)
        case .noPhone: ("No phone", Theme.muted, Theme.surface2)
        }
        Text(text)
            .phoneFont(.body, 11.5, weight: 800, relativeTo: .caption)
            .foregroundStyle(ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(fill, in: Capsule())
            .fixedSize()
    }
}

/// The outlined accent capsule of "Invite" and "I'll do it", with a 44 pt target.
struct TakeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .phoneFont(.body, 12.5, weight: 800, relativeTo: .caption)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .fixedSize()
    }
}

/// "Invite someone" (journey A3 on the phone): people who haven't joined come first, then
/// someone new, then the code for someone standing next to you.
private struct InvitePage: View {
    let roster: FamilyRoster
    let present: (HouseholdInvite) -> Void

    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(SyncController.self) private var sync
    @State private var failure: String?
    @State private var addsSomeone = false
    @State private var newPerson = PersonDraft(name: "", color: .blue)

    private var waiting: [FamilyRoster.Row] {
        roster.rows.filter { $0.person != nil && $0.state != .joined }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.household?.name ?? "")
                        .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                    Text("Invite someone")
                        .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(explanation)
                    .phoneFont(.body, 13.5, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("invite-explanation")
                if let reason = blocker ?? failure {
                    StatusBanner(tone: .info, emoji: "☁️", title: "Inviting needs iCloud", detail: reason)
                        .accessibilityIdentifier("invite-blocker")
                }
                VStack(spacing: 0) {
                    ForEach(Array(waiting.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider() }
                        PersonStateRow(row: row, action: ("Invite", openInvite))
                    }
                    if !waiting.isEmpty { RowDivider() }
                    someoneNew
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                PublicLinkNotice()
                if case let .elsewhere(text) = codeAvailability {
                    JoinCodeElsewhere(text: text, compact: true)
                        .padding(.horizontal, 4)
                }
                if codeAvailability == .available {
                NavigationLink(value: YouPage.joinCode) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Show a code instead").phoneFont(.display, 17, weight: 600, relativeTo: .headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.muted)
                        }
                        Text("For someone standing next to you: one code, one person.")
                            .phoneFont(.body, 13, weight: 500)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .phoneCard()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("show-code")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(blocker != nil)
        // "‹ Invite someone" on the code's page; the page shows its own big title.
        .navigationTitle("Invite someone")
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        .onAppear { newPerson.color = .suggested(for: model.people.count) }
    }

    private var home: HouseholdHome {
        HouseholdHome.from(
            sync.status, isOwner: sharing.members.isOwner,
            ownerName: sharing.ownerName(people: model.everyone, devices: model.devices)
        )
    }

    private var codeAvailability: JoinCodeAvailability {
        .decide(
            isOwner: sharing.members.isOwner, supportsSeats: sharing.service.supportsJoinSeats,
            ownerName: sharing.ownerName(people: model.everyone, devices: model.devices)
        )
    }

    /// Why inviting can't work now: sync's state first, then the sharing itself.
    private var blocker: String? {
        home.inviteBlocker(device: DeviceWords.this) ?? sharing.unavailableReason
    }

    /// What joining means, true to where the household lives now.
    private var explanation: String {
        switch home {
        case .yourICloud:
            "They join with their own Apple ID and use your iCloud for the household. It uses almost none of their storage."
        case .ownersICloud:
            "They join with their own Apple ID and the household stays \(home.whereText(device: DeviceWords.this)). It uses almost none of their storage."
        default:
            "The household is \(home.whereText(device: DeviceWords.this)), so nobody can join it yet."
        }
    }

    @ViewBuilder
    private var someoneNew: some View {
        Button { addsSomeone.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface2, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Someone new").phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                    Text("Add them, then invite")
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: addsSomeone ? "chevron.down" : "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("someone-new")
        if addsSomeone {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Their name", text: $newPerson.name)
                    .phoneFont(.body, 15.5, weight: 600)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                    .accessibilityIdentifier("new-person-name")
                PhoneColorChoice(selection: $newPerson.color)
                Button("Add and invite", action: addAndInvite)
                    .buttonStyle(PhoneButtonStyle())
                    .disabled(newPerson.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.bottom, 14)
        }
    }

    private func addAndInvite() {
        guard model.addPerson(newPerson) else {
            failure = model.lastError
            return
        }
        newPerson = PersonDraft(name: "", color: .suggested(for: model.people.count))
        addsSomeone = false
        openInvite()
    }

    private func openInvite() {
        guard let household = model.household else { return }
        failure = nil
        Task {
            do {
                present(try await sharing.service.invite(household))
            } catch {
                failure = error.userMessage
            }
        }
    }
}

/// The code to scan, on the phone, for someone standing next to you.
private struct JoinCodePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let name = model.household?.name ?? "the household"
        ScrollView {
            VStack(spacing: 18) {
                Text("Join \(name)")
                    .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                JoinCodeCard(size: 240, compact: true)
                Text("Point another iPhone's camera here. The first person who scans joins \(name), so show it only to family.")
                    .phoneFont(.body, 14, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

/// This device's name, as the household sees it ("Mia's iPhone").
private struct DeviceNamePage: View {
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device
    @Environment(\.me) private var me
    @State private var name = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("This \(DeviceWords.this)")
                    .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Its name shows on everyone's devices, as in \u{201C}from \(device.name(me: me))\u{201D}.")
                    .phoneFont(.body, 13.5, weight: 500)
                    .foregroundStyle(Theme.muted)
                TextField(device.name(me: me), text: $name)
                    .phoneFont(.body, 15.5, weight: 600)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                    .accessibilityIdentifier("device-name")
                Button("Save", action: save)
                    .buttonStyle(PhoneButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .onAppear { name = device.customName ?? "" }
    }

    private func save() {
        device.setName(name)
        onDone()
    }
}

/// Sync waiting for a choice, on the phone: the same two choices as the wall's Settings.
private struct SyncDecisionCard: View {
    @Environment(SyncController.self) private var sync
    @Environment(AppModel.self) private var model
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch sync.decision {
            case .accountChanged?:
                text("A different iCloud account signed in", "\(householdName) on this \(DeviceWords.this) belongs to the earlier account, so nothing syncs until you choose.")
                Button("Keep it here without sync") { sync.keepDataWithoutSync() }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
                Button("Remove it from this \(DeviceWords.this)") { confirm = true }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
            case .restoredCopy?:
                text("This \(DeviceWords.this)'s data was replaced by an older copy", "iCloud may have newer walks, meals and chores, so nothing syncs until you choose. This copy is never sent over them.")
                Button("Use what is in iCloud") { confirm = true }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
                Button("Keep this copy on this \(DeviceWords.this), without sync") { sync.keepRestoredCopyWithoutSync() }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
            case nil:
                EmptyView()
            }
        }
        .phoneCard()
        .confirmationDialog(confirmTitle, isPresented: $confirm, titleVisibility: .visible) {
            Button(confirmTitle, role: .destructive) {
                Task {
                    await model.removeHouseholdHere {
                        if sync.decision == .restoredCopy { await sync.useCopyInICloud() } else { await sync.removeDataFromDevice() }
                    }
                }
            }
        }
    }

    private var householdName: String { model.household?.name ?? "The household" }

    private var confirmTitle: String {
        sync.decision == .restoredCopy ? "Use what is in iCloud" : "Remove it from this \(DeviceWords.this)"
    }

    private func text(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).phoneFont(.display, 17, weight: 600, relativeTo: .headline)
            Text(detail)
                .phoneFont(.body, 13, weight: 500)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A row in the You sheet: an emoji, a title and a line under it.
struct InfoRow: View {
    let emoji: String
    let title: String
    let detail: String
    var chevron = false
    /// A symbol drawn instead of the emoji, as chores are everywhere on the phone.
    var symbol: (name: String, color: Color)?

    @PhoneMetric(upTo: 1.4) private var symbolSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol.name)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(symbol.color)
                    .frame(minWidth: 24)
                    .accessibilityHidden(true)
            } else {
                Text(emoji).phoneFont(.body, 20).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                Text(detail)
                    .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The hairline between rows in a list card.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }
}
