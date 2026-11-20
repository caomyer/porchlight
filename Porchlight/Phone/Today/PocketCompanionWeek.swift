import SwiftUI

/// A companion's week on the phone: the wall's companion page, for a phone held in one
/// hand. The same report (`CompanionReport`), the same pieces (`CompanionWeekViews`: the
/// mood meter, stat tiles, paw trail and podium) and the same words (`CompanionWeekWords`),
/// in one column. The wall shows the primary routine's week; the phone shows each
/// routine's, picked at the top, so meals and water have their trail and diary too.
struct PocketCompanionWeek: View {
    let companionId: Companion.ID
    let logging: PocketLogging

    @Environment(CompanionStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(ToastCenter.self) private var toasts
    @State private var catchUp: PocketCatchUpSheet.Request?
    /// A new log, or a logged one opened to fix, as on the wall's companion page.
    @State private var careSheet: PocketCareSheet.Request?
    /// The routine whose week is shown: the primary one until another is picked.
    @State private var routineId: CareRoutine.ID?

    var body: some View {
        TimelineView(.everyMinute) { _ in
            if let report = store.report(for: companionId, now: CompanionClock.now()) {
                let week = report.week(of: routineId) ?? report.primaryWeek
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        hero(report)
                        if let week {
                            if report.weeks.count > 1 {
                                RoutineTabs(weeks: report.weeks, selected: week.id) { routineId = $0 }
                            }
                            numbers(week, report: report)
                            trail(week, report: report)
                            diary(week, report: report)
                            podium(week)
                            milestones(week, report: report)
                        } else {
                            Text("Add a care routine in Household to track \(report.name.possessive) day.")
                                .phoneFont(.body, 14, weight: 600, relativeTo: .subheadline)
                                .foregroundStyle(Theme.muted)
                                .phoneCard()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            } else {
                Text("This companion was removed.")
                    .phoneFont(.body, 15, weight: 600)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .sheet(item: $catchUp, onDismiss: toasts.showPending) { PocketCatchUpSheet(request: $0, logging: logging.inSheet) }
        .sheet(item: $careSheet, onDismiss: toasts.showPending) { PocketCareSheet(request: $0, logging: logging.inSheet) }
    }

    // MARK: Opening a log

    /// A new log for this routine, credited to me to start with.
    private func newLog(_ routine: CareRoutine) {
        careSheet = PocketCareSheet.Request(companionId: companionId, routineId: routine.id, people: me.map { [$0.id] } ?? [], logId: nil)
    }

    /// A slot that was never logged, from the trail or the diary, is logged for its own
    /// day. Every way the page catches up goes through here.
    private func logMissed(_ missed: MissedCare) {
        catchUp = PocketCatchUpSheet.Request(companionId: companionId, missed: missed)
    }

    /// What a tap on the trail does, as on the wall.
    private func open(_ tap: RoutineWeek.TrailTap, week: RoutineWeek) {
        switch tap {
        case let .edit(entry): careSheet = .edit(entry, companionId: companionId)
        case let .catchUp(missed): logMissed(missed)
        case .log: newLog(week.routine)
        }
    }

    // MARK: Hero

    private func hero(_ report: CompanionReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AdaptiveRow(spacing: 12) {
                CompanionBadge(report, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(report.name.possessive) week")
                        .phoneFont(.display, 24, weight: 600, relativeTo: .title)
                        .accessibilityAddTraits(.isHeader)
                    Text(report.aboutLine(calendar: store.snapshot.calendar))
                        .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                    Text(report.weekStats.count == 0 ? "The first week together" : report.weekSummary)
                        .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            MoodMeter(report: report)
        }
        .phoneCard(tint: report.look.tint)
    }

    // MARK: Numbers

    /// The week's four numbers and the page's own log button, as in the wall's hero.
    private func numbers(_ week: RoutineWeek, report: CompanionReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatTileGrid(week: week)
            Button { newLog(week.routine) } label: {
                Label(CompanionWeekWords.logButton(week.routine), systemImage: "pawprint.fill")
            }
            .buttonStyle(PhoneButtonStyle())
            .accessibilityIdentifier("log-routine")
        }
        .phoneCard()
    }

    // MARK: Paw trail

    private func trail(_ week: RoutineWeek, report: CompanionReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PhoneCardHeader(title: "Paw trail", meta: CompanionWeekWords.trailMeta(week.routine))
            // Seven columns can't grow without end: the letters stop growing at the
            // extra-large size, and every slot is also a row in the diary below.
            PawTrailGrid(week: week, weekDays: report.weekDays, today: report.today, metrics: .phone) { open($0, week: week) }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .phoneCard()
    }

    // MARK: Diary

    private func diary(_ week: RoutineWeek, report: CompanionReport) -> some View {
        let rows = week.rows
        return VStack(alignment: .leading, spacing: 4) {
            PhoneCardHeader(title: CompanionWeekWords.diaryTitle(week.routine), meta: CompanionWeekWords.captionsMeta(report.companion))
            if rows.isEmpty {
                Text(CompanionWeekWords.emptyDiary(week.routine))
                    .phoneFont(.body, 13, weight: 600, relativeTo: .subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 7)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider() }
                    switch row {
                    case let .logged(item): loggedRow(item, report: report)
                    case let .missed(missed): missedRow(missed, report: report)
                    }
                }
            }
        }
        .phoneCard()
    }

    private func loggedRow(_ item: DiaryItem, report: CompanionReport) -> some View {
        let entry = item.entry
        let snapshot = store.snapshot
        var head = CaptionEngine.whoText(entry.people, names: snapshot.names)
        if let minutes = entry.log.durationMinutes { head += " · \(minutes) min" }
        let business = CareText.business(entry.log, spaced: true)
        if !business.isEmpty { head += "  \(business)" }
        return Button { careSheet = .edit(entry, companionId: report.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                CarerAvatar(carers: Carers(entry.people, snapshot: snapshot), size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(head).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                    if let story = entry.log.note ?? item.caption {
                        Text(story)
                            .phoneFont(.body, 13, weight: 500, relativeTo: .footnote)
                            .foregroundStyle(Theme.ink)
                    }
                    Text(CompanionWeekWords.when(entry.time, today: report.today, calendar: snapshot.calendar))
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint(CareLogWording.editSubtitle)
    }

    /// "Morning walk wasn't logged · Mon · usually 6-10am · Log it", in the wall's words.
    private func missedRow(_ missed: MissedCare, report: CompanionReport) -> some View {
        let calendar = store.snapshot.calendar
        let title = CompanionWeekWords.missedTitle(missed, companion: report.companion)
        return Button { logMissed(missed) } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(missed.routine.emoji)
                    .phoneFont(.body, 12)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Theme.muted.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])))
                AdaptiveRow(spacing: 10, alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(title) wasn't logged")
                            .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                            .foregroundStyle(Theme.muted)
                        Text(CompanionWeekWords.missedDetail(missed, calendar: calendar))
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Log it")
                        .phoneFont(.body, 13, weight: 800, relativeTo: .footnote)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) wasn't logged, \(CompanionWeekWords.missedDay(missed, today: report.today, calendar: calendar))")
        .accessibilityHint("Log it")
    }

    // MARK: Podium

    private func podium(_ week: RoutineWeek) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PhoneCardHeader(title: CompanionWeekWords.podiumTitle(week.routine))
            if week.leaderboard.isEmpty {
                Text(CompanionWeekWords.emptyPodium(week.routine))
                    .phoneFont(.body, 13, weight: 600, relativeTo: .subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .multilineTextAlignment(.center)
            } else if typeSize.isAccessibilitySize {
                // At accessibility sizes the pods' names would be cut off: the same top
                // three as bars, the leader crowned.
                let most = week.leaderboard.map(\.count).max() ?? 1
                let leader = CareLogic.leader(week.leaderboard)
                ForEach(Array(week.leaderboard.prefix(3)), id: \.carer) { standing in
                    standingRow(standing, most: most, crowned: standing == leader)
                }
            } else {
                PodiumView(standings: week.leaderboard)
            }
        }
        .phoneCard()
    }

