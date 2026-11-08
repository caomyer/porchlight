import SwiftUI

/// What the Chores screen has open on top of the board.
enum ChoreSheet: Identifiable {
    case newChore
    case editChore(Chore)
    case whoDidIt(Chore, DayKey)
    case editReward(Reward)

    var id: String {
        switch self {
        case .newChore: "new"
        case let .editChore(chore): "edit-\(chore.id ?? -1)"
        case let .whoDidIt(chore, day): "who-\(chore.id ?? -1)-\(day)"
        case let .editReward(reward): "reward-\(reward.id ?? -1)"
        }
    }
}

/// The chore board: a column per person plus "Anyone", or the week overview.
struct ChoresScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    @State private var showWeek = ChoresScreen.debugShowsWeek
    @State private var sheet: ChoreSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeHeader(
                title: "Chores",
                subtitle: store.today.formatted(.dateTime.weekday(.wide), calendar: store.calendar) + (showWeek ? " · this week at a glance" : " · tap to check off")
            ) {
                HeaderChip(title: "This week", isSelected: showWeek) {
                    withAnimation(.easeInOut(duration: 0.25)) { showWeek.toggle() }
                }
                HeaderChip(title: "New chore", symbol: "plus") { present(.newChore) }
            }
            if showWeek {
                ChoreWeekView(onToggle: toggle)
                    .transition(.opacity)
            } else {
                ChoreBoardView(onToggle: { toggle($0, store.today) }, present: present)
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
            case let .editReward(reward): RewardEditor(reward: reward)
            }
        }
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
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    let onToggle: (Chore) -> Void
    let present: (ChoreSheet) -> Void

    var body: some View {
        let board = store.board(people: model.people)
        GeometryReader { proxy in
            let count = CGFloat(max(board.columns.count, 1))
            let fitted = (proxy.size.width - 16 * (count - 1)) / count
            // Up to four columns share the width; more scroll sideways.
            let width = max(fitted, 280)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(board.columns) { column in
                        ChoreColumnView(column: column, onToggle: onToggle, present: present)
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
            ProgressBar(fraction: column.tasks.isEmpty ? 0 : Double(column.doneCount) / Double(column.tasks.count), fill: AnyShapeStyle(color), height: 8, track: Theme.surface2)
                .padding(.top, 2)
                .padding(.bottom, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if column.tasks.isEmpty {
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
                        ChoreRow(task: task, color: color, today: store.today, calendar: store.calendar) { onToggle(task.chore) }
                            .contextMenu {
                                Button { present(.editChore(task.chore)) } label: { Label("Edit", systemImage: "pencil") }
                                Button { store.setArchived(task.chore, true) } label: { Label("Archive", systemImage: "archivebox") }
                            }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 0)
            ForEach(column.rewards) { status in
                RewardCard(status: status)
                    .contextMenu {
                        Button { present(.editReward(status.reward)) } label: { Label("Edit", systemImage: "pencil") }
                        Button { store.restart(status.reward) } label: { Label("Start over", systemImage: "arrow.counterclockwise") }
                        Button { store.setArchived(status.reward, true) } label: { Label("Archive", systemImage: "archivebox") }
                    }
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
                Text("\(column.doneCount) of \(column.tasks.count) today")
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

private struct ChoreRow: View {
    let task: ChoreBoard.Task
    let color: Color
    let today: DayKey
    let calendar: Calendar
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CheckBox(isOn: task.isDone, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.chore.title)
                        .font(.body(16, weight: 700))
                        .foregroundStyle(task.isDone ? Theme.muted : Theme.ink)
                        .strikethrough(task.isDone, pattern: .solid, color: color.opacity(0.7))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        if let emoji = task.chore.emoji { Text(emoji).font(.system(size: 12)) }
                        Text(ChoreSchedule.subtitle(for: task.chore, today: today, calendar: calendar))
                            .font(.body(12, weight: 600))
                            .foregroundStyle(isOverdue ? Theme.accent : Theme.muted)
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("+\(task.chore.stars)")
                    .font(.body(13, weight: 800))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.surface, in: Capsule())
            }
            .padding(14)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(task.chore.title)
        .accessibilityValue(task.isDone ? "Done" : "Not done")
        .accessibilityHint("Double-tap to check off. Long-press to edit.")
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

private struct RewardCard: View {
    @Environment(HomeStore.self) private var store
    let status: ChoreBoard.RewardStatus

    var body: some View {
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
                Text("\(min(status.earned, status.reward.targetStars)) / \(status.reward.targetStars) stars" + (status.reward.isShared ? " together" : ""))
                    .font(.body(12.5, weight: 700))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                Spacer(minLength: 4)
                if status.isReached {
                    Button("Start over") { store.restart(status.reward) }
                        .font(.body(12.5, weight: 800))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Week overview

private struct ChoreWeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeStore.self) private var store
    let onToggle: (Chore, DayKey) -> Void

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
            onToggle(chore, day)
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
        let totals = StarTotals.byPerson(store.snapshot.completions, in: week)
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
            Text("Tap a box to catch up on a missed day")
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
