import SQLiteData
import SwiftUI

/// Inviting someone: iOS's own sharing sheet over the household's share, which sends the
/// invite by Messages, Mail or a link and manages who has access (as in Notes and
/// Reminders). Participants may read and write; invites go only to the people they're sent to.
struct InviteSheet: View {
    let invite: HouseholdInvite
    /// Puts the sheet away; the system's sheet puts itself away.
    let onDone: () -> Void

    var body: some View {
        switch invite {
        case let .cloud(record, engine):
            CloudSharingView(sharedRecord: record, availablePermissions: [.allowReadWrite, .allowPrivate], syncEngine: engine)
                .ignoresSafeArea()
        case let .standIn(name):
            InviteStandIn(householdName: name, onDone: onDone)
        }
    }
}

/// What the fake shows where iOS's sharing sheet would open, for tests and screenshots.
private struct InviteStandIn: View {
    let householdName: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Join \(householdName) on Porchlight")
                .font(.display(24))
            Text("iOS's sharing sheet opens here, to send the invite by Messages, Mail or a link, and to see who has joined.")
                .font(.body(15, weight: 500))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("invite-done")
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .presentationDetents([.medium])
    }
}

/// The code a camera can scan to join the household on screen. Showing it lets anyone with
/// the household's link join; putting it away stops that, unless joiners would lose access
/// (`JoinCodePolicy`).
struct JoinCodeCard: View {
    var size: CGFloat = 260

    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    /// Nil while the link is on its way.
    @State private var url: URL?
    @State private var failure: String?

    private var householdName: String { model.household?.name ?? "the household" }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if let url {
                    QRCode(text: url.absoluteString, label: "Code to join \(householdName)")
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0xF0E8DA))
                    Text(failure ?? "Getting the code ready…")
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Color(hex: 0x867A6E))
                        .multilineTextAlignment(.center)
                        .padding(20)
                }
            }
            .frame(width: size, height: size)
        }
        .padding(18)
        // A code reads best dark on white, whatever the look around it.
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: 0x3C_2814).opacity(0.1), radius: 8, x: 0, y: 4)
        .task(id: model.household?.id) { await load() }
        .onDisappear(perform: end)
    }

    private func load() async {
        guard let household = model.household else { return }
        do {
            url = try await sharing.service.joinCode(household)
        } catch {
            failure = "The code needs iCloud. Check that this device is online, then try again."
        }
    }

    /// Putting the code away closes the link only when nobody joined through it: closing
    /// it would remove them (`JoinCodePolicy`). Asked again here, so someone who scanned a
    /// moment ago is counted.
    private func end() {
        guard url != nil, let household = model.household else { return }
        let service = sharing.service
        Task { await JoinCodePolicy.putAway(service, household: household) }
    }
}

extension JoinCodePolicy {
    /// The code was put away: the link closes only when nobody joined through it. Nil when
    /// who joined couldn't be read, and the link is left as it was (never removing anyone
    /// by not knowing).
    @MainActor
    @discardableResult
    static func putAway(_ service: any HouseholdSharing, household: Household) async -> Closing? {
        guard let joiners = try? await service.linkJoiners(of: household) else {
            SyncLog.shared.write("join code: left on, couldn't read who joined")
            return nil
        }
        let closing = closing(linkJoiners: joiners)
        switch closing {
        case .closeLink:
            try? await service.endJoinCode(household)
        case let .keepOpen(names):
            SyncLog.shared.write("join code: left on, \(names.count) joined through it")
        }
        return closing
    }
}

/// Under the code: who joined with it and keeps access only while it stays on, and
/// turning it off, after saying who that removes.
struct JoinCodeJoiners: View {
    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    var compact = false
    @State private var joiners: [HouseholdParticipant] = []
    @State private var confirming = false
    @State private var turnedOff = false

    var body: some View {
        let names = joiners.map { $0.name ?? "Someone with the code" }
        VStack(spacing: 10) {
            if turnedOff {
                Text("The code is off. Anyone who joined with it was removed.")
            } else if let text = JoinCodePolicy.keptOpenText(names) {
                Text(text)
                Button("Turn off the code…") { confirming = true }
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("join-code-turn-off")
            }
        }
        .font(.body(compact ? 13 : 15, weight: 600))
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Turn off the code?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Turn off and remove \(ListFormatter.localizedString(byJoining: names))", role: .destructive) {
                Task { await turnOff() }
            }
        } message: {
            Text(JoinCodePolicy.turnOffQuestion(names))
        }
        // Someone may scan while it shows; look again every few seconds.
        .task(id: model.household?.id) {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func load() async {
        guard let household = model.household,
              let found = try? await sharing.service.linkJoiners(of: household) else { return }
        if found != joiners { joiners = found }
    }

    private func turnOff() async {
        guard let household = model.household else { return }
        do {
            try await sharing.service.endJoinCode(household)
            turnedOff = true
            joiners = []
            await sharing.refresh(household)
        } catch {
            SyncLog.shared.write("join code: turning off failed: \(error.syncDescription)")
        }
    }
}

extension JoinCodePolicy {
    /// What showing the code means, in plain words.
    static func caption(_ householdName: String) -> String {
        "Point an iPhone camera here. Anyone who scans joins \(householdName), so show it only to family. Anyone who joins with it keeps access while the code stays on."
    }
}
