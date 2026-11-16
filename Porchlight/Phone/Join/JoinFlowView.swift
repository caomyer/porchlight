import GRDB
import SwiftUI

/// The invite that opened the app, answered on one screen at a time (journey A4): "Join?",
/// "Which one is you?", then "Bringing everything in". It covers whatever was showing
/// until it is done or declined, on a phone and on an iPad alike.
struct JoinFlowView: View {
    let invitation: HouseholdInvitation

    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing
    @Environment(DeviceSettings.self) private var device
    @Environment(ShareInbox.self) private var inbox
    @State private var flow: JoinFlow?

    var body: some View {
        // A ZStack, not a Group: an empty Group never appears, and the flow is made on appear.
        ZStack {
            Theme.background.ignoresSafeArea()
            if let flow {
                screen(flow)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Theme.ink)
        .onAppear {
            if flow?.invitation.id != invitation.id {
                flow = JoinFlow(invitation: invitation, database: model.database, sharing: sharing.service, device: device)
            }
        }
    }

    @ViewBuilder
    private func screen(_ flow: JoinFlow) -> some View {
        switch flow.step {
        case .preview, .joining:
            JoinPreview(flow: flow, onNotNow: done)
        case .who:
            WhoAreYouView(progress: (count: 2, index: 0), onPick: flow.pick, onAddMe: { try flow.addMe($0) })
        case let .bringingIn(id):
            BringingInView(householdId: id, onDone: done)
        }
    }

    private func done() {
        withAnimation(.easeInOut(duration: 0.3)) { inbox.invitation = nil }
    }
}

/// "Join The Lake House?": who invited you and whose iCloud it uses, before anything is accepted.
private struct JoinPreview: View {
    let flow: JoinFlow
    let onNotNow: () -> Void

    @Environment(DeviceSettings.self) private var device
    @PhoneMetric private var face: CGFloat = 84

