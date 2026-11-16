import SwiftUI

/// A companion's week on the phone: the wall's companion page, condensed into one
/// column. The same report (`CompanionReport`) feeds both, so the trail, diary, mood,
/// milestones and walker of the week say the same thing on the wall and here.
struct PocketCompanionWeek: View {
    let companionId: Companion.ID

    @Environment(CompanionStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.colorScheme) private var scheme
    @State private var catchUp: PocketCatchUpSheet.Request?
    let logging: PocketLogging

    var body: some View {
        TimelineView(.everyMinute) { _ in
            if let report = store.report(for: companionId, now: CompanionClock.now()) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        hero(report)
                        if let routine = report.primaryRoutine {
                            PocketPawTrail(report: report, routine: routine)
                        }
                        diary(report)
                        walkers(report)
                        milestones(report)
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
        .sheet(item: $catchUp) { PocketCatchUpSheet(request: $0, logging: logging) }
    }

    // MARK: Hero

    private func hero(_ report: CompanionReport) -> some View {
        HStack(spacing: 12) {
            CompanionBadge(report, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(report.name)'s week")
                    .phoneFont(.display, 24, weight: 600, relativeTo: .title)
                    .accessibilityAddTraits(.isHeader)
                Text(report.weekStats.count == 0 ? "The first week together" : report.weekSummary)
                    .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
                if let mood = report.moodLabel {
                    Text("\(mood.emoji) \(mood.label)")
                        .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .phoneCard(tint: report.look.tint)
    }

    // MARK: Diary

    private enum DiaryRow: Identifiable {
        case logged(DiaryItem)
        case missed(MissedCare)

        var id: String {
            switch self {
            case let .logged(item): "log-\(item.id)"
            case let .missed(missed): "missed-\(missed.id)"
            }
        }

        var time: Date {
            switch self {
            case let .logged(item): item.entry.time
            case let .missed(missed): missed.usual
            }
        }
    }

    private func diary(_ report: CompanionReport) -> some View {
        let rows = (report.diary.map(DiaryRow.logged) + report.missed.map(DiaryRow.missed)).sorted { $0.time > $1.time }
        let noun = PocketCareWords.capitalized(report.noun)
        return VStack(alignment: .leading, spacing: 4) {
            PhoneCardHeader(
                title: "\(noun) diary",
                meta: report.companion.captionTone == .off ? nil : "captions: \(report.companion.captionTone.label.lowercased())"
            )
            if rows.isEmpty {
                Text("Nothing logged this week yet. The first \(report.noun) starts the story.")
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
        var head = PocketToday.who(entry.people, me: nil, names: snapshot.names)
        if let minutes = entry.log.durationMinutes { head += " · \(minutes) min" }
        let business = CareText.business(entry.log)
        if !business.isEmpty { head += " \(business)" }
        return HStack(alignment: .top, spacing: 10) {
            CarerAvatar(carers: Carers(entry.people, snapshot: snapshot), size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(head).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                if let story = entry.log.note ?? item.caption {
                    Text(story)
                        .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
                        .foregroundStyle(Theme.ink)
                }
                Text(PocketWeekWords.when(entry.time, today: report.today, calendar: snapshot.calendar))
                    .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func missedRow(_ missed: MissedCare, report: CompanionReport) -> some View {
        let calendar = store.snapshot.calendar
        let name = PocketCareWords.capitalized(CareCatchUp.slotName(missed.slot.window, of: missed.routine))
        let day = PocketCareWords.dayWord(missed.day, today: report.today, calendar: calendar)
        return Button { catchUp = PocketCatchUpSheet.Request(companionId: report.id, missed: missed) } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(missed.routine.emoji)
                    .phoneFont(.body, 12)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Theme.muted.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(name) wasn't logged")
                        .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                        .foregroundStyle(Theme.muted)
                    Text(PocketCareWords.capitalized(day))
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Log it")
                    .phoneFont(.body, 12.5, weight: 800, relativeTo: .footnote)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) wasn't logged \(day)")
        .accessibilityHint("Log it")
    }

    // MARK: Walker of the week

    @ViewBuilder
    private func walkers(_ report: CompanionReport) -> some View {
        let title = "\(report.primaryRoutine?.kind.agentNoun ?? "Helper") of the week"
        let standings = Array(report.leaderboard.prefix(4))
        VStack(alignment: .leading, spacing: 8) {
            PhoneCardHeader(title: title)
            if standings.isEmpty {
                Text("No \(report.noun)s yet this week. Wide open.")
                    .phoneFont(.body, 13, weight: 600, relativeTo: .subheadline)
                    .foregroundStyle(Theme.muted)
            }
            let most = standings.map(\.count).max() ?? 1
            ForEach(standings, id: \.carer) { standing in
                standingRow(standing, most: most, crowned: standing == standings.first && (standings.count == 1 || standings[1].count < standing.count))
            }
        }
        .phoneCard()
    }

    private func standingRow(_ standing: CareLogic.Standing, most: Int, crowned: Bool) -> some View {
        let snapshot = store.snapshot
        let (carers, name): (Carers, String) = switch standing.carer {
        case let .person(id): (Carers([id], snapshot: snapshot), id == me?.id ? "You" : snapshot.person(id)?.name ?? "Someone")
        case .together: (Carers(colors: [Theme.everyone, Theme.everyone], initials: [CareText.heart]), "Together")
        }
        let color = carers.isTogether ? Theme.everyone : carers.single
        return HStack(spacing: 8) {
            CarerAvatar(carers: carers, size: 24)
            Text(name + (crowned ? " 👑" : ""))
                .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
                .frame(minWidth: 70, alignment: .leading)
            ProgressBar(fraction: Double(standing.count) / Double(max(most, 1)), fill: AnyShapeStyle(color), height: 8, track: Theme.surface2)
            Text("\(standing.count)")
                .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
                .monospacedDigit()
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(standing.count)")
    }

    // MARK: Milestones

    private func milestones(_ report: CompanionReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PhoneCardHeader(title: "Little milestones")
            ForEach(report.milestones) { milestone in
                HStack(spacing: 10) {
                    Text(milestone.emoji)
                        .phoneFont(.body, 20)
                        .frame(width: 40, height: 40)
                        .background(tint(milestone.tint, report: report).wash(0.15, over: Theme.surface, in: scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func tint(_ tint: Milestone.Tint, report: CompanionReport) -> Color {
        switch tint {
        case .companion: report.look.tint
        case let .person(id): store.snapshot.person(id)?.color.color ?? Theme.everyone
        case .together: Theme.everyone
        }
    }
}

/// Paw trail at phone size: a ring per slot and day, in the color of who did it, a dashed
/// ring for one not done (accented while it's still waiting today). Never a zero.
private struct PocketPawTrail: View {
    let report: CompanionReport
    let routine: CareRoutine

    @Environment(CompanionStore.self) private var store
    @PhoneMetric private var ring: CGFloat = 24

    var body: some View {
        let calendar = store.snapshot.calendar
        let windows = routine.effectiveWindows
        let labels = CareText.shortLabels(windows)
        VStack(alignment: .leading, spacing: 8) {
            PhoneCardHeader(title: "Paw trail", meta: "who \(routine.kind.pastVerb.lowercased()), each slot")
            Grid(horizontalSpacing: 2, verticalSpacing: 6) {
                GridRow {
                    Color.clear.frame(width: 34, height: 1)
                    ForEach(report.weekDays, id: \.self) { day in
                        Text(PocketWeekWords.letter(day, calendar: calendar))
                            .phoneFont(.body, 10.5, weight: 700, relativeTo: .caption2)
                            .foregroundStyle(day == report.today ? Theme.accent : Theme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(windows.indices, id: \.self) { index in
                    GridRow {
                        Text(labels[index])
                            .phoneFont(.body, 10.5, weight: 700, relativeTo: .caption2)
                            .foregroundStyle(Theme.muted)
                            .frame(width: 34, alignment: .leading)
                        ForEach(report.weekDays.indices, id: \.self) { dayIndex in
                            cell(report.trail[dayIndex].first { $0.index == index }, day: report.weekDays[dayIndex], window: windows[index])
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .phoneCard()
    }

    @ViewBuilder
    private func cell(_ slot: CareSlot?, day: DayKey, window: CareWindow) -> some View {
        let calendar = store.snapshot.calendar
        let weekday = day.formatted(.dateTime.weekday(.wide), calendar: calendar)
        let name = PocketCareWords.capitalized(CareCatchUp.slotName(window, of: routine))
        if let entry = slot?.entry {
            PawDot(carers: Carers(entry.people, snapshot: store.snapshot), size: ring, content: .initial)
                .accessibilityLabel("\(name), \(weekday), \(CaptionEngine.whoText(entry.people, names: store.snapshot.names))")
        } else {
            let waiting = slot?.isPendingToday == true
            Circle()
                .strokeBorder(waiting ? Theme.accent : Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                .frame(width: ring, height: ring)
                .overlay {
                    if waiting {
                        Text(routine.emoji).font(.system(size: ring * 0.45))
                    }
                }
                .accessibilityLabel("\(name), \(weekday), \(waiting ? "to do" : slot?.state == .missed ? "missed" : "not due")")
        }
    }
}

enum PocketWeekWords {
    /// "M", "T": a day's letter in the trail.
    static func letter(_ day: DayKey, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: day.startDate(in: calendar))
        return calendar.veryShortWeekdaySymbols[weekday - 1]
    }

    /// "Today 8:12am", "Fri 6:40pm".
    static func when(_ date: Date, today: DayKey, calendar: Calendar) -> String {
        let time = CareText.timeWithPeriod(date, calendar: calendar)
        let day = DayKey(date, calendar: calendar)
        if day == today { return "Today \(time)" }
        return day.formatted(.dateTime.weekday(.abbreviated), calendar: calendar) + " \(time)"
    }
}
