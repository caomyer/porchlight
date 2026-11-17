import SwiftUI

/// Settings › Family & devices (journeys A3 and D2): who has the app and how, this
/// device's name and role, and the two ways in, an invite or a code to scan. The owner can
/// remove someone's devices here.
struct FamilySection: View {
    /// Brings the iCloud sync switch into view, when sync being off is what stops inviting.
    var showSync: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(DeviceSettings.self) private var device
    @Environment(SyncController.self) private var sync

    @State private var sheet: FamilySheet?
    @State private var invite: HouseholdInvite?
    @State private var failure: String?

    private var roster: FamilyRoster {
        FamilyRoster(
            snapshot: model.snapshot, members: sharing.members, thisDevice: model.thisDeviceId,
            thisUserName: sync.userName ?? sharing.userName, onSharedScreen: device.role == .sharedScreen
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Family & devices")
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(roster.rows) { row in
                    FamilyRowView(row: row) { present(.remove(row)) }
                }
                ForEach(roster.sharedScreens) { screen in
                    FamilyDeviceRow(title: screen.name, detail: "Shared screen · asks who did it")
                }
                FamilyDeviceRow(title: thisDeviceName, detail: "This \(device.model) · " + roleText, action: ("Change", { present(.thisDevice) }))
                actions
            }
            .card(padding: 20)
        }
        .frame(maxWidth: 980, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-settings")
        .wallSheet(item: $sheet, width: sheet?.width ?? 560) { sheet in
            switch sheet {
            case .code: JoinCodeWallSheet()
            case let .remove(row): RemoveDevicesSheet(row: row)
            case .thisDevice: ThisDeviceSheet()
            }
        }
        .sheet(item: $invite) { InviteSheet(invite: $0, onDone: { invite = nil }) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Who has the app").font(.display(22))
                Spacer()
                Text(roster.summary)
                    .font(.body(13, weight: 700))
                    .foregroundStyle(Theme.muted)
            }
            if let household = model.household {
                Text("\(household.name) · \(home.whereText(device: device.model))")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("household-home")
            }
        }
        .padding(.bottom, 8)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("Invite someone", action: openInvite)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("invite")
                Button("Show a code to join") { present(.code) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("show-code")
            }
            .disabled(blocker != nil)
            if let reason = blocker ?? failure {
                HStack(spacing: 10) {
                    Text(reason)
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("invite-blocker")
                    if blocker != nil && home.turnsOnWithTheSwitch {
                        Button("Go to iCloud sync", action: showSync)
                            .font(.body(14, weight: 700))
                            .foregroundStyle(Theme.accent)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("go-to-sync")
                    }
                }
            }
        }
        .padding(.top, 16)
    }

    /// Where the household lives now, from sync's state and the share.
    private var home: HouseholdHome {
        HouseholdHome.from(
            sync.status, isOwner: sharing.members.isOwner,
            ownerName: sharing.ownerName(people: model.everyone, devices: model.devices),
            onSharedScreen: device.role == .sharedScreen
        )
    }

    /// Why inviting can't work now: sync's state first, then the sharing itself.
    private var blocker: String? {
        home.inviteBlocker(device: device.model) ?? sharing.unavailableReason
    }

    private var me: Person? {
        model.household.flatMap { device.me(in: $0.id) }.flatMap(model.people.person)
    }

    private var thisDeviceName: String { device.name(me: me) }

    private var roleText: String {
        switch device.role {
        case .sharedScreen: "Shared screen · asks who did it"
        case .personal: "Just me · credits \(me?.name ?? "its owner")"
        }
    }

    private func present(_ sheet: FamilySheet) {
        withoutAnimation { self.sheet = sheet }
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

private enum FamilySheet: Identifiable {
    case code
    case remove(FamilyRoster.Row)
    case thisDevice

    var id: String {
        switch self {
        case .code: "code"
        case let .remove(row): "remove-\(row.id)"
        case .thisDevice: "this-device"
        }
    }

    var width: CGFloat {
        switch self {
        case .code: 520
        case .remove, .thisDevice: 560
        }
    }
}

/// A person on the family card: avatar, name, how they use Porchlight, and a status pill.
private struct FamilyRowView: View {
    let row: FamilyRoster.Row
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let person = row.person {
                    Avatar(person: person, size: 40)
                } else {
                    Image(systemName: "envelope")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 40, height: 40)
                        .background(Theme.surface2, in: Circle())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.body(17, weight: 700))
                Text(row.detail)
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.removable != nil {
                Button("Remove…", action: onRemove)
                    .font(.body(14, weight: 700))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Remove \(row.title)'s devices")
            }
            FamilyStatePill(state: row.state)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("family-\(row.title)")
    }
}

/// "Joined", "Invited", "No phone".
struct FamilyStatePill: View {
    let state: FamilyRoster.Row.State

