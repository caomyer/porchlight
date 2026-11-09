import SwiftUI

/// What the Pitch in screen has open on top of the board.
enum ChoreSheet: Identifiable {
    case newChore
    case editChore(Chore)
    case whoDidIt(Chore, DayKey)
    /// A chore on a day: who did it, undo, edit, archive or delete.
    case task(Chore, DayKey)
    case editReward(Reward)

    var id: String {
        switch self {
        case .newChore: "new"
        case let .editChore(chore): "edit-\(chore.id ?? -1)"
        case let .whoDidIt(chore, day): "who-\(chore.id ?? -1)-\(day)"
        case let .task(chore, day): "task-\(chore.id ?? -1)-\(day)"
        case let .editReward(reward): "reward-\(reward.id ?? -1)"
        }
    }
}

/// "Pitch in": what the household does for each other, a column per person plus
/// "Anyone" for shared chores and companion care, or the week overview. Every row works
/// the same way: tap its box to check it off, tap the row to open it and fix it.
struct ChoresScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @Environment(CompanionStore.self) private var companions
    @State private var showWeek = ChoresScreen.debugShowsWeek
    @State private var sheet: ChoreSheet?
    @State private var careRequest: CareLogRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeHeader(
                title: "Pitch in",
                subtitle: store.today.formatted(.dateTime.weekday(.wide), calendar: store.calendar)
                    + (showWeek ? " · this week at a glance" : " · tap a box to check it off, a row to open it")
            ) {
                HeaderChip(title: "This week", isSelected: showWeek) {
                    withAnimation(.easeInOut(duration: 0.25)) { showWeek.toggle() }
                }
                HeaderChip(title: "New chore", symbol: "plus") { present(.newChore) }
            }
            if showWeek {
                ChoreWeekView(onToggle: toggle, onOpen: { present(.task($0, $1)) })
                    .transition(.opacity)
            } else {
                TimelineView(.everyMinute) { _ in
                    ChoreBoardView(
                        board: store.board(people: model.people, care: companions.careTasks(now: CompanionClock.now())),
                        onToggle: { toggle($0, store.today) },
                        onOpenCare: openCare,
                        present: present
                    )
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .wallSheet(item: $sheet, width: sheetWidth) { sheet in
            switch sheet {
            case .newChore: ChoreEditor(chore: nil)
            case let .editChore(chore): ChoreEditor(chore: chore)
            case let .whoDidIt(chore, day): WhoDidItSheet(chore: chore, day: day)
            case let .task(chore, day): ChoreTaskSheet(chore: chore, day: day) { present(.editChore(chore)) }
            case let .editReward(reward): RewardEditor(reward: reward)
            }
        }
        .careLogFlow($careRequest)
        #if DEBUG
        .task { openDebugSheet() }
        .fullScreenCover(isPresented: $debugAmbient) {
            AmbientView(extraPhotoURLs: debugPhotos, onWake: { debugAmbient = false }, glance: debugGlance)
        }
        #endif
    }

    #if DEBUG
    /// `-homeSheet ambient` shows Ambient mode over the board (the wall's own "photos" start is not wired up);
    /// `ambientPhoto` also feeds it a rendered test photo and a sample glance card.
    @State private var debugAmbient = ["ambient", "ambientPhoto"].contains(UserDefaults.standard.string(forKey: "homeSheet"))

    private var debugPhotos: [URL] {
        guard UserDefaults.standard.string(forKey: "homeSheet") == "ambientPhoto" else { return [] }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-debug.jpg")
        let renderer = ImageRenderer(content: LandscapePainting(palette: .morning).frame(width: 1600, height: 1200))
        if let image = renderer.uiImage, let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: url)
        }
        return [url]
    }

    private var debugGlance: AnyView? {
        guard UserDefaults.standard.string(forKey: "homeSheet") == "ambientPhoto" else { return nil }
        return AnyView(AmbientGlassCard {
            VStack(alignment: .leading, spacing: 3) {
                Text("NEXT UP").font(.body(11.5, weight: 800)).tracking(0.9).opacity(0.7)
                Text("🧗 Climbing gym").font(.body(17, weight: 700))
                Text("10:00 - 11:30").font(.body(13.5)).opacity(0.8)
            }
        })
    }
    #endif

    private var sheetWidth: CGFloat {
        if case .whoDidIt = sheet { return 460 }
        return 640
    }

    private func present(_ sheet: ChoreSheet) {
        withoutAnimation { self.sheet = sheet }
    }

    /// Care is logged (or fixed) with the companion's own sheet: who, when, and details.
    private func openCare(_ task: CareTask) {
        guard let routineId = task.routine.id else { return }
        let request = task.slot.entry.map { CareLogRequest.edit($0, companionId: task.companionId) }
            ?? CareLogRequest(companionId: task.companionId, routineId: routineId)
        var shown = request
        shown.returnTitle = "Back to Pitch in"
        CompanionCover.instantly { careRequest = shown }
    }

    /// Checks a chore off. Owned chores credit their owner; "Anyone" chores ask who did it.
    private func toggle(_ chore: Chore, _ day: DayKey) {
        let isDone = store.snapshot.completions.contains { $0.choreId == chore.id && $0.dayKey == day }
        if chore.ownerId == nil, !isDone {
            if model.people.count == 1 {
                store.toggle(chore, on: day, by: model.people.first?.id)
            } else {
                present(.whoDidIt(chore, day))
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) { store.toggle(chore, on: day) }
        }
    }

    private static var debugShowsWeek: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "homeSheet") == "week"
        #else
        false
        #endif
    }

    #if DEBUG
    /// `-homeSheet newChore|editChore|whoDidIt|editReward` opens a sheet for screenshots.
    private func openDebugSheet() {
        guard sheet == nil, let name = UserDefaults.standard.string(forKey: "homeSheet") else { return }
        let chores = store.activeChores
        switch name {
        case "newChore": present(.newChore)
        case "editChore": if let chore = chores.first { present(.editChore(chore)) }
        case "whoDidIt": if let chore = chores.first(where: { $0.ownerId == nil }) { present(.whoDidIt(chore, store.today)) }
        case "editReward": if let reward = store.snapshot.rewards.first { present(.editReward(reward)) }
        default: break
        }
    }
    #endif
}

