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

    private func end() {
        guard JoinCodePolicy.joinersKeepAccess, url != nil, let household = model.household else { return }
        let service = sharing.service
        Task { try? await service.endJoinCode(household) }
    }
}

extension JoinCodePolicy {
    /// What showing the code means, in plain words.
    static func caption(_ householdName: String) -> String {
        let joins = "Point an iPhone camera here. Anyone who scans joins \(householdName), so show it only to family."
        return joinersKeepAccess ? joins : joins + " The code keeps working after you close this; stop sharing from Invite to end it."
    }
}
