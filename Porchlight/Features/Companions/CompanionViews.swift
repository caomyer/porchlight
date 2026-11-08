import SwiftUI

/// The small face used as the rail icon.
struct CompanionRailIcon: View {
    var companionId: Int64
    @Environment(CompanionStore.self) private var store

    var body: some View {
        if let report = store.report(for: companionId) {
            CompanionFace(look: report.look, expression: report.expression, size: 28)
        } else {
            Image(systemName: "pawprint").font(.system(size: 21, weight: .medium))
        }
    }
}

/// Companion cards for Today, one per companion.
struct CompanionTodayCards: View {
    @Environment(CompanionStore.self) private var store
    @State private var request: CareLogRequest?

    var body: some View {
        TimelineView(.everyMinute) { _ in
            // Re-evaluated every minute, so "Walked 1h ago" and slot states stay current.
            let now = CompanionClock.now()
            VStack(spacing: 16) {
                ForEach(store.companions) { summary in
                    if let report = store.report(for: summary.id, now: now) {
                        CompanionTodayCard(report: report) { routineId in
                            CompanionCover.instantly {
                                request = CareLogRequest(companionId: summary.id, routineId: routineId)
                            }
                        }
                    }
                }
            }
        }
        .careLogFlow($request)
        #if DEBUG
        .onAppear(perform: openDebugSheet)
        .fullScreenCover(isPresented: $showOnboardingPreview) {
            OnboardingStepPreview().statusBarHidden(true).persistentSystemOverlays(.hidden)
        }
        #endif
    }

    #if DEBUG
    @State private var showOnboardingPreview = false
    #endif

    #if DEBUG
    /// `-debugCompanionSheet log|celebrate|onboarding` opens a sheet for screenshots.
    private func openDebugSheet() {
        if UserDefaults.standard.string(forKey: "debugCompanionSheet") == "onboarding" {
            CompanionCover.instantly { showOnboardingPreview = true }
            return
        }
        guard let mode = UserDefaults.standard.string(forKey: "debugCompanionSheet"),
              mode == "log" || mode == "celebrate",
              let first = store.companions.first,
              let routine = store.report(for: first.id)?.primaryRoutine?.id else { return }
        CompanionCover.instantly {
            request = CareLogRequest(companionId: first.id, routineId: routine, celebrateOnly: mode == "celebrate")
        }
    }
    #endif
}

/// The pet card: face, mood, streak, today's slots and the big log button.
struct CompanionTodayCard: View {
    let report: CompanionReport
    let onLog: (Int64) -> Void

