import SwiftUI

/// Pitch in on the phone: what is mine, what is open for anyone, and everyone's, from
/// the wall's board. Pure parts are in `PocketPitchInLogic`.
struct PocketPitchIn: View {
    enum Segment: String, CaseIterable, Identifiable {
        case yours = "Yours"
        case open = "Open"
        case everyone = "Everyone"
        var id: String { rawValue }
    }

    let logging: PocketLogging

    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var home
    @Environment(\.me) private var me
    @State private var segment: Segment = .yours
    @State private var adding = false

    var body: some View {
        let board = home.board(people: model.people)
        let week = PocketPitchInLogic.weekProgress(chores: home.activeChores, completions: home.snapshot.completions, week: home.week, calendar: home.calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("This week · \(week.done) of \(week.total) done")
                        .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                    Text("Pitch in")
                        .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                }
                Picker("Show", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch segment {
                case .yours: yours(board)
                case .open: open(board)
                case .everyone: everyone(board)
                }
                Button("+ Add a chore") { adding = true }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
                    .accessibilityIdentifier("add-chore")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .sheet(isPresented: $adding) {
            PhoneEditorSheet { ChoreEditor(chore: nil, newOwner: me?.id) }
        }
    }

    // MARK: Segments

    @ViewBuilder
    private func yours(_ board: ChoreBoard) -> some View {
        if let me {
            let mine = PocketToday.chores(board, me: me.id).mine
            card(title: "Today", meta: mine.isEmpty ? "Nothing of yours" : "\(mine.filter(\.isDone).count) of \(mine.count) done", tasks: mine, kind: .mine)
            let done = PocketPitchInLogic.doneThisWeek(by: me.id, chores: home.snapshot.chores, completions: home.snapshot.completions, week: home.week, before: home.today)
            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    PhoneCardHeader(title: "Done this week", meta: StarWords.earned(done.map(\.completion.stars).reduce(0, +)))
                    rows(done.map { ChoreBoard.Task(chore: $0.chore, completion: $0.completion) }, kind: .mine, dayLabels: true)
                }
                .phoneCard()
            }
        } else {
            everyone(board)
        }
    }

    @ViewBuilder
    private func open(_ board: ChoreBoard) -> some View {
        let open = board.columns.first { $0.owner == .everyone }?.tasks.filter { !$0.isDone } ?? []
        if open.isEmpty {
            StatusBanner(tone: .good, emoji: "🙌", title: "Nothing open for anyone", detail: "Every shared chore today is done.")
        } else {
            card(title: "Anyone can take", meta: "\(open.count) open", tasks: open, kind: .anyone)
        }
    }

    @ViewBuilder
    private func everyone(_ board: ChoreBoard) -> some View {
        ForEach(board.columns) { column in
            let title: String = switch column.owner {
            case let .person(id): id == me?.id ? "You" : model.person(id)?.name ?? "Someone"
            case .everyone: "Anyone"
            }
            if !column.tasks.isEmpty {
                card(title: title, meta: "\(column.tasks.filter(\.isDone).count) of \(column.tasks.count) done", tasks: column.tasks, kind: kind(for: column.owner))
            }
        }
    }

    // MARK: Pieces

    /// Mine to check off, anyone's to take, or someone else's to see.
    private func kind(for owner: Owner) -> PhoneChoreRow.Kind {
        switch owner {
        case .everyone: .anyone
        case let .person(id): id == me?.id ? .mine : .theirs
        }
    }

    private func card(title: String, meta: String, tasks: [ChoreBoard.Task], kind: PhoneChoreRow.Kind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PhoneCardHeader(title: title, meta: meta)
            rows(tasks, kind: kind, dayLabels: false)
        }
        .phoneCard()
    }

    private func rows(_ tasks: [ChoreBoard.Task], kind: PhoneChoreRow.Kind, dayLabels: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                if index > 0 { RowDivider() }
                PhoneChoreRow(
                    kind: kind, emoji: task.chore.emoji, title: task.chore.title,
                    subtitle: dayLabels
                        ? task.completion.map { $0.dayKey.formatted(.dateTime.weekday(.abbreviated), calendar: home.calendar) }
                        : PocketChoreWords.subtitle(task, today: home.today, calendar: home.calendar, people: model.everyone, me: me?.id),
                    stars: task.chore.stars, isDone: task.isDone,
                    doneBy: task.completion?.personId.flatMap(model.person),
                    lateFrom: dayLabels ? nil : ChoreSchedule.lateFrom(task.chore, isDone: task.isDone, today: home.today, calendar: home.calendar)
                ) { logging.complete(task.chore, by: me?.id) }
            }
        }
    }
}

/// The counts and lists behind Pitch in on the phone. Pure, covered by PocketPitchInTests.
enum PocketPitchInLogic {
    /// How many of this week's chore days are done, over the whole week (today's and the
    /// days still to come count toward the total), from the wall's week marks.
    static func weekProgress(chores: [Chore], completions: [ChoreCompletion], week: HomeWeek, calendar: Calendar) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for chore in chores where !chore.archived {
            for day in week.days {
                switch WeekMark.mark(for: chore, on: day, completions: completions, calendar: calendar) {
                case .none: continue
                case .open: total += 1
                case .done: total += 1; done += 1
                }
            }
        }
        return (done, total)
    }

    /// What `person` did earlier this week, newest first. Today's are on the Today card.
    static func doneThisWeek(by person: Person.ID, chores: [Chore], completions: [ChoreCompletion], week: HomeWeek, before today: DayKey) -> [(chore: Chore, completion: ChoreCompletion)] {
        let byId = Dictionary(chores.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return completions
            .filter { $0.personId == person && week.contains($0.dayKey) && $0.dayKey < today }
            .sorted { ($0.dayKey, $0.completedAt) > ($1.dayKey, $1.completedAt) }
            .compactMap { completion in byId[completion.choreId].map { ($0, completion) } }
    }
}
