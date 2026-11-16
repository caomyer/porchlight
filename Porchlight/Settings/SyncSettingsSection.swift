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
                VStack(alignment: .leading, spacing: 14) {
                    if sync.status == .iCloudFull {
                        paused
                    }
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
                    .accessibilityIdentifier("sync-switch")
                }
                .card(padding: 16)
                .frame(maxWidth: 980)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sync-settings")
    }

    /// A full iCloud is the owner's to fix, from any device on the account (journey D3).
    private var paused: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync is paused: iCloud is full")
                        .font(.body(16, weight: 700))
                    Text("Everything still works on this iPad. Changes send as soon as there's room.")
                        .font(.body(14, weight: 600))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(Theme.warnInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Free up space, or choose a bigger iCloud plan, on any iPhone or iPad signed in to this account. Nothing is lost while it's paused.")
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
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
            "Paused until there's room in iCloud."
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