// MARK: - Board

private struct ChoreBoardView: View {
    let board: ChoreBoard
    let onToggle: (Chore) -> Void
    let onOpenCare: (CareTask) -> Void
    let present: (ChoreSheet) -> Void

    var body: some View {
        GeometryReader { proxy in
            let count = CGFloat(max(board.columns.count, 1))
            let fitted = (proxy.size.width - 16 * (count - 1)) / count
            // Up to four columns share the width; more scroll sideways.
            let width = max(fitted, 280)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(board.columns) { column in
                        ChoreColumnView(column: column, onToggle: onToggle, onOpenCare: onOpenCare, present: present)
                            .frame(width: width)
                    }
                }
                .frame(height: proxy.size.height)
            }
            .scrollDisabled(fitted >= 280)
            // Let the column shadows spill past the scroll bounds.
            .scrollClipDisabled()
        }
    }
}

private struct ChoreColumnView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    let column: ChoreBoard.Column
    let onToggle: (Chore) -> Void
    let onOpenCare: (CareTask) -> Void
    let present: (ChoreSheet) -> Void

    private var color: Color { model.color(for: column.owner) }

    private var name: String {
        switch column.owner {
        case let .person(id): model.person(id)?.name ?? "Someone"
        case .everyone: "Anyone"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ProgressBar(fraction: column.isEmpty ? 0 : Double(column.doneCount) / Double(column.totalCount), fill: AnyShapeStyle(color), height: 8, track: Theme.surface2)
                .padding(.top, 2)
                .padding(.bottom, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if column.isEmpty {
                        Text(column.owner == .everyone ? "Nothing shared today" : "Nothing due today")
                            .font(.body(14, weight: 600))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                    .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            }
                    }
                    ForEach(column.tasks) { task in
                        ChoreRow(task: task, color: color, today: store.today, calendar: store.calendar) {
                            onToggle(task.chore)
                        } onOpen: {
                            present(.task(task.chore, store.today))
                        }
                    }
                    ForEach(column.care) { task in
                        CareTaskRow(task: task) { onOpenCare(task) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 0)
            ForEach(column.rewards) { status in
                RewardCard(status: status) { present(.editReward(status.reward)) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SurfaceShape(cornerRadius: Theme.radius))
    }

    private var header: some View {
        HStack(spacing: 12) {
            OwnerAvatar(owner: column.owner, size: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.display(20))
                    .lineLimit(1)
                Text("\(column.doneCount) of \(column.totalCount) today")
                    .font(.body(13, weight: 700))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Text("\(column.weekStars)")
                    .font(.display(24))
                    .monospacedDigit()
                StarIcon(size: 20)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(column.weekStars) stars this week")
        }
        .foregroundStyle(Theme.ink)
    }
}

/// A chore on the board: its box checks it off; the rest of the row opens it.
private struct ChoreRow: View {
    @Environment(AppModel.self) private var model
    let task: ChoreBoard.Task
    let color: Color
    let today: DayKey
    let calendar: Calendar
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                CheckBox(isOn: task.isDone, color: doneColor)
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(task.chore.title)
            .accessibilityValue(task.isDone ? "Done" : "Not done")
            .accessibilityHint("Checks it off")
            Button(action: onOpen) { details }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Open \(task.chore.title)")
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }

    /// Done by someone else than the owner shows in the doer's color.
    private var doneColor: Color {
        guard let person = task.completion?.personId else { return color }
        return model.color(for: .person(person))
    }

    private var details: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.chore.title)
                        .font(.body(16, weight: 700))
                        .foregroundStyle(task.isDone ? Theme.muted : Theme.ink)
                        .strikethrough(task.isDone, pattern: .solid, color: color.opacity(0.7))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        if let emoji = task.chore.emoji { Text(emoji).font(.system(size: 12)) }
                        Text(subtitle)
                            .font(.body(12, weight: 600))
                            .foregroundStyle(isOverdue ? Theme.accent : Theme.muted)
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StarsTag(stars: task.chore.stars)
            }
            .padding(.vertical, 14)
            .padding(.trailing, 14)
            .contentShape(Rectangle())
    }

    /// "Mia pitched in" when someone else did your chore; otherwise when it's due.
    private var subtitle: String {
        if let completion = task.completion, let person = completion.personId, person != task.chore.ownerId, task.chore.ownerId != nil {
            return "\(model.person(person)?.name ?? "Someone") pitched in"
        }
        if let completion = task.completion, task.chore.ownerId == nil, let person = completion.personId {
            return "Done by \(model.person(person)?.name ?? "someone")"
        }
        return ChoreSchedule.subtitle(for: task.chore, today: today, calendar: calendar)
    }

    private var isOverdue: Bool {
        task.chore.recurrence.isOnce && !task.isDone && task.chore.anchor < today
    }
}

