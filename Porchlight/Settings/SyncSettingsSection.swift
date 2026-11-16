import SwiftUI

/// The iCloud sync switch for this iPad, with one line on how sync is doing.
///
/// Sync problems are only ever told here, never on Today: the wall keeps working on its
/// own whatever iCloud does.
struct SyncSettingsSection: View {
    @Environment(SyncController.self) private var sync
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("iCloud sync")
            if sync.needsDecision {
                decision
            } else {
                Toggle(isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync with iCloud")
                            .font(.body(17, weight: 600))
                        Text(sync.status.summary)
                            .font(.body(14))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.good)
                .disabled(!sync.isAvailable)
                .card(padding: 16)
                .frame(maxWidth: 980)
            }
        }
    }

    private var decision: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("A different iCloud account signed in")
                    .font(.body(17, weight: 600))
                Text(sync.status.summary)
                    .font(.body(14))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 12) {
                Button("Keep it here without sync") { sync.keepDataWithoutSync() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Remove it from this iPad") { confirmRemove = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
        .frame(maxWidth: 980)
        .confirmationDialog("Remove the household from this iPad?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove from this iPad", role: .destructive) {
                Task { await sync.removeDataFromDevice() }
            }
        } message: {
            Text("Everything here goes: people, companions, meals, chores and photos. It stays in the earlier account's iCloud. Then this iPad syncs with the account signed in now.")
        }
    }
}

extension SyncStatus {
    /// One plain line for Settings.
    var summary: String {
        switch self {
        case let .off(reason):
            #if DEBUG
            switch reason {
            case .switchedOff: "Off. Everything stays on this iPad."
            case .sampleData: "Off: sample data never syncs."
            case .noEntitlement: "Off: this build isn't signed for iCloud."
            case let .failed(message): "Off: sync couldn't start. \(message)"
            }
            #else
            if case .failed = reason { "Off: sync couldn't start. Everything stays on this iPad." } else { "Off. Everything stays on this iPad." }
            #endif
        case .noAccount:
            "This iPad isn't signed in to iCloud. Sign in in the Settings app to sync again; everything stays here meanwhile."
        case let .upToDate(lastSynced):
            "Up to date\(Self.lastSyncedText(lastSynced))."
        case .syncing:
            "Syncing…"
        case let .waiting(lastSynced):
            "Waiting for iCloud\(Self.lastSyncedText(lastSynced)). Changes keep saving on this iPad."
        case .iCloudFull:
            "Paused: iCloud is full. Changes keep saving on this iPad until there's room."
        case .needsDecision:
            "The household on this iPad belongs to the earlier account, so nothing syncs until you choose what to do with it."
        }
    }

    private static func lastSyncedText(_ date: Date?) -> String {
        guard let date else { return "" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return ", last synced at \(time)" }
        return ", last synced \(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
    }
}
