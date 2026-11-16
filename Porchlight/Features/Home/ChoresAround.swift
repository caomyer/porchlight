import SwiftUI

// Chores outside the Pitch in screen: the Today card, the Today timeline and the
// calendar's "Pitch in" lane. Everything opens the same sheets as the board.

// MARK: - Sheets and check-off

extension View {
    /// The board's sheets (open a chore, who did it, edit), presentable from any screen.
    func choreSheets(_ sheet: Binding<ChoreSheet?>) -> some View {
        let width: CGFloat = if case .whoDidIt = sheet.wrappedValue { 460 } else { 640 }
        return wallSheet(item: sheet, width: width) { shown in
            switch shown {
            case .newChore: ChoreEditor(chore: nil)
            case let .editChore(chore): ChoreEditor(chore: chore)
            case let .whoDidIt(chore, day): WhoDidItSheet(chore: chore, day: day)
            case let .task(chore, day):
                ChoreTaskSheet(chore: chore, day: day) { withoutAnimation { sheet.wrappedValue = .editChore(chore) } }
            case let .editReward(reward): RewardEditor(reward: reward)
            }
        }
    }
}

enum ChoreCheck {
    /// Checks a chore off (or back on). Owned chores credit their owner; "Anyone" chores ask
    /// who did it, unless there is only one person to ask.
    @MainActor
    static func toggle(_ chore: Chore, on day: DayKey, store: HomeStore, people: [Person], ask: (ChoreSheet) -> Void) {
        let isDone = store.completion(of: chore, on: day) != nil
        if chore.ownerId == nil, !isDone {
            if people.count == 1 {
                store.toggle(chore, on: day, by: people.first?.id)
            } else {
                ask(.whoDidIt(chore, day))
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) { store.toggle(chore, on: day) }
        }
    }
}

// MARK: - A day's chores

/// One chore on one day, for the Today card and the calendar lane.
struct ChoreDayMark: Identifiable, Equatable {
    var chore: Chore
    var day: DayKey
    var completion: ChoreCompletion?

    var id: String { "\(chore.id)-\(day)" }
    var isDone: Bool { completion != nil }
}

enum ChoreDay {
    /// What the household did and had to do on `day`, done first in the order they were done,
    /// then what is still open in board order. Chores archived since still show what was done.
    static func marks(on day: DayKey, chores: [Chore], completions: [ChoreCompletion], calendar: Calendar) -> [ChoreDayMark] {
        let done = completions
            .filter { $0.dayKey == day }
            .sorted { ($0.completedAt, $0.id) < ($1.completedAt, $1.id) }
            .compactMap { completion in
                chores.first { $0.id == completion.choreId }.map { ChoreDayMark(chore: $0, day: day, completion: completion) }
            }
        let open = chores
            .filter { !$0.archived && WeekMark.mark(for: $0, on: day, completions: completions, calendar: calendar) == .open }
            .map { ChoreDayMark(chore: $0, day: day, completion: nil) }
        return done + open
    }

    /// When a completion happened, for placing it on a timeline: its check-off time when that
    /// falls on its day, or the end of the day when it was checked off later.
    static func time(of completion: ChoreCompletion, calendar: Calendar) -> Date {
        let start = completion.dayKey.startDate(in: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        if completion.completedAt >= start && completion.completedAt < end { return completion.completedAt }
        return end.addingTimeInterval(-60)
    }
}

extension HomeStore {
    func dayMarks(on day: DayKey) -> [ChoreDayMark] {
        ChoreDay.marks(on: day, chores: snapshot.chores, completions: snapshot.completions, calendar: calendar)
    }

    /// Chores done that day, as Today agenda rows: who did it, when, and the stars it earned.
    func timelineItems(for day: DayKey, people: [Person]) -> [TimelineItem] {
        dayMarks(on: day).compactMap { mark -> TimelineItem? in
            guard let completion = mark.completion else { return nil }
            let who = people.person(completion.personId)
            var subtitle = who.map { "\($0.name) pitched in" } ?? "Done"
            if completion.stars > 0 { subtitle += " · +\(completion.stars) " + (completion.stars == 1 ? "star" : "stars") }
            return TimelineItem(
                id: "chore-\(completion.id)",
                kind: .log,
                time: ChoreDay.time(of: completion, calendar: calendar),
                title: mark.chore.title,
                subtitle: subtitle,
                owner: completion.personId.map(Owner.person) ?? .everyone,
                leading: AnyView(ChoreEmojiTile(emoji: mark.chore.emoji, size: 32)),
                trailing: AnyView(OwnerAvatar(owner: completion.personId.map(Owner.person) ?? .everyone, people: people)),
                target: .chore(choreId: mark.chore.id, day: day)
            )
        }
    }

