import SwiftUI

/// A companion's page: the week at a glance, with the hero face, paw trail, diary and podium.
/// The mood meter, stat tiles, trail grid and podium are shared with the phone's week
/// (`CompanionWeekViews`), and so are the words (`CompanionWeekWords`).
struct CompanionScreen: View {
    var companionId: Companion.ID

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
            Text("\(report.name.possessive) week")
                .font(.display(40))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            Text(report.weekSummary)
                .font(.body(15))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let routine = report.primaryRoutine {
                Button {
                    CompanionCover.instantly {
                        request = CareLogRequest(companionId: companionId, routineId: routine.id, returnTitle: "Back to \(report.name)")
                    }
                } label: {
                    Label(CompanionWeekWords.logButton(CareWords(routine, species: report.companion.species)), systemImage: "pawprint.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] + 6 }
            }
        }
        .frame(minHeight: 56, alignment: .bottom)
    }
}

// MARK: - Hero

private struct HeroCard: View {
    @Environment(AppModel.self) private var model
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
            Text(report.aboutLine(calendar: model.calendar))
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
            if let week = report.primaryWeek {
                StatTileGrid(week: week)
            }
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
}

// MARK: - Paw trail

private struct PawTrailCard: View {
    let report: CompanionReport
    @Environment(\.openCareLog) private var openCareLog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Paw trail", meta: report.words.map(CompanionWeekWords.trailMeta) ?? "who did it, each slot")
            if let week = report.primaryWeek {
                PawTrailGrid(week: week, weekDays: report.weekDays, today: report.today, isEnabled: openCareLog != nil) { open($0, week: week) }
            }
        }
        .card(padding: 20)
    }

    /// A filled dot opens its walk to fix; an empty one logs it, for its own day when missed.
    private func open(_ tap: RoutineWeek.TrailTap, week: RoutineWeek) {
        switch tap {
        case let .edit(entry):
            openCareLog?(.edit(entry, companionId: report.id))
        case let .catchUp(missed):
            openCareLog?(.catchUp(companionId: report.id, routineId: week.routine.id, day: missed.day, slot: missed.slot.index))
        case .log:
            openCareLog?(CareLogRequest(companionId: report.id, routineId: week.routine.id))
        }
    }
}

// MARK: - Diary

private struct DiaryCard: View {
    let report: CompanionReport
    @Environment(CompanionStore.self) private var store
    @Environment(\.openCareLog) private var openCareLog
    /// Why a log couldn't be deleted, until it is read.
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: report.words.map(CompanionWeekWords.diaryTitle) ?? "Care diary",
                meta: CompanionWeekWords.captionsMeta(report.companion)
            )
            if report.diary.isEmpty && report.missed.isEmpty {
                Text(report.words.map(CompanionWeekWords.emptyDiary) ?? "Nothing logged this week yet.")
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
        .alert("That didn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// What was logged, with what wasn't in its place (every routine's), newest first.
    private var rows: [DiaryRow] {
        DiaryRow.rows(report.diary, missed: report.missed)
    }

    /// "Feed Yo-Yo · Dinner wasn't logged · Log it": tapping logs it for that day.
    private func missedRow(_ missed: MissedCare) -> some View {
        let calendar = store.snapshot.calendar
        let title = CompanionWeekWords.missedTitle(missed, companion: report.companion)
        return Button {
            openCareLog?(.catchUp(companionId: report.id, routineId: missed.routine.id, day: missed.day, slot: missed.slot.index))
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
                    Text(CompanionWeekWords.missedDetail(missed, calendar: calendar))
                        .font(.body(12, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(openCareLog == nil)
        .accessibilityLabel("\(title) wasn't logged, \(CompanionWeekWords.missedDay(missed, today: report.today, calendar: calendar))")
    }

    private func row(_ item: DiaryItem) -> some View {
        let snapshot = store.snapshot
        let entry = item.entry
        let nobody = snapshot.namesNobody(entry)
        let who = nobody ? CareLogWording.nobody : CaptionEngine.whoText(entry.people, names: snapshot.names)
        var head = Text(who).font(.body(13.5, weight: 700)).foregroundStyle(nobody ? Theme.accent : Theme.ink)
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
                if !store.deleteLog(id: entry.id) { deleteError = store.lastError ?? "Try again in a moment." }
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
                Text(CompanionWeekWords.when(entry.time, today: report.today, calendar: store.snapshot.calendar))
                    .font(.body(12, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Podium

private struct PodiumCard: View {
    let report: CompanionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: report.words.map(CompanionWeekWords.podiumTitle) ?? "Helper of the week")
            if report.leaderboard.isEmpty {
                Text(report.words.map(CompanionWeekWords.emptyPodium) ?? "The podium is wide open.")
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .multilineTextAlignment(.center)
            } else {
                PodiumView(standings: report.leaderboard)
            }
        }
        .card(padding: 20)
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
                            .background(milestone.tint.color(look: report.look, snapshot: store.snapshot).wash(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
}
