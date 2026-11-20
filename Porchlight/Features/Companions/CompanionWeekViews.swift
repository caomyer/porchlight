import SwiftUI

// The pieces of a companion's page that the wall and the phone share: the mood meter,
// the stat tiles, the paw trail and the podium. Their type is `sharedFont`, so over the
// wall they keep the wall's fixed sizes and on a phone they grow with Dynamic Type.

// MARK: - Mood

/// The mood as a bar from its lowest word to its highest, with a knob where it is now.
struct MoodMeter: View {
    let report: CompanionReport

    var body: some View {
        let moods = CompanionPresets.moods(for: report.companion.species)
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(moods.first?.label ?? "")
                Spacer(minLength: 8)
                Text(moods.last?.label ?? "")
                    .multilineTextAlignment(.trailing)
            }
            .sharedFont(.body, 11.5, weight: 700, relativeTo: .caption)
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
            .accessibilityHidden(true)
            Text(report.moodText)
                .sharedFont(.body, 15, weight: 700, relativeTo: .subheadline)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .animation(.easeInOut(duration: 0.6), value: report.mood)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mood, \(report.moodText)")
    }
}

// MARK: - Stat tiles

/// The week's four numbers, two by two. On a phone at accessibility sizes they go one
/// under another and wrap rather than shrink.
struct StatTileGrid: View {
    let week: RoutineWeek