    /// The "Pitch in" lane under the week and day grids and inside month cells.
    func calendarLanes() -> [CalendarLane] {
        guard snapshot.chores.contains(where: { !$0.archived }) || !snapshot.completions.isEmpty else { return [] }
        return [
            CalendarLane(
                id: "chores",
                label: AnyView(
                    Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.everyone)
                        .accessibilityLabel("Pitch in")
                ),
                title: "chores",
                cell: { [self] day, style in AnyView(ChoreLaneCell(marks: dayMarks(on: day), today: today, style: style)) }
            ),
        ]
    }
}

// MARK: - Pieces

/// A chore's emoji on a soft square, like an event's mark.
struct ChoreEmojiTile: View {
    var emoji: String?
    var size: CGFloat = 32

    var body: some View {
        Text(emoji ?? "✅")
            .font(.system(size: size * 0.6))
            .frame(width: size, height: size)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A chore as a small round mark: the doer's color with a check when done, its emoji in an
/// outline when still to do (faint once the day has passed).
private struct ChoreDot: View {
    @Environment(AppModel.self) private var model
    let mark: ChoreDayMark
    let isPast: Bool
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let completion = mark.completion {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.45, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(completion.personId.map { model.color(for: .person($0)) } ?? Theme.everyone, in: Circle())
            } else {
                Text(mark.chore.emoji ?? "•")
                    .font(.system(size: size * 0.5))
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(Theme.muted.opacity(isPast ? 0.3 : 0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])))
                    .opacity(isPast ? 0.45 : 1)
            }
        }
    }
}

/// A lane cell: dots in the week, titled chips in the day, done checks in the month.
private struct ChoreLaneCell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openTimelineTarget) private var openTarget
    let marks: [ChoreDayMark]
    let today: DayKey
    let style: CalendarLane.Style

    var body: some View {
        switch style {
        case .week: week
        case .day: dayChips
        case .month: month
        }
    }

    /// As many dots as the column has room for, the rest as "+N".
    private var week: some View {
        ViewThatFits(in: .horizontal) {
            ForEach([6, 5, 4, 3, 2], id: \.self) { limit in
                weekRow(limit: limit)
            }
        }
        .padding(.vertical, 10)
    }

    private func weekRow(limit: Int) -> some View {
        let shown = marks.count > limit ? Array(marks.prefix(limit - 1)) : marks
        return HStack(spacing: 4) {
            ForEach(shown) { mark in
                Button { open(mark) } label: { ChoreDot(mark: mark, isPast: isPast(mark)) }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(label(mark))
            }
            if shown.count < marks.count {
                Text("+\(marks.count - shown.count)")
                    .font(.body(11, weight: 700))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
            }
        }
        .fixedSize()
    }

    private var dayChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(marks) { mark in
                Button { open(mark) } label: { chip(mark) }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(label(mark))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ mark: ChoreDayMark) -> some View {
        let color = mark.completion?.personId.map { model.color(for: .person($0)) } ?? Theme.everyone
        return HStack(spacing: 7) {
            ChoreDot(mark: mark, isPast: isPast(mark), size: 22)
            Text(mark.chore.title)
                .font(.body(13.5, weight: 700))
                .foregroundStyle(mark.isDone ? Theme.ink : Theme.muted)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(mark.isDone ? color.wash(0.16) : Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(mark.isDone ? .clear : Theme.line))
        .opacity(isPast(mark) ? 0.7 : 1)
    }

    @ViewBuilder
    private var month: some View {
        let done = marks.compactMap(\.completion)
        if !done.isEmpty {
            HStack(spacing: 2) {
                ForEach(Array(done.prefix(3).enumerated()), id: \.offset) { _, completion in
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(completion.personId.map { model.color(for: .person($0)) } ?? Theme.everyone)
                }
                if done.count > 3 {
                    Text("+\(done.count - 3)").font(.body(10.5, weight: 700)).foregroundStyle(Theme.muted)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(done.count == 1 ? "1 chore done" : "\(done.count) chores done")
        }
    }

    private func isPast(_ mark: ChoreDayMark) -> Bool { !mark.isDone && mark.day < today }

    private func open(_ mark: ChoreDayMark) {
        let id = mark.chore.id
        openTarget?(.chore(choreId: id, day: mark.day))
    }

    private func label(_ mark: ChoreDayMark) -> String {
        if let person = mark.completion?.personId.flatMap(model.person) { return "\(mark.chore.title), done by \(person.name)" }
        if mark.isDone { return "\(mark.chore.title), done" }
        return mark.day < today ? "\(mark.chore.title), not done" : "\(mark.chore.title), to do"
    }
}

// MARK: - Today card

/// "Pitch in" on Today: what is left to do today, one tap to check it off, and what got done.
/// Mirrors a companion's card: the board's rows, the same sheets, the stars this week.
struct PitchInTodayCard: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @State private var sheet: ChoreSheet?

    var body: some View {
        let board = store.board(people: model.people)
        let tasks = board.columns.flatMap(\.tasks)
        if !tasks.isEmpty {
            let open = tasks.filter { !$0.isDone }
            let done = tasks.filter(\.isDone).sorted { ($0.completion?.completedAt ?? .distantPast) < ($1.completion?.completedAt ?? .distantPast) }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Pitch in").font(.display(22))
                    Spacer()
                    Text(open.isEmpty ? "All done today" : "\(done.count) of \(tasks.count) done")
                        .font(.body(13, weight: 600))
                        .foregroundStyle(open.isEmpty ? Theme.accent : Theme.muted)
                }
                if !open.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(open) { task in
                            TodayChoreRow(task: task, today: store.today, calendar: store.calendar, onToggle: { toggle(task.chore) }, onOpen: { present(.task(task.chore, store.today)) })
                        }
                    }
                }
                if !done.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(done) { task in
                            Button { present(.task(task.chore, store.today)) } label: { DoneChip(task: task) }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel("\(task.chore.title), done")
                                .accessibilityHint("Opens it")
                        }
                    }
                }
                WeekStarsLine(totals: StarTotals.byPerson(store.snapshot.earnings, in: store.week))
            }
            .foregroundStyle(Theme.ink)
            .card()
            .choreSheets($sheet)
        }
    }

    private func present(_ next: ChoreSheet) {
        withoutAnimation { sheet = next }
    }

    private func toggle(_ chore: Chore) {
        ChoreCheck.toggle(chore, on: store.today, store: store, people: model.people, ask: present)
    }
}