/// A gentle press effect for big tappable rows.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ProgressBar: View {
    var fraction: Double
    var fill: AnyShapeStyle
    var height: CGFloat
    var track: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fill)
                        .frame(width: fraction > 0 ? max(height, proxy.size.width * min(fraction, 1)) : 0)
                }
                .clipShape(Capsule())
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// A reward at the foot of a column; tap to edit it, "Cash in" once it's reached.
struct RewardCard: View {
    @Environment(HomeStore.self) private var store
    let status: ChoreBoard.RewardStatus
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) { card }
            .buttonStyle(PressableStyle())
            .overlay(alignment: .bottomTrailing) {
                if status.isReached {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { store.cashIn(status.reward) }
                    } label: {
                        Text("Cash in 🎉")
                            .font(.body(12.5, weight: 800))
                            .foregroundStyle(Theme.accentInk)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Cash in \(status.reward.title)")
                }
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text([status.reward.emoji, status.reward.title].compactMap { $0 }.joined(separator: " "))
                .font(.body(15.5, weight: 700))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            ProgressBar(
                fraction: status.fraction,
                fill: AnyShapeStyle(LinearGradient(colors: [PersonColor.ochre.color, Theme.accent], startPoint: .leading, endPoint: .trailing)),
                height: 10,
                track: Theme.surface
            )
            .padding(.top, 9)
            .padding(.bottom, 6)
            HStack {
                // Leaves room for the "Cash in" button once the reward is reached.
                Text("\(min(status.earned, status.reward.targetStars)) / \(status.reward.targetStars) stars" + (status.reward.isShared ? " together" : ""))
                    .font(.body(12.5, weight: 700))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                Spacer(minLength: 4)
            }
            .frame(minHeight: status.isReached ? 28 : nil)
        }
        .padding(12)
        .padding(.bottom, status.isReached ? -4 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit the reward")
    }
}