    @Environment(CompanionStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let tiles = week.tiles(calendar: store.snapshot.calendar)
        if isPhone {
            // Rows of two that share one height when a label wraps; one a row at
            // accessibility sizes.
            let perRow = typeSize.isAccessibilitySize ? 1 : 2
            VStack(spacing: 8) {
                ForEach(Array(stride(from: 0, to: tiles.count, by: perRow)), id: \.self) { start in
                    HStack(spacing: 8) {
                        ForEach(start..<min(start + perRow, tiles.count), id: \.self) { tile(tiles[$0]) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    self.tile(tile)
                }
            }
        }
    }

    private var isPhone: Bool { sizeClass == .compact }

    private func tile(_ tile: RoutineWeek.Tile) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(tile.value).sharedFont(.display, 24, weight: 600, relativeTo: .title2)
                if let unit = tile.unit { Text(unit).sharedFont(.display, 15, weight: 600, relativeTo: .subheadline) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(tile.label)
                .sharedFont(.body, 12, weight: 700, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(isPhone ? nil : 1)
                .minimumScaleFactor(isPhone ? 1 : 0.85)
                .fixedSize(horizontal: false, vertical: isPhone)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: isPhone ? .infinity : nil, alignment: .topLeading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paw trail

/// A routine's week as a grid: a column per day, a row per slot, each slot a dot in the
/// color of who did it. A logged dot opens its log, a missed one logs it for its day,
/// one still expected today starts a log (`RoutineWeek.tap`).
struct PawTrailGrid: View {
    struct Metrics {
        var dot: CGFloat
        var labelWidth: CGFloat
        /// A dot's tap area is 44 pt tall, and this wide; nil shares the row's width out
        /// evenly, which on a phone is a little under 44.
        var cellWidth: CGFloat?
        /// A slot still to log shows the routine's emoji (the phone) or a paw (the wall).
        var showsEmoji: Bool

        /// How tall a slot that asks nothing stands: the wall's dot, or the phone's tap
        /// height, so a row of them lines up with a row of buttons.
        var restHeight: CGFloat

        static let wall = Metrics(dot: 36, labelWidth: 44, cellWidth: 44, showsEmoji: false, restHeight: 36)
        static let phone = Metrics(dot: 30, labelWidth: 30, cellWidth: nil, showsEmoji: true, restHeight: 44)
    }

    let week: RoutineWeek
    let weekDays: [DayKey]
    let today: DayKey
    var metrics: Metrics = .wall
    var isEnabled = true
    let onTap: (RoutineWeek.TrailTap) -> Void

    @Environment(CompanionStore.self) private var store

    var body: some View {
        let calendar = store.snapshot.calendar
        let windows = week.routine.effectiveWindows
        let labels = CareText.shortLabels(windows)
        Grid(horizontalSpacing: 0, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: metrics.labelWidth, height: 1)
                ForEach(weekDays, id: \.self) { day in
                    VStack(spacing: 0) {
                        Text(CompanionWeekWords.weekdayLetter(day, calendar: calendar))
                            .sharedFont(.body, 12, weight: 700, relativeTo: .caption)
                            .foregroundStyle(day == today ? Theme.accent : Theme.muted)
                        Text(CompanionWeekWords.dayNumber(day, calendar: calendar))
                            .sharedFont(.display, 15, weight: 600, relativeTo: .subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                }
            }
            ForEach(windows.indices, id: \.self) { index in
                GridRow {
                    Text(labels[index].uppercased())
                        .sharedFont(.body, 11, weight: 700, relativeTo: .caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: metrics.labelWidth, alignment: .leading)
                        .accessibilityHidden(true)
                    ForEach(weekDays.indices, id: \.self) { dayIndex in
                        let slot = week.trail[safe: dayIndex]?.first { $0.index == index }
                        cell(slot, window: windows[index], on: weekDays[dayIndex])
                            .accessibilityIdentifier("trail-\(week.routine.title)-\(dayIndex)-\(index)")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ slot: CareSlot?, window: CareWindow, on day: DayKey) -> some View {
        let snapshot = store.snapshot
        let label = week.trailLabel(slot, window: window, on: day, snapshot: snapshot)
        if let tap = week.tap(slot, on: day) {
            Button { onTap(tap) } label: {
                mark(tap)
                    .frame(width: metrics.cellWidth, height: 44)
                    .frame(maxWidth: metrics.cellWidth == nil ? .infinity : nil)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(label)
        } else {
            Circle().fill(Theme.surface2.opacity(0.6)).frame(width: 12, height: 12).frame(width: metrics.dot, height: metrics.restHeight)
                .accessibilityElement()
                .accessibilityLabel(label)
        }
    }

    @ViewBuilder
    private func mark(_ tap: RoutineWeek.TrailTap) -> some View {
        switch tap {
        case let .edit(entry):
            PawDot(carers: Carers(entry.people, snapshot: store.snapshot), size: metrics.dot, content: .initial)
        case let .catchUp(missed) where missed.day == today:
            // Late today: still waiting, like an open slot.
            ghost(waiting: true)
        case .catchUp:
            ghost(waiting: false).opacity(0.45)
        case .log:
            ghost(waiting: true)
        }
    }

    @ViewBuilder
    private func ghost(waiting: Bool) -> some View {
        if metrics.showsEmoji {
            Circle()
                .strokeBorder(waiting ? Theme.accent : Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                .frame(width: metrics.dot, height: metrics.dot)
                .overlay { Text(week.routine.emoji).font(.system(size: metrics.dot * 0.45)) }
        } else {
            PawDot(carers: nil, size: metrics.dot)
        }
    }
}

// MARK: - Podium

/// The week's top three on a podium, second, first and third, the leader crowned.
struct PodiumView: View {
    let standings: [CareLogic.Standing]

    @Environment(CompanionStore.self) private var store

    var body: some View {
        let order = CareLogic.podium(standings)
        let leader = CareLogic.leader(standings)
        let most = order.map(\.count).max() ?? 1
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(order, id: \.carer) { standing in
                pod(standing, isWinner: standing == leader, most: most)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176, alignment: .bottom)
    }

    private func pod(_ standing: CareLogic.Standing, isWinner: Bool, most: Int) -> some View {
        let (carers, name) = CareLogic.describe(standing.carer, snapshot: store.snapshot)
        let color = carers.isTogether ? Theme.everyone : carers.single
        return VStack(spacing: 6) {
            if isWinner {
                Text("👑").font(.system(size: 22)).padding(.bottom, -8)
            }
            CarerAvatar(carers: carers, size: 46)
            Text("\(standing.count)")
                .sharedFont(.display, 22, weight: 600, relativeTo: .title3)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(height: max(30, 88 * CGFloat(standing.count) / CGFloat(max(most, 1))))
                .background(color.wash(0.28, over: Theme.surface2), in: UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 12, style: .continuous))
            Text(name)
                .sharedFont(.body, 12, weight: 700, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .frame(width: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(standing.count)\(isWinner ? ", first" : "")")
    }
}

extension CareLogic {
    /// Who a standing is, to draw: a person's mark and name, or the gold heart for together.
    static func describe(_ carer: Carer, snapshot: CompanionSnapshot) -> (Carers, String) {
        switch carer {
        case let .person(id):
            (Carers([id], snapshot: snapshot), snapshot.person(id)?.name ?? "Someone")
        case .together:
            (Carers(colors: [Theme.everyone, Theme.everyone], initials: [CareText.heart]), "Together")
        }
    }
}

extension Milestone.Tint {
    /// The milestone's wash: the companion's color, the person's, or the household's gold.
    func color(look: CompanionLook, snapshot: CompanionSnapshot) -> Color {
        switch self {
        case .companion: look.tint
        case let .person(id): snapshot.person(id)?.color.color ?? Theme.everyone
        case .together: Theme.everyone
        }
    }
}