/// An open chore on Today: tap the box to check it off, the row to open it.
private struct TodayChoreRow: View {
    @Environment(AppModel.self) private var model
    let task: ChoreBoard.Task
    let today: DayKey
    let calendar: Calendar
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        let color = model.color(for: task.chore.owner)
        HStack(spacing: 0) {
            Button(action: onToggle) {
                CheckBox(isOn: false, color: color, size: 26, cornerRadius: 8)
                    .padding(.leading, 12)
                    .padding(.trailing, 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(task.chore.title)
            .accessibilityValue("Not done")
            .accessibilityHint("Checks it off")
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    if let emoji = task.chore.emoji { Text(emoji).font(.system(size: 18)) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.chore.title)
                            .font(.body(15, weight: 700))
                            .lineLimit(1)
                        if let hint = hint {
                            Text(hint)
                                .font(.body(12, weight: 600))
                                .foregroundStyle(isOverdue ? Theme.accent : Theme.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    OwnerAvatar(owner: task.chore.owner, size: 24)
                    StarsTag(stars: task.chore.stars)
                }
                .padding(.vertical, 8)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Open \(task.chore.title)")
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }

    /// The time hint, or when a one-off is (over)due. Repeating chores due today say nothing more.
    private var hint: String? {
        if let hint = task.chore.timeHint, !hint.isEmpty { return hint }
        guard task.chore.recurrence.isOnce else { return nil }
        return ChoreSchedule.describe(task.chore, today: today, calendar: calendar)
    }

    private var isOverdue: Bool {
        task.chore.recurrence.isOnce && task.chore.anchor < today
    }
}

/// A chore done today, in the doer's color.
private struct DoneChip: View {
    @Environment(AppModel.self) private var model
    let task: ChoreBoard.Task

    var body: some View {
        let person = task.completion?.personId
        let color = person.map { model.color(for: .person($0)) } ?? Theme.everyone
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text([task.chore.emoji, task.chore.title].compactMap { $0 }.joined(separator: " "))
                .font(.body(13.5, weight: 700))
                .foregroundStyle(Theme.muted)
                .strikethrough(true, color: Theme.muted.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.wash(0.14), in: Capsule())
    }
}

/// "This week: J ★ 9 · M ★ 5", tying the card to Glow.
private struct WeekStarsLine: View {
    @Environment(AppModel.self) private var model
    let totals: [Person.ID: Int]

    var body: some View {
        if model.people.contains(where: { (totals[$0.id] ?? 0) > 0 }) {
            HStack(spacing: 12) {
                Text("THIS WEEK")
                    .font(.body(11, weight: 800))
                    .tracking(0.8)
                    .foregroundStyle(Theme.muted)
                ForEach(model.people) { person in
                    HStack(spacing: 5) {
                        Avatar(person: person, size: 22)
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.everyone)
                        Text("\(totals[person.id] ?? 0)")
                            .font(.body(13.5, weight: 700))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(person.name), \(totals[person.id] ?? 0) stars this week")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }
}