    private func standingRow(_ standing: CareLogic.Standing, most: Int, crowned: Bool) -> some View {
        let (carers, name) = CareLogic.describe(standing.carer, snapshot: store.snapshot)
        return PersonBarRow(
            name: name + (crowned ? " 👑" : ""), count: standing.count,
            fraction: Double(standing.count) / Double(max(most, 1)), color: carers.isTogether ? Theme.everyone : carers.single
        ) {
            CarerAvatar(carers: carers, size: 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(standing.count)\(crowned ? ", first" : "")")
    }

    // MARK: Milestones

    private func milestones(_ week: RoutineWeek, report: CompanionReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PhoneCardHeader(title: "Little milestones")
            ForEach(week.milestones) { milestone in
                HStack(spacing: 10) {
                    Text(milestone.emoji)
                        .phoneFont(.body, 20)
                        .frame(width: 40, height: 40)
                        .background(
                            milestone.tint.color(look: report.look, snapshot: store.snapshot).wash(0.15, over: Theme.surface, in: scheme),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(milestone.title).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                        Text(milestone.detail)
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .phoneCard()
    }
}

/// Which routine's week the page shows: "🦮 Walk", "🥣 Feed". A segmented row that
/// wraps into a column at accessibility sizes, rather than cutting its words off.
private struct RoutineTabs: View {
    let weeks: [RoutineWeek]
    let selected: CareRoutine.ID
    let pick: (CareRoutine.ID) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(weeks) { week in
                tab(week)
            }
        }
        .padding(4)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tab(_ week: RoutineWeek) -> some View {
        let isOn = week.id == selected
        return Button { pick(week.id) } label: {
            Text("\(week.routine.emoji) \(week.routine.title)")
                .phoneFont(.body, 14, weight: isOn ? 800 : 700, relativeTo: .subheadline)
                .foregroundStyle(isOn ? Theme.ink : Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.surface)
                            .shadow(color: Color(hex: 0x3C_2814).opacity(0.1), radius: 2, x: 0, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(week.routine.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("routine-\(week.routine.title)")
    }
}
