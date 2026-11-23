import SwiftUI

/// "Sync details": what sync is doing on this device, folded away until someone asks
/// (docs/design/sync-icloud.md, "Seeing what sync does"). Shown in the wall's iCloud Sync
/// section and on the phone under its sync switch.
struct SyncDetails: View {
    @Environment(SyncController.self) private var sync
    @State private var isOpen = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Sync details")
                        .font(.body(compact ? 13 : 15, weight: 700))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "open" : "closed")
            .accessibilityIdentifier("sync-details")
            if isOpen {
                SyncDetailsBody(compact: compact)
                    .padding(.top, 4)
            }
        }
    }
}

private struct SyncDetailsBody: View {
    @Environment(SyncController.self) private var sync
    @Environment(CalendarStore.self) private var calendarStore
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
            // What iCloud refused and this device kept: read aloud, it is the evidence.
            row("Held for a parent", trace.deferrals.heldLine())
                .accessibilityIdentifier("sync-details-held")
            row("Turned down, sent again", trace.deferrals.resentLine())
                .accessibilityIdentifier("sync-details-resent")
            // Not sync, but the one other thing this device fetches from Apple on its own.
            row("Handwriting fonts", HandCompanionFonts.shared.summary)
                .accessibilityIdentifier("sync-details-hand-fonts")
            // How fresh each device keeps the shared calendar (docs/design/calendar-shared.md,
            // "How fresh"): one line per device, to read the numbers off real devices.
            let lines = CalendarFreshness.detailLines(
                calendarStore.shared, now: CompanionClock.now(), calendar: calendarStore.calendar, checkedHere: calendarStore.lastChecked
            )
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row("Calendars, \(line.device)", line.line)
            }
            .accessibilityIdentifier("sync-details-calendars")
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