    private var invitation: HouseholdInvitation { flow.invitation }
    private var owner: String { invitation.ownerName ?? "Someone" }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let failure = flow.failure {
                    StatusBanner(
                        tone: .warn, emoji: "📴", title: "Not joined yet", detail: failure,
                        action: ("Try again", { Task { await flow.join() } })
                    )
                    .accessibilityIdentifier("join-failed")
                }
                VStack(spacing: 12) {
                    Text("🏡")
                        .font(.system(size: face * 0.52))
                        .frame(width: face, height: face)
                        .background(Color(hex: 0xF3D9BE), in: Circle())
                        .accessibilityHidden(true)
                    Text("Join \(invitation.householdName)?")
                        .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(owner) invited you. You'll share walks, meals, chores and lists with the household.")
                        .phoneFont(.body, 14.5, weight: 500)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: 300)
                }
                .multilineTextAlignment(.center)
                .padding(.top, flow.failure == nil ? 44 : 8)
                VStack(spacing: 0) {
                    row("☁️", "Stored in \(invitation.ownerName.map { "\($0)'s" } ?? "their") iCloud", "Uses almost none of your storage")
                    RowDivider()
                    row("🔒", "Private to the household", "No account to create. Porchlight can't see it.")
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                VStack(spacing: 10) {
                    Button(flow.step == .joining ? "Joining…" : "Join") { Task { await flow.join() } }
                        .buttonStyle(PhoneButtonStyle())
                        .disabled(flow.step == .joining)
                        .accessibilityLabel(flow.step == .joining ? "Joining \(invitation.householdName)" : "Join \(invitation.householdName)")
                        .accessibilityIdentifier("join")
                    Button("Not now", action: onNotNow)
                        .buttonStyle(PhoneButtonStyle(kind: .ghost))
                        .disabled(flow.step == .joining)
                }
                .padding(.top, 28)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(_ emoji: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji).phoneFont(.body, 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                Text(detail)
                    .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// "Bringing everything in": the household is usable at once; its photos fill in behind.
/// What has arrived so far is counted from the database as it lands, never guessed.
private struct BringingInView: View {
    let householdId: Household.ID
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var counts = ArrivalCounts()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                StepDots(count: 2, index: 1)
                VStack(spacing: 12) {
                    Text("📦").font(.system(size: 46)).accessibilityHidden(true)
                    Text("Bringing everything in")
                        .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("You can start now. Photos fill in as they arrive.")
                        .phoneFont(.body, 14.5, weight: 500)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: 300)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 24)
                VStack(alignment: .leading, spacing: 14) {
                    line("People, chores, routines", counts.people > 0 ? "✓ Here" : "On the way")
                    line("Walks and meals", counts.logs == 1 ? "1 so far" : "\(counts.logs) so far")
                    VStack(alignment: .leading, spacing: 6) {
                        line("Meal photos", counts.photos == 0 ? "None yet" : "\(counts.thumbnails) of \(counts.photos)")
                        if counts.photos > 0 {
                            let fraction = Double(counts.thumbnails) / Double(counts.photos)
                            ProgressBar(fraction: fraction, fill: AnyShapeStyle(Theme.accent), height: 8, track: Theme.surface2)
                                .accessibilityElement()
                                .accessibilityLabel("Meal photos")
                                .accessibilityValue("\(Int((fraction * 100).rounded())) percent here")
                        }
                    }
                }
                .phoneCard()
                Button("Go to Today", action: onDone)
                    .buttonStyle(PhoneButtonStyle())
                    .padding(.top, 28)
                    .accessibilityIdentifier("go-to-today")
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task {
            let id = householdId
            let updates = ValueObservation.tracking { try ArrivalCounts.fetch($0, householdId: id) }.removeDuplicates()
            do {
                for try await latest in updates.values(in: model.database.writer) { counts = latest }
            } catch {}
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).phoneFont(.display, 15, weight: 600, relativeTo: .headline)
                Spacer(minLength: 8)
                Text(value).phoneFont(.body, 12, weight: 700, relativeTo: .caption).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).phoneFont(.display, 15, weight: 600, relativeTo: .headline)
                Text(value).phoneFont(.body, 12, weight: 700, relativeTo: .caption).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// How much of a joined household has arrived.
struct ArrivalCounts: Equatable, Sendable {
    var people = 0
    var logs = 0
    var photos = 0
    /// Photos whose thumbnail has arrived: they show everywhere a meal does.
    var thumbnails = 0

    static func fetch(_ db: Database, householdId: Household.ID) throws -> ArrivalCounts {
        func count(_ sql: String) throws -> Int {
            try Int.fetchOne(db, sql: sql, arguments: [householdId]) ?? 0
        }
        let entries = "SELECT journalEntry.id FROM journalEntry JOIN journal ON journal.id = journalEntry.journalId WHERE journal.householdId = ?"
        return ArrivalCounts(
            people: try count("SELECT COUNT(*) FROM person WHERE householdId = ?"),
            logs: try count("""
                SELECT COUNT(*) FROM careLog JOIN careRoutine ON careRoutine.id = careLog.careRoutineId
                JOIN companion ON companion.id = careRoutine.companionId WHERE companion.householdId = ?
                """) + count("SELECT COUNT(*) FROM (\(entries))"),
            photos: try count("SELECT COUNT(*) FROM journalEntryPhoto WHERE entryId IN (\(entries))"),
            thumbnails: try count("""
                SELECT COUNT(*) FROM journalEntryPhotoThumb JOIN journalEntryPhoto ON journalEntryPhoto.id = journalEntryPhotoThumb.photoId
                WHERE journalEntryPhoto.entryId IN (\(entries))
                """)
        )
    }
}

/// The small dots that say how far along a flow is.
struct StepDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { dot in
                Circle()
                    .fill(dot == index ? Theme.accent : Theme.line)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

/// "You're no longer in The Lake House" (journey A6): one calm screen, then the household
/// is gone from this device. What this device logged stays with the household.
struct RemovedHouseholdView: View {
    let removed: RemovedHousehold

    @Environment(AppModel.self) private var model
    @Environment(DeviceSettings.self) private var device

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("🚪").font(.system(size: 46)).accessibilityHidden(true)
                Text("You're no longer in \(removed.name)")
                    .phoneFont(.display, 26, weight: 600, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("\(removed.ownerName ?? "Its owner") removed this \(device.model) from the household, or stopped sharing it. What you logged stays with the household.")
                    .phoneFont(.body, 14.5, weight: 500)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 300)
                Button("OK") {
                    withAnimation(.easeInOut(duration: 0.3)) { model.forgetRemovedHousehold() }
                }
                .buttonStyle(PhoneButtonStyle())
                .padding(.top, 120)
                .accessibilityIdentifier("removed-ok")
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            .padding(.horizontal, 16)
            .padding(.top, 150)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }
}