    @Environment(CompanionStore.self) private var store
    @Environment(\.openCompanion) private var openCompanion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CompanionFace(look: report.look, expression: report.expression, size: 66)
                    .frame(width: 78, height: 78)
                    .background(report.look.tint.wash(0.3), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.name)
                        .font(.display(26))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(moodLine)
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if report.streak > 1 {
                    StreakBadge(days: report.streak)
                }
            }
            if let primary = report.primary {
                SlotGrid(today: primary, report: report, style: .card)
                    .padding(.vertical, 14)
                if !report.others.isEmpty {
                    OtherRoutines(report: report, onLog: onLog)
                        .padding(.bottom, 14)
                }
                HStack(spacing: 10) {
                    Button { onLog(primary.id) } label: {
                        Label(primary.routine.kind.buttonTitle(name: report.name, title: primary.routine.title), systemImage: "pawprint.fill")
                            .lineLimit(1)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    if let openCompanion {
                        Button("See the week") { openCompanion(report.id) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            } else {
                Text("Add a care routine in Settings to track \(report.name)'s day.")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PetCardBackground(tint: report.look.tint))
        .foregroundStyle(Theme.ink)
    }

    private var moodLine: String {
        guard let routine = report.primaryRoutine else { return report.companion.species.label }
        guard let last = report.primary?.lastEntry else { return "Waiting for first \(report.noun)" }
        return "\(routine.kind.pastVerb) \(CareText.ago(last.time, now: report.now))"
    }
}

/// The card's warm wash: the companion's tint fading into paper.
struct PetCardBackground: View {
    var tint: Color

    var body: some View {
        ZStack {
            SurfaceShape(cornerRadius: Theme.radius)
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(LinearGradient(
                    stops: [.init(color: tint.wash(0.26), location: 0), .init(color: Theme.surface, location: 0.7)],
                    startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)
                ))
        }
    }
}

struct StreakBadge: View {
    var days: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill").font(.system(size: 13, weight: .semibold))
            Text("\(days)-day streak").font(.body(13, weight: 700))
        }
        .foregroundStyle(Theme.accent)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Today's slots for a routine as tiles, two per row.
struct SlotGrid: View {
    enum Style { case card, hero }

    let today: RoutineToday
    let report: CompanionReport
    var style: Style = .card

    @Environment(CompanionStore.self) private var store

    var body: some View {
        let calendar = store.snapshot.calendar
        let shortLabels = CareText.shortLabels(today.routine.effectiveWindows)
        Group {
            if today.slots.isEmpty {
                Text(nextDueText)
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(today.slots) { slot in
                        let turn = today.turns[slot.index].flatMap { store.snapshot.person($0)?.name }
                        SlotTile(
                            slot: slot,
                            title: style == .card ? slotTitle(slot) : shortLabels[safe: slot.index] ?? slot.window.label,
                            carers: slot.entry.map { Carers($0.people, snapshot: store.snapshot) },
                            pendingDetail: pendingDetail(slot, turn: turn),
                            doneDetail: slot.entry.map {
                                style == .card ? CareText.doneDetail($0, calendar: calendar) : CareText.time($0.time, calendar: calendar)
                            } ?? ""
                        )
                    }
                }
            }
        }
    }

    private func slotTitle(_ slot: CareSlot) -> String {
        slot.window.isAllDay ? today.routine.title : slot.window.label
    }

    private func pendingDetail(_ slot: CareSlot, turn: String?) -> String {
        if style == .hero { return turn ?? slot.window.rangeText }
        let when: String
        switch slot.state {
        case .due: when = "Due now"
        case .late: when = "Late"
        default: when = slot.window.isAllDay ? "Due today" : slot.window.rangeText
        }
        return [when, turn.map(CareText.turn)].compactMap { $0 }.joined(separator: " · ")
    }

    private var nextDueText: String {
        guard let last = today.lastEntry else { return "Not due today" }
        let calendar = store.snapshot.calendar
        let due = calendar.date(byAdding: .day, value: today.routine.everyDays, to: calendar.startOfDay(for: last.time)) ?? last.time
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: report.now), to: due).day ?? 0
        return "\(today.routine.kind.pastVerb) \(CareText.ago(last.time, now: report.now)) · next in \(days) \(days == 1 ? "day" : "days")"
    }
}

/// Compact chips for a companion's other routines ("🥣 Feed 1/2"); tap to log one.
struct OtherRoutines: View {
    let report: CompanionReport
    let onLog: (Int64) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(report.others) { other in
                Button { onLog(other.id) } label: {
                    HStack(spacing: 6) {
                        Text(other.routine.emoji)
                        Text(other.routine.title).font(.body(13.5, weight: 700))
                        Text(status(other))
                            .font(.body(12.5, weight: 700))
                            .foregroundStyle(other.isComplete ? Theme.good : Theme.muted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(other.isComplete ? Color.clear : Theme.line, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                    .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log \(other.routine.title)")
            }
        }
    }

    private func status(_ today: RoutineToday) -> String {
        if today.slots.isEmpty { return "not due" }
        if today.isComplete { return "✓" }
        return "\(today.doneCount)/\(today.slots.count)"
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Companions section inside Settings.
struct CompanionSettingsSection: View {
    var body: some View {
        CompanionSettingsList()
    }
}

/// Onboarding step: who else lives here.
struct CompanionOnboardingStep: View {
    var body: some View {
        CompanionOnboardingEditor()
    }
}

#if DEBUG
/// The onboarding step inside a stand-in for the onboarding chrome (same paddings),
/// so the step can be screenshotted on a set-up household.
private struct OnboardingStepPreview: View {
    var body: some View {
        HStack(spacing: 0) {
            Theme.rail.frame(width: 270)
            VStack(alignment: .leading, spacing: 22) {
                CompanionOnboardingStep()
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Continue") {}.buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.background)
        .ignoresSafeArea(.container, edges: .vertical)
    }
}
#endif