/// "+2" stars on a row.
struct StarsTag: View {
    let stars: Int

    var body: some View {
        Text("+\(stars)")
            .font(.body(13, weight: 800))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Theme.surface, in: Capsule())
            .accessibilityLabel("\(stars) \(stars == 1 ? "star" : "stars")")
    }
}

/// Companion care on the board: "Walk Yo-Yo · Morning 6-10am", or who did it.
/// Tapping logs it (who, when, details) or opens the log to fix it.
private struct CareTaskRow: View {
    @Environment(AppModel.self) private var model
    let task: CareTask
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CheckBox(isOn: task.isDone, color: doneColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.body(16, weight: 700))
                        .foregroundStyle(task.isDone ? Theme.muted : Theme.ink)
                        .strikethrough(task.isDone, pattern: .solid, color: doneColor.opacity(0.7))
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text(task.routine.emoji).font(.system(size: 12))
                        Text(subtitle)
                            .font(.body(12, weight: 600))
                            .foregroundStyle(isLate ? Theme.accent : Theme.muted)
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StarsTag(stars: task.routine.stars)
            }
            .padding(14)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(task.title + (task.slot.window.isAllDay ? "" : ", \(task.slot.window.label)"))
        .accessibilityValue(task.isDone ? "Done" : "Not done")
        .accessibilityHint(task.isDone ? "Opens the log to fix it" : "Logs it")
    }

    private var doneColor: Color {
        guard let first = task.slot.entry?.people.first else { return Theme.everyone }
        return task.slot.entry?.isTogether == true ? Theme.everyone : model.color(for: .person(first))
    }

    private var isLate: Bool {
        task.slot.state == .late || task.slot.state == .due
    }

    private var subtitle: String {
        if let entry = task.slot.entry {
            let names = ListFormat.join(entry.people.compactMap { model.person($0)?.name })
            return (names.isEmpty ? "Done" : names) + " · " + entry.time.formatted(date: .omitted, time: .shortened)
        }
        let window = task.slot.window
        let when = window.isAllDay ? "any time today" : "\(window.label) · \(window.rangeText)"
        switch task.slot.state {
        case .late: return "Late · " + when
        case .due: return "Due now · " + when
        default: return when
        }
    }
}

// MARK: - A chore, opened

