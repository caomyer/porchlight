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

/// The code a camera can scan to join the household: one private seat on the share, made
/// for this showing (docs/design/households.md, "The join code"). Whoever opens it first
/// takes the seat and joins as anyone invited by name does; the household is never open to
/// whoever has a link. Putting the code away removes the seat if nobody took it.
struct JoinCodeCard: View {
    var size: CGFloat = 260
    var compact = false

    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    /// Nil while the seat is on its way.
    @State private var seat: JoinSeat?
    @State private var state: SeatState = .waiting
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                ZStack {
                    if let seat, state == .waiting {
                        QRCode(text: seat.url.absoluteString, label: "Code to join \(model.household?.name ?? "the household")")
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: 0xF0E8DA))
                        Text(placeholder)
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
            Text(statusLine)
                .font(.body(compact ? 14 : 16, weight: 600))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("join-code-status")
        }
        .task(id: model.household?.id) { await run() }
        .onDisappear(perform: close)
    }

    private var placeholder: String {
        if let failure { return failure }
        if case .claimed = state { return "Taken ✓" }
        if state == .gone { return "This code was put away." }
        return "Getting the code ready…"
    }

    /// "Waiting for someone to scan", "Carol joined with this code".
    private var statusLine: String {
        switch state {
        case .waiting: return seat == nil ? " " : "One person can join with this code. It works until you close this."
        case let .claimed(userName): return "\(name(of: userName) ?? "Someone") joined with this code."
        case .gone: return "This code no longer works."
        }
    }

    /// The person behind an iCloud user, once their phone has said who they are.
    private func name(of userName: String?) -> String? {
        guard let userName else { return nil }
        let person = model.devices.first { $0.userName == userName && $0.owner != nil }?.owner
        return person.flatMap { id in model.everyone.first { $0.id == id }?.name }
    }

    /// Makes the seat, then follows it every few seconds until someone takes it.
    private func run() async {
        guard let household = model.household else { return }
        do {
            let seat = try await sharing.service.openSeat(household)
            self.seat = seat
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let state = try? await sharing.service.seatState(seat, in: household) else { continue }
                if state != self.state { self.state = state }
                if case .claimed = state { await sharing.refresh(household) }
            }
        } catch {
            failure = "The code needs iCloud. Check that this device is online, then try again."
        }
    }

    /// The seat goes when the code is put away, unless someone took it.
    private func close() {
        guard let seat, let household = model.household else { return }
        let service = sharing.service
        Task { try? await service.closeSeat(seat, in: household) }
    }
}

/// Where the join code is when this device can't make one: the one line that says so.
struct JoinCodeElsewhere: View {
    let text: String
    var compact = false

    var body: some View {
        Text(text)
            .font(.body(compact ? 13 : 14, weight: 600))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("join-code-elsewhere")
    }
}

/// The share's old public link, still open with people who joined through it: who they
/// are, and closing it, which removes them, only when the owner chooses.
struct PublicLinkNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @State private var confirming = false
    @State private var failure: String?

    var body: some View {
        let names = sharing.linkJoiners.map { $0.name ?? "Someone with the link" }
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("The household's old open link is still on")
                    .font(.body(15, weight: 700))
                Text("\(ListFormatter.localizedString(byJoining: names)) joined through it. Anyone with that link can still join. Close it, then invite \(names.count == 1 ? "them" : "them") by name.")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let failure {
                    Text(failure).font(.body(13, weight: 600)).foregroundStyle(Theme.danger)
                }
                Button("Close the link…") { confirming = true }
                    .font(.body(15, weight: 700))
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("close-public-link")
            }
            .padding(14)
            .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .confirmationDialog("Close the open link?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Close it and remove \(ListFormatter.localizedString(byJoining: names))", role: .destructive) {
                    Task { await close() }
                }
            } message: {
                Text("Closing the link removes \(ListFormatter.localizedString(byJoining: names)) from the household. You can invite \(names.count == 1 ? "them" : "them") again by name with Invite someone.")
            }
        }
    }

    private func close() async {
        guard let household = model.household else { return }
        do {
            try await sharing.closePublicLink(household)
        } catch {
            failure = "Couldn't close it. Check that this device is online, then try again."
        }
    }
}
