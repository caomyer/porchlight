import SwiftUI

/// "Sync details": what sync is doing on this device, folded away until someone asks
/// (docs/design/sync-icloud.md, "Seeing what sync does"). Shown in the wall's iCloud Sync
/// section and on the phone under its sync switch.
struct SyncDetails: View {
    @Environment(SyncController.self) private var sync
    @State private var isOpen = false
    var compact = false

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            if isOpen {
                SyncDetailsBody(compact: compact)
                    .padding(.top, 8)
            }
        } label: {
            Text("Sync details")
                .font(.body(compact ? 13 : 15, weight: 700))
                .foregroundStyle(Theme.muted)
        }
        .tint(Theme.muted)
        .accessibilityIdentifier("sync-details")
    }
}

private struct SyncDetailsBody: View {
    @Environment(SyncController.self) private var sync
    let compact: Bool
    @State private var counts: SyncController.Counts?
    @State private var checking = false

    var body: some View {
        let trace = sync.trace
        VStack(alignment: .leading, spacing: 4) {
            row("Role", trace.role.map { $0 == .sharedScreen ? "shared screen" : "personal" } ?? "-")
            row("In front", trace.isActive ? "yes (\(trace.activitySource))" : "no (\(trace.activitySource))")
            row("Online", trace.isOnline ? "yes" : "no")
            row("Engine", sync.engine?.isRunning == true || trace.engineRunning ? "running" : "stopped")
            row("iCloud account", trace.account)
            row("Last check", trace.lastCheck.map { "\(time($0.at)), \($0.outcome)\(trace.lastTrigger.map { " (\($0))" } ?? "")" } ?? "none yet")
                .accessibilityIdentifier("sync-details-last-check")
            row("Checks", "\(trace.checks), \(trace.failuresInRow) failed in a row")
                .accessibilityIdentifier("sync-details-checks")
            row("Last error", trace.lastError ?? "none")
            row("Brought in", trace.received ?? "-")
                .accessibilityIdentifier("sync-details-received")
            row("iCloud says", trace.lastProbe ?? "-")
            row("Engine restarts", "\(trace.restarts)")
            row("Next check", trace.nextCheckAt.map(time) ?? "-")
            row("Pushes", "\(trace.pushes)\(trace.lastPush.map { ", last at \(time($0))" } ?? "")")
            row("Push token", "\(trace.pushToken), asked \(trace.tokenRequests)×")
            row("Registered for pushes", trace.registeredForPushes ? "yes" : "no")
            row("Background App Refresh", trace.backgroundRefresh)
            row("Low Power Mode", trace.lowPowerMode ? "on" : "off")
            row("Not yet in iCloud", counts.map { "\($0.unconfirmed) rows" } ?? "…")
            row("Queued while paused", counts.map { "\($0.queued) changes" } ?? "…")
            Button {
                checking = true
                Task {
                    await sync.checkNow(.manual)
                    counts = await sync.counts()
                    checking = false
                }
            } label: {
                Text(checking ? "Checking…" : "Check now")
                    .font(.body(compact ? 13 : 15, weight: 700))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(checking)
            .padding(.top, 6)
            .accessibilityIdentifier("sync-check-now")
            Text("The log is in the app's data folder, \(SyncLog.fileName).")
                .font(.body(compact ? 11 : 12))
                .foregroundStyle(Theme.muted)
                .padding(.top, 2)
        }
        .task {
            sync.readPushState()
            counts = await sync.counts()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.body(compact ? 12 : 14, weight: 600))
        .accessibilityElement(children: .combine)
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