/// One chore on one day, opened from its row: who did it (and changing that), undo,
/// and the chore itself (edit, archive, delete). The same "tap to fix" as meals and walks.
struct ChoreTaskSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @Environment(\.closeWallSheet) private var close
    let chore: Chore
    let day: DayKey
    let onEdit: () -> Void

    @State private var confirmDelete = false

    /// The chore as it is now.
    private var current: Chore { store.snapshot.chores.first { $0.id == chore.id } ?? chore }

    var body: some View {
        let completion = store.completion(of: current, on: day)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Text(current.emoji ?? "✅")
                    .font(.system(size: 30))
                    .frame(width: 60, height: 60)
                    .background(model.color(for: current.owner).wash(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.title).font(.display(28)).lineLimit(2)
                    Text(scheduleLine)
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.trailing, 40)
            }

            VStack(alignment: .leading, spacing: 10) {
                SheetLabel(title: dayTitle, note: completion == nil ? "· not done yet" : "· done")
                if let completion {
                    HStack(spacing: 10) {
                        if let person = completion.personId.flatMap(model.person) {
                            Avatar(person: person, size: 30)
                        }
                        Text(doneLine(completion))
                            .font(.body(16, weight: 700))
                        Spacer(minLength: 0)
                        Button("Undo") {
                            store.toggle(current, on: day)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                if completion != nil || isDue {
                    Text(completion == nil ? "Who did it?" : "Someone else did it?")
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                    FlowLayout(spacing: 10) {
                        ForEach(model.people) { person in
                            let isDoer = completion?.personId == person.id
                            Button {
                                guard let id = person.id else { return }
                                store.credit(current, on: day, to: id)
                            } label: {
                                HStack(spacing: 8) {
                                    Avatar(person: person, size: 30)
                                    Text(person.name).font(.body(15, weight: 700))
                                }
                                .foregroundStyle(Theme.ink)
                                .padding(.leading, 6)
                                .padding(.trailing, 14)
                                .padding(.vertical, 5)
                                .background(isDoer ? person.color.color.wash(0.14) : Theme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(isDoer ? person.color.color : Theme.line, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(person.name) did it")
                            .accessibilityAddTraits(isDoer ? .isSelected : [])
                        }
                    }
                } else {
                    Text("Not due that day.")
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            WeekDots(chore: current)

            HStack(spacing: 10) {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    store.setArchived(current, !current.archived)
                    close()
                } label: { Label(current.archived ? "Restore" : "Archive", systemImage: "archivebox") }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                if confirmDelete {
                    Button("Keep it") { confirmDelete = false }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Delete chore") {
                        store.delete(current)
                        close()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            ErrorLine(message: store.lastError)
        }
        .foregroundStyle(Theme.ink)
    }

    /// One-offs can be done any day; repeating chores only on the days they come around.
    private var isDue: Bool {
        current.recurrence.isOnce || ChoreSchedule.occurs(current, on: day, calendar: store.calendar)
    }

    private var scheduleLine: String {
        let owner = current.ownerId.flatMap(model.person)?.name ?? "Anyone"
        let pattern = current.recurrence.isOnce
            ? Recurrence.describeDue(current.anchor, today: store.today, calendar: store.calendar)
            : current.recurrence.describe(start: current.anchor, calendar: store.calendar)
        return "\(owner) · \(pattern) · +\(current.stars) \(current.stars == 1 ? "star" : "stars")"
    }

    private var dayTitle: String {
        if day == store.today { return "Today" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day(), calendar: store.calendar)
    }

    private func doneLine(_ completion: ChoreCompletion) -> String {
        let who = completion.personId.flatMap(model.person)?.name ?? "Someone"
        let time = completion.completedAt.formatted(date: .omitted, time: .shortened)
        return completion.dayKey == DayKey(completion.completedAt, calendar: store.calendar) ? "\(who) did it at \(time)" : "\(who) did it"
    }
}

/// The chore's week: a dot per day, filled in the color of whoever did it.
private struct WeekDots: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    let chore: Chore

    var body: some View {
        let calendar = store.calendar
        HStack(spacing: 14) {
            ForEach(store.week.days, id: \.self) { day in
                let mark = WeekMark.mark(for: chore, on: day, completions: store.snapshot.completions, calendar: calendar)
                VStack(spacing: 5) {
                    Text(day.formatted(.dateTime.weekday(.narrow), calendar: calendar))
                        .font(.body(11.5, weight: 800))
                        .foregroundStyle(day == store.today ? Theme.accent : Theme.muted)
                    switch mark {
                    case .none:
                        Circle().fill(Theme.line).frame(width: 8, height: 8).frame(width: 20, height: 20)
                    case .open:
                        Circle().strokeBorder(Theme.muted.opacity(day < store.today ? 0.35 : 0.7), lineWidth: 2).frame(width: 20, height: 20)
                    case let .done(person):
                        Circle().fill(person.map { model.color(for: .person($0)) } ?? Theme.everyone).frame(width: 20, height: 20)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week")
    }
}

// MARK: - Week overview

private struct ChoreWeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    let onToggle: (Chore, DayKey) -> Void
    let onOpen: (Chore, DayKey) -> Void

    private var groups: [(owner: Owner, chores: [Chore])] {
        let chores = store.activeChores
        var groups: [(Owner, [Chore])] = model.people.compactMap { person in
            let mine = chores.filter { $0.ownerId == person.id }
            return mine.isEmpty ? nil : (.person(person.id ?? -1), mine)
        }
        let shared = chores.filter { $0.ownerId == nil }
        if !shared.isEmpty { groups.append((.everyone, shared)) }
        return groups
    }

    var body: some View {
        let week = store.week
        let calendar = store.calendar
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("This week")
                    .font(.display(19))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(week.days, id: \.self) { day in
                    let isToday = day == store.today
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated), calendar: calendar).uppercased())
                            .font(.body(11, weight: 800))
                            .tracking(0.6)
                        Text(day.formatted(.dateTime.day(), calendar: calendar))
                            .font(.display(18))
                    }
                    .foregroundStyle(isToday ? Theme.accent : Theme.muted)
                    .frame(width: 64, height: 50)
                    .background(isToday ? Theme.accent.wash(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.bottom, 6)
            if groups.isEmpty {
                Spacer()
                EmptyState(symbol: "checkmark.square", title: "No chores yet", message: "Add one with New chore and it shows up here, day by day.")
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.owner) { group in
                            groupHeader(group.owner)
                            ForEach(group.chores) { chore in
                                row(chore, owner: group.owner, week: week, calendar: calendar)
                            }
                        }
                    }
                }
            }
            starsFooter(week: week)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SurfaceShape(cornerRadius: Theme.radius))
    }

    private func groupHeader(_ owner: Owner) -> some View {
        HStack(spacing: 8) {
            OwnerAvatar(owner: owner, size: 22)
            Text(name(owner).uppercased())
                .font(.body(11.5, weight: 800))
                .tracking(0.9)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func row(_ chore: Chore, owner: Owner, week: HomeWeek, calendar: Calendar) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(chore.emoji ?? "•").font(.system(size: 16)).frame(width: 22)
                Text(chore.title)
                    .font(.body(15, weight: 600))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onOpen(chore, store.dayToOpen(chore)) }
            .accessibilityAddTraits(.isButton)
            ForEach(week.days, id: \.self) { day in
                cell(chore, owner: owner, day: day, calendar: calendar)
                    .frame(width: 64)
            }
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    @ViewBuilder
    private func cell(_ chore: Chore, owner: Owner, day: DayKey, calendar: Calendar) -> some View {
        let mark = WeekMark.mark(for: chore, on: day, completions: store.snapshot.completions, calendar: calendar)
        let canToggle = day <= store.today && mark != .none
        Button {
            // A done day opens to fix who did it; an open one checks it off.
            if case .done = mark { onOpen(chore, day) } else { onToggle(chore, day) }
        } label: {
            switch mark {
            case .none:
                Circle().fill(Theme.line).frame(width: 6, height: 6)
            case .open:
                CheckBox(isOn: false, color: model.color(for: owner), size: 24, cornerRadius: 8, lineWidth: 2)
                    .opacity(day < store.today ? 0.45 : 1)
            case let .done(personId):
                CheckBox(isOn: true, color: personId.map { model.color(for: .person($0)) } ?? Theme.everyone, size: 24, cornerRadius: 8, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .disabled(!canToggle)
        .accessibilityLabel("\(chore.title), \(day.formatted(.dateTime.weekday(.wide), calendar: calendar))")
    }

    private func starsFooter(week: HomeWeek) -> some View {
        let totals = StarTotals.byPerson(store.snapshot.earnings, in: week)
        return HStack(spacing: 18) {
            ForEach(model.people) { person in
                HStack(spacing: 8) {
                    Avatar(person: person, size: 26)
                    Text(person.name).font(.body(14, weight: 700))
                    Text("\(totals[person.id ?? -1] ?? 0)").font(.display(18)).monospacedDigit()
                    StarIcon(size: 15)
                }
            }
            Spacer()
            Text("Tap a box to catch up on a missed day, a check to fix who did it")
                .font(.body(13, weight: 600))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 14)
    }

    private func name(_ owner: Owner) -> String {
        switch owner {
        case let .person(id): model.person(id)?.name ?? "Someone"
        case .everyone: "Anyone"
        }
    }
}

// MARK: - Who did it

private struct WhoDidItSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @Environment(\.closeWallSheet) private var close
    let chore: Chore
    let day: DayKey

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Who did it?").font(.display(28))
                Text([chore.emoji, chore.title].compactMap { $0 }.joined(separator: " ") + "  ·  +\(chore.stars) " + (chore.stars == 1 ? "star" : "stars"))
                    .font(.body(15, weight: 600))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.trailing, 40)
            FlowLayout(spacing: 12) {
                ForEach(model.people) { person in
                    Button {
                        store.toggle(chore, on: day, by: person.id)
                        close()
                    } label: {
                        VStack(spacing: 8) {
                            Avatar(person: person, size: 64)
                            Text(person.name)
                                .font(.body(15, weight: 700))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                        }
                        .frame(width: 104, height: 118)
                        .background(person.color.color.wash(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(person.name)
                }
            }
        }
    }
}
