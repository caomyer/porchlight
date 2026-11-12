import SwiftUI

/// A companion's page: the week at a glance, with the hero face, paw trail, diary and podium.
struct CompanionScreen: View {
    var companionId: Int64

    @Environment(CompanionStore.self) private var store
    @State private var request: CareLogRequest?

    var body: some View {
        TimelineView(.everyMinute) { _ in
            if let report = store.report(for: companionId, now: CompanionClock.now()) {
                content(report)
            } else {
                EmptyState(symbol: "pawprint", title: "Companion not found", message: "It may have been removed in Settings.")
                    .frame(maxHeight: .infinity)
            }
        }
        .careLogFlow($request)
    }

    private func content(_ report: CompanionReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(report)
            HStack(alignment: .top, spacing: 16) {
                HeroCard(report: report)
                    .frame(width: 300)
                VStack(spacing: 16) {
                    PawTrailCard(report: report)
                    DiaryCard(report: report)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    PodiumCard(report: report)
                    MilestonesCard(report: report)
                }
                .frame(width: 278)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, Theme.pagePadding + 2)
        .padding(.vertical, 22)
        .foregroundStyle(Theme.ink)
    }

    private func header(_ report: CompanionReport) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 18) {
            Text("\(report.name)'s week")
                .font(.display(40))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            Text(summary(report))
                .font(.body(15))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let routine = report.primaryRoutine, let routineId = routine.id {
                Button {
                    CompanionCover.instantly {
                        request = CareLogRequest(companionId: companionId, routineId: routineId, returnTitle: "Back to \(report.name)")
                    }
                } label: {
                    Label("Log a \(report.noun)", systemImage: "pawprint.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] + 6 }
            }
        }
        .frame(minHeight: 56, alignment: .bottom)
    }

    /// "13 walks · 5h 50m outside · 4 squirrels pursued, 0 caught".
    private func summary(_ report: CompanionReport) -> String {
        let stats = report.weekStats
        var parts = ["\(stats.count) \(stats.count == 1 ? report.noun : report.noun + "s")"]
        if stats.totalMinutes > 0 {
            let time = stats.totalMinutes >= 60 ? "\(stats.totalMinutes / 60)h \(stats.totalMinutes % 60)m" : "\(stats.totalMinutes) min"
            parts.append(report.primaryRoutine?.kind == .walk ? "\(time) outside" : time)
        }
        let squirrels = report.diary.filter { $0.entry.log.vibe == .squirrel }.count
        if squirrels > 0 {
            parts.append("\(squirrels) \(squirrels == 1 ? "squirrel" : "squirrels") pursued, 0 caught")
        } else if stats.stars > 0 {
            parts.append("\(stats.stars) stars earned")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Hero

private struct HeroCard: View {
    let report: CompanionReport

    var body: some View {
        VStack(spacing: 0) {
            CompanionFace(look: report.look, expression: report.expression, size: 184, bobs: true)
                .padding(.top, 10)
            Text(report.name)
                .font(.display(36))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 6)
            Text(aboutLine)
                .font(.body(13, weight: 600))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .padding(.top, 2)
            MoodMeter(report: report)
                .padding(.top, 16)
                .padding(.bottom, 4)
            if let primary = report.primary {
                SlotGrid(today: primary, report: report, style: .hero)
                    .padding(.vertical, 14)
            }
            Spacer(minLength: 0)
            StatTiles(report: report)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                SurfaceShape(cornerRadius: Theme.radius)
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(LinearGradient(
                        stops: [.init(color: report.look.tint.wash(0.32), location: 0), .init(color: Theme.surface, location: 0.62)],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
        }
    }

    /// "Toy poodle · 4 yrs".
    private var aboutLine: String {
        var parts: [String] = []
        let about = report.companion.about
        parts.append(about.isEmpty ? report.companion.species.label : about)
        if let birth = report.companion.birthDate {
            let years = Calendar.current.dateComponents([.year], from: birth, to: report.now).year ?? 0
            let months = Calendar.current.dateComponents([.month], from: birth, to: report.now).month ?? 0
            parts.append(years >= 1 ? "\(years) \(years == 1 ? "yr" : "yrs")" : "\(max(months, 1)) mo")
        }
        return parts.joined(separator: " · ")
    }
}

private struct MoodMeter: View {
    let report: CompanionReport

    var body: some View {
        let moods = CompanionPresets.moods(for: report.companion.species)
        VStack(spacing: 6) {
            HStack {
                Text(moods.first?.label ?? "")
                Spacer()
                Text(moods.last?.label ?? "")
            }
            .font(.body(11.5, weight: 700))
            .foregroundStyle(Theme.muted)
            GeometryReader { proxy in
                Capsule()
                    .fill(LinearGradient(
                        stops: [.init(color: Color(hex: 0xC9B8A6), location: 0), .init(color: report.look.tint, location: 0.55), .init(color: Theme.good, location: 1)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(height: 12)
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(Theme.surface)
                            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 3))
                            .frame(width: 24, height: 24)
                            .offset(x: proxy.size.width * (report.mood ?? 0.5) - 12)
                            .opacity(report.mood == nil ? 0.4 : 1)
                    }
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 24)
            Text(moodText)
                .font(.body(15, weight: 700))
                .padding(.top, 2)
        }
        .animation(.easeInOut(duration: 0.6), value: report.mood)
    }

    private var moodText: String {
        guard let mood = report.moodLabel else { return "Waiting for first \(report.noun)" }
        return "\(mood.emoji) \(mood.label)"
    }
}

private struct StatTiles: View {
    @Environment(CompanionStore.self) private var store
    let report: CompanionReport

    var body: some View {
        let stats = report.weekStats
        let routine = report.primaryRoutine
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tile(value: "\(report.streak)", unit: report.streak == 1 ? "day" : "days", label: "\(cadence) streak 🔥")
            if routine?.tracks(.duration) == true {
                tile(value: stats.averageMinutes.map(String.init) ?? "-", unit: "min", label: "avg \(report.noun)")
            } else {
                tile(value: "\(stats.count)", unit: nil, label: "\(report.noun)s this week")
            }
            tile(value: "\(stats.slotsOnTime)/\(stats.slotsSoFar)", unit: nil, label: "slots on time")
            if routine?.tracks(.pee) == true || routine?.tracks(.poo) == true {
                tile(value: businessValue(stats, routine: routine), unit: nil, label: "business log")
            } else {
                tile(value: "⭐\(stats.stars)", unit: nil, label: "stars this week")
            }
        }
    }

    private var cadence: String {
        guard let routine = report.primaryRoutine else { return "" }
        return routine.isDaily ? "\(routine.slotsPerDay)×/day" : routine.cadenceText(calendar: store.snapshot.calendar)
    }

    private func businessValue(_ stats: CareLogic.WeekStats, routine: CareRoutine?) -> String {
        [routine?.tracks(.pee) == true ? "💧\(stats.pee)" : nil, routine?.tracks(.poo) == true ? "💩\(stats.poo)" : nil]
            .compactMap { $0 }.joined(separator: " ")
    }

    private func tile(value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.display(24))
                if let unit { Text(unit).font(.display(15)) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(label)
                .font(.body(12, weight: 700))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }
}

// MARK: - Paw trail

private struct PawTrailCard: View {
    let report: CompanionReport
    @Environment(CompanionStore.self) private var store
    @Environment(\.openCareLog) private var openCareLog

    var body: some View {
        let calendar = store.snapshot.calendar
        let windows = report.primaryRoutine?.effectiveWindows ?? []
        let labels = CareText.shortLabels(windows)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Paw trail", meta: "who \(report.primaryRoutine?.kind == .walk ? "walked" : "did it"), each slot")
            Grid(horizontalSpacing: 0, verticalSpacing: 4) {
                GridRow {
                    Color.clear.frame(width: 44, height: 1)
                    ForEach(report.weekDays, id: \.self) { day in
                        VStack(spacing: 0) {
                            Text(weekdayLetter(day, calendar: calendar))
                                .font(.body(12, weight: 700))
                                .foregroundStyle(day == report.today ? Theme.accent : Theme.muted)
                            Text(dayNumber(day, calendar: calendar))
                                .font(.display(15))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                ForEach(windows.indices, id: \.self) { index in
                    GridRow {
                        Text(labels[index].uppercased())
                            .font(.body(11, weight: 700))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .frame(width: 44, alignment: .leading)
                        ForEach(report.weekDays.indices, id: \.self) { dayIndex in
                            cell(report.trail[dayIndex].first { $0.index == index }, on: report.weekDays[dayIndex])
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .card(padding: 20)
    }

    /// A filled dot opens its walk to fix; an empty one logs it, for its own day when missed.
    @ViewBuilder
    private func cell(_ slot: CareSlot?, on day: DayKey) -> some View {
        if let slot, let entry = slot.entry {
            dotButton(slot, on: day, status: CaptionEngine.whoText(entry.people, names: store.snapshot.names)) {
                .edit(entry, companionId: report.id)
            } label: {
                PawDot(carers: Carers(entry.people, snapshot: store.snapshot), size: 36, content: .initial)
            }
        } else if let slot, slot.isPendingToday || slot.state == .missed, let routineId = report.primaryRoutine?.id {
            dotButton(slot, on: day, status: slot.state == .missed ? "missed" : "to do") {
                slot.state == .missed
                    ? .catchUp(companionId: report.id, routineId: routineId, day: day, slot: slot.index)
                    : CareLogRequest(companionId: report.id, routineId: routineId)
            } label: {
                PawDot(carers: nil, size: 36)
                    .opacity(slot.state == .missed ? 0.45 : 1)
            }
        } else {
            Circle().fill(Theme.surface2.opacity(0.6)).frame(width: 12, height: 12).frame(width: 36, height: 36)
        }
    }

    private func dotButton<Dot: View>(
        _ slot: CareSlot, on day: DayKey, status: String,
        request: () -> CareLogRequest, @ViewBuilder label: () -> Dot
    ) -> some View {
        let request = request()
        let name = report.primaryRoutine.map { CareCatchUp.slotName(slot.window, of: $0) } ?? slot.window.label
        let weekday = day.formatted(.dateTime.weekday(.wide), calendar: store.snapshot.calendar)
        return Button { openCareLog?(request) } label: {
            label()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(openCareLog == nil)
        .accessibilityLabel("\(name.prefix(1).uppercased() + name.dropFirst()), \(weekday), \(status)")
    }

    private func weekdayLetter(_ day: DayKey, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: day.startDate(in: calendar))
        return calendar.veryShortWeekdaySymbols[weekday - 1]
    }

    private func dayNumber(_ day: DayKey, calendar: Calendar) -> String {
        "\(calendar.component(.day, from: day.startDate(in: calendar)))"
    }
}

// MARK: - Diary

private struct DiaryCard: View {
    let report: CompanionReport
    @Environment(CompanionStore.self) private var store
    @Environment(\.openCareLog) private var openCareLog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: "\(report.noun.prefix(1).uppercased() + report.noun.dropFirst()) diary",
                meta: report.companion.captionTone == .off ? nil : "captions: \(report.companion.captionTone.label)"
            )
            if report.diary.isEmpty && report.missed.isEmpty {
                Text("Nothing logged this week yet. The first \(report.noun) starts the story.")
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(rows) { row in
                            switch row {
                            case let .logged(item): self.row(item)
                            case let .missed(missed): missedRow(missed)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card(padding: 20)
    }

    /// What was logged, with what wasn't in its place, newest first.
    private enum Row: Identifiable {
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

    private var rows: [Row] {
        (report.diary.map(Row.logged) + report.missed.map(Row.missed)).sorted { $0.time > $1.time }
    }

    /// "Feed Yo-Yo · Dinner wasn't logged · Log it": tapping logs it for that day.
    private func missedRow(_ missed: MissedCare) -> some View {
        let calendar = store.snapshot.calendar
        let title = CompanionTimeline.expectedTitle(missed.slot, routine: missed.routine, companion: report.companion)
        let dayName = missed.day == report.today.adding(days: -1, calendar: calendar)
            ? "yesterday"
            : missed.day.formatted(.dateTime.weekday(.wide), calendar: calendar)
        return Button {
            if let routineId = missed.routine.id {
                openCareLog?(.catchUp(companionId: report.id, routineId: routineId, day: missed.day, slot: missed.slot.index))
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(missed.routine.emoji)
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Theme.muted.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])))
                VStack(alignment: .leading, spacing: 2) {
                    (Text("\(title) wasn't logged").foregroundStyle(Theme.muted)
                        + Text("  Log it").foregroundStyle(Theme.accent).font(.body(13.5, weight: 800)))
                        .font(.body(13.5, weight: 600))
                    Text(([missed.day.formatted(.dateTime.weekday(.abbreviated), calendar: calendar)]
                        + (missed.slot.window.isAllDay ? [] : ["usually \(missed.slot.window.rangeText)"])).joined(separator: " · "))
                        .font(.body(12, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(openCareLog == nil)
        .accessibilityLabel("\(title) wasn't logged, \(dayName)")
    }

    private func row(_ item: DiaryItem) -> some View {
        let snapshot = store.snapshot
        let entry = item.entry
        let who = CaptionEngine.whoText(entry.people, names: snapshot.names)
        var head = Text(who).font(.body(13.5, weight: 700))
        if let minutes = entry.log.durationMinutes {
            head = head + Text(" · \(minutes) min").font(.body(13.5))
        }
        let business = CareText.business(entry.log, spaced: true)
        if !business.isEmpty { head = head + Text("  \(business)").font(.body(12)) }
        let story = entry.log.note ?? item.caption
        return Button { openCareLog?(.edit(entry, companionId: report.id)) } label: {
            diaryRow(entry, head: head, story: story)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete this log", systemImage: "trash", role: .destructive) {
                store.deleteLog(id: entry.id)
            }
        }
    }

    private func diaryRow(_ entry: CareEntry, head: Text, story: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CarerAvatar(carers: Carers(entry.people, snapshot: store.snapshot))
            VStack(alignment: .leading, spacing: 2) {
                head
                if let story {
                    Text(story).font(.body(13.5)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
                Text(whenText(entry.time))
                    .font(.body(12, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// "Today 8:12am", "Fri 6:40pm".
    private func whenText(_ date: Date) -> String {
        let calendar = store.snapshot.calendar
        let time = CareText.timeWithPeriod(date, calendar: calendar)
        if DayKey(date, calendar: calendar) == report.today { return "Today \(time)" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return "\(formatter.string(from: date)) \(time)"
    }
}

// MARK: - Podium

private struct PodiumCard: View {
    let report: CompanionReport
    @Environment(CompanionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "\(report.primaryRoutine?.kind.agentNoun ?? "Helper") of the week")
            let top = Array(report.leaderboard.prefix(3))
            if top.isEmpty {
                Text("No \(report.noun)s yet this week. The podium is wide open.")
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .multilineTextAlignment(.center)
            } else {
                let order = podiumOrder(top)
                let maxCount = top.map(\.count).max() ?? 1
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(order, id: \.carer) { standing in
                        pod(standing, isWinner: standing == top[0] && (top.count == 1 || top[1].count < top[0].count), maxCount: maxCount)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 176, alignment: .bottom)
            }
        }
        .card(padding: 20)
    }

    /// Second, first, third, like a real podium.
    private func podiumOrder(_ top: [CareLogic.Standing]) -> [CareLogic.Standing] {
        switch top.count {
        case 3: [top[1], top[0], top[2]]
        case 2: [top[1], top[0]]
        default: top
        }
    }

    private func pod(_ standing: CareLogic.Standing, isWinner: Bool, maxCount: Int) -> some View {
        let (carers, name) = describe(standing.carer)
        let color = carers.isTogether ? Theme.everyone : carers.single
        return VStack(spacing: 6) {
            if isWinner {
                Text("👑").font(.system(size: 22)).padding(.bottom, -8)
            }
            CarerAvatar(carers: carers, size: 46)
            Text("\(standing.count)")
                .font(.display(22))
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(height: max(30, 88 * CGFloat(standing.count) / CGFloat(max(maxCount, 1))))
                .background(color.wash(0.28, over: Theme.surface2), in: UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 12, style: .continuous))
            Text(name)
                .font(.body(12, weight: 700))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .frame(width: 76)
    }

    private func describe(_ carer: CareLogic.Carer) -> (Carers, String) {
        switch carer {
        case let .person(id):
            let person = store.snapshot.person(id)
            return (Carers([id], snapshot: store.snapshot), person?.name ?? "Someone")
        case .together:
            return (Carers(colors: [Theme.everyone, Theme.everyone], initials: [CareText.heart]), "Together")
        }
    }
}

// MARK: - Milestones

private struct MilestonesCard: View {
    let report: CompanionReport
    @Environment(CompanionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Little milestones")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(report.milestones) { milestone in
                    HStack(spacing: 12) {
                        Text(milestone.emoji)
                            .font(.system(size: 24))
                            .frame(width: 52, height: 52)
                            .background(tint(milestone.tint).wash(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(milestone.title)
                                .font(.body(14.5, weight: 700))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(milestone.detail)
                                .font(.body(12.5, weight: 600))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card(padding: 20)
    }

    private func tint(_ tint: Milestone.Tint) -> Color {
        switch tint {
        case .companion: report.look.tint
        case let .person(id): store.snapshot.person(id)?.color.color ?? Theme.everyone
        case .together: Theme.everyone
        }
    }
}