    var body: some View {
        let (text, ink, fill): (String, Color, Color) = switch state {
        case .joined: ("Joined", Theme.goodInk, Theme.goodSoft)
        case .invited: ("Invited", Theme.accent, Theme.accentSoft)
        case .noPhone: ("No phone", Theme.muted, Theme.surface2)
        }
        Text(text)
            .font(.body(13, weight: 800))
            .foregroundStyle(ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(fill, in: Capsule())
            .fixedSize()
    }
}

/// A shared screen, or this device, on the family card.
private struct FamilyDeviceRow: View {
    let title: String
    let detail: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "house")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 40, height: 40)
                .background(Theme.surface2, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body(17, weight: 700))
                Text(detail)
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Change this device's name and role")
                    .accessibilityIdentifier("change-this-device")
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// The code to scan, on the wall (journey A3).
private struct JoinCodeWallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeWallSheet) private var close

    var body: some View {
        let name = model.household?.name ?? "the household"
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                SectionLabel("Scan to join")
                Text("Join \(name)")
                    .font(.display(30))
                    .multilineTextAlignment(.center)
            }
            JoinCodeCard(size: 280)
            Text(JoinCodePolicy.caption(name))
                .font(.body(16, weight: 500))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { close() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Remove Mia's iPhone?" (journey A6, the owner's side), worded once for the wall's sheet
/// and the phone's: what changes, and that the person and their history stay.
struct RemoveDevicesWords {
    let row: FamilyRoster.Row
    let householdName: String

    /// "Mia's iPhone", or "Mia's devices" for more than one.
    var what: String {
        row.devices.count == 1 ? row.devices[0].name : "\(row.title)'s devices"
    }

    /// "Mia · Mia's iPhone", over the title.
    var label: String { ([row.title] + row.devices.map(\.name)).joined(separator: " · ") }

    var title: String { "Remove \(what)?" }

    var body: String {
        "\(row.devices.count == 1 ? "It stops" : "They stop") seeing \(householdName). \(row.title) stays in the household with the same color and history, and can still pitch in on a shared screen. You can invite \(row.title) again any time."
    }

    static func failure(device: String) -> String {
        "Couldn't remove them. Check that this \(device) is online, then try again."
    }
}

/// The wall's sheet for removing someone's devices.
private struct RemoveDevicesSheet: View {
    let row: FamilyRoster.Row
    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(\.closeWallSheet) private var close
    @State private var failure: String?
    @State private var isRemoving = false

    var body: some View {
        let words = RemoveDevicesWords(row: row, householdName: model.household?.name ?? "the household")
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(words.label)
            Text(words.title).font(.display(30))
            Text(words.body)
                .font(.body(16, weight: 500))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let failure {
                Text(failure).font(.body(14, weight: 600)).foregroundStyle(Theme.accent)
            }
            HStack(spacing: 12) {
                Button("Remove", action: remove)
                    .buttonStyle(DestructiveButtonStyle())
                    .disabled(isRemoving)
                Button("Cancel") { close() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func remove() {
        guard let household = model.household, let participant = row.removable else { return }
        isRemoving = true
        Task {
            do {
                try await sharing.remove(participant, from: household)
                close()
            } catch {
                failure = RemoveDevicesWords.failure(device: "iPad")
                isRemoving = false
            }
        }
    }
}

/// A primary button for an action that can't be undone, in the atlas's brick red.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body(16, weight: 700))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .background(Theme.danger, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

/// This device's name and how it is used (the role step of A1, from Settings).
private struct ThisDeviceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device
    @Environment(\.closeWallSheet) private var close
    @State private var name = ""
    @State private var role: DeviceRole = .sharedScreen

    private var me: Person? {
        model.household.flatMap { device.me(in: $0.id) }.flatMap(model.people.person)
    }

    /// Compact enough to stay whole above the keyboard on the wall's 834 pt height.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This \(device.model)").font(.display(30))
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Name")
                TextField(device.name(me: me), text: $name)
                    .font(.body(18, weight: 600))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .fieldStyle()
                    .accessibilityIdentifier("device-name")
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("How it's used")
                DeviceRoleChoice(role: $role, model: device.model, compact: true)
            }
            HStack(spacing: 12) {
                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("save-device")
                Button("Cancel") { close() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .onAppear {
            name = device.customName ?? ""
            role = device.role
        }
    }

    private func save() {
        device.setName(name)
        device.setRole(role)
        close()
    }
}

/// "A shared screen" or "Just me" (journey A1's role step, also in Settings).
struct DeviceRoleChoice: View {
    @Binding var role: DeviceRole
    let model: String
    /// One line each, for a sheet.
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            option(.sharedScreen, emoji: "🖼️", title: "A shared screen",
                   detail: "On a wall or a counter. Anyone in the family can tap, so it asks who did something.")
            option(.personal, emoji: "🙋", title: "Just me",
                   detail: "Your own \(model). What you log is credited to you, like on your phone.")
        }
    }

    private func option(_ value: DeviceRole, emoji: String, title: String, detail: String) -> some View {
        let isOn = role == value
        return Button { role = value } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(emoji).font(.system(size: compact ? 22 : 28)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body(compact ? 16 : 19, weight: 700))
                    Text(detail)
                        .font(.body(compact ? 13.5 : 15, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 11 : 18)
            .background(isOn ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isOn ? Theme.accent : Theme.line, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("role-\(value.rawValue)")
    }
}
