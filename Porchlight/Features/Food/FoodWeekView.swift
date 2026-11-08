import SwiftUI

/// The week of polaroids with the "This week" and "On this day" cards beside it.
struct FoodWeekView: View {
    let days: [DayKey]
    let today: DayKey
    let onSnap: (DayKey, String) -> Void
    let onOpen: (JournalEntry) -> Void

    @Environment(FoodStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PolaroidGrid(days: days, today: today, onSnap: onSnap, onOpen: onOpen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 16) {
                WeekStatsCard(days: days, today: today)
                MemoryCard(today: today)
            }
            .frame(width: 260)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Polaroid grid

private struct PolaroidGrid: View {
    let days: [DayKey]
    let today: DayKey
    let onSnap: (DayKey, String) -> Void
    let onOpen: (JournalEntry) -> Void

    @Environment(FoodStore.self) private var store

    private let labelWidth: CGFloat = 62
    private let gap: CGFloat = 9

    var body: some View {
        GeometryReader { proxy in
            let slots = store.slots
            let column = max((proxy.size.width - 36 - labelWidth - gap * 7) / 7, 40)
            // Polaroids are square photos plus a caption strip; shrink to fit many slots.
            let headerHeight: CGFloat = 52
            let rowSpace = (proxy.size.height - 28 - headerHeight) / CGFloat(max(slots.count, 1))
            let width = min(column, max(rowSpace - 40, 40))
            VStack(spacing: 0) {
                header(column: column)
                    .frame(height: headerHeight)
                ForEach(Array(slots.enumerated()), id: \.element) { slotIndex, slot in
                    Spacer(minLength: 0)
                    row(slot: slot, slotIndex: slotIndex, column: column, width: width)
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
        }
        .background(SurfaceShape(cornerRadius: Theme.radius))
    }

    private func header(column: CGFloat) -> some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: labelWidth)
            ForEach(days, id: \.self) { day in
                let date = day.startDate(in: store.calendar)
                VStack(spacing: 1) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.body(11.5, weight: 800))
                        .tracking(0.7)
                        .foregroundStyle(Theme.muted)
                    Text("\(store.calendar.component(.day, from: date))")
                        .font(.display(22))
                        .foregroundStyle(day == today ? Theme.accent : Theme.ink)
                }
                .frame(width: column)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func row(slot: String, slotIndex: Int, column: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: gap) {
            Text(slot.uppercased())
                .font(.body(11, weight: 800))
                .tracking(0.66)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: labelWidth, alignment: .leading)
            ForEach(Array(days.enumerated()), id: \.element) { dayIndex, day in
                cell(day: day, slot: slot, rotation: FoodStyle.rotations[(dayIndex + slotIndex) % 7], width: width)
                    .frame(width: column)
            }
        }
    }

    @ViewBuilder
    private func cell(day: DayKey, slot: String, rotation: Double, width: CGFloat) -> some View {
        let entries = store.entries(on: day, slot: slot)
        if let entry = entries.first {
            Button { onOpen(entry) } label: {
                Polaroid(entry: entry, rotation: rotation, emojiSize: width * 0.44, captionSize: width < 70 ? 14 : 16, extra: entries.count - 1)
            }
            .buttonStyle(.plain)
            .frame(width: width)
        } else if day <= today {
            Button { onSnap(day, slot) } label: {
                EmptyPolaroid(label: day == today ? "snap \(slot.lowercased())" : "not logged")
            }
            .buttonStyle(.plain)
            .frame(width: width)
            .accessibilityLabel(day == today ? "Snap \(slot.lowercased())" : "Add \(slot.lowercased())")
        } else {
            Color.clear.frame(width: width, height: width)
        }
    }
}

// MARK: - This week

private struct WeekStatsCard: View {
    let days: [DayKey]
    let today: DayKey

    @Environment(FoodStore.self) private var store

    var body: some View {
        let stats = store.weekStats(days: days)
        let streak = store.streak(today: today)
        let missed = DiaryStreak.missedSlots(entries: store.snapshot.entries, days: days, today: today, slots: store.slots)
        VStack(alignment: .leading, spacing: 12) {
            Text(isCurrentWeek ? "This week" : "That week").font(.display(19))
            split(stats)
            VStack(alignment: .leading, spacing: 8) {
                if let theme = stats.theme {
                    StatRow(emoji: theme.emoji, tint: PersonColor.coral.color, title: "\(theme.name) week", detail: stats.themeSentence)
                }
                if let best = stats.newDishes.first {
                    StatRow(emoji: "✨", tint: PersonColor.sage.color, title: "New this week", detail: newDetail(best, count: stats.newDishes.count))
                }
                StatRow(emoji: streak > 0 ? "🔥" : "📔", tint: PersonColor.blue.color, title: streakTitle(streak), detail: missedText(missed))
            }
            .padding(.top, 2)
        }
        .card(padding: 20)
    }

    private var isCurrentWeek: Bool { days.contains(today) }

    @ViewBuilder
    private func split(_ stats: WeekStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let total = max(stats.total, 1)
                let gap: CGFloat = stats.homeCooked > 0 && stats.delivery > 0 ? 3 : 0
                let home = (proxy.size.width - gap) * CGFloat(stats.homeCooked) / CGFloat(total)
                HStack(spacing: gap) {
                    if stats.total == 0 {
                        Capsule().fill(Theme.surface2)
                    } else {
                        if stats.homeCooked > 0 { Capsule().fill(PersonColor.ochre.color).frame(width: home) }
                        if stats.delivery > 0 { Capsule().fill(PersonColor.blue.color) }
                    }
                }
            }
            .frame(height: 12)
            HStack {
                legend(PersonColor.ochre.color, "\(stats.homeCooked) home-cooked")
                Spacer()
                legend(PersonColor.blue.color, "\(stats.delivery) delivery")
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.body(12.5, weight: 700)).foregroundStyle(Theme.muted)
        }
    }

    private func newDetail(_ entry: JournalEntry, count: Int) -> String {
        var text = entry.title
        if let rating = entry.rating { text += " · rated \(rating.emoji)" }
        if count > 1 { text += " · +\(count - 1) more" }
        return text
    }

    private func streakTitle(_ streak: Int) -> String {
        switch streak {
        case 0: "Start a diary streak"
        case 1: "1-day diary streak"
        default: "\(streak)-day diary streak"
        }
    }

    private func missedText(_ missed: Int) -> String {
        switch missed {
        case 0: "Every meal snapped so far"
        case 1: "1 meal slipped by unsnapped"
        default: "\(missed) meals slipped by unsnapped"
        }
    }
}

// MARK: - On this day

private struct MemoryCard: View {
    let today: DayKey

    @Environment(FoodStore.self) private var store

    var body: some View {
        if let memory = store.memory(today: today) {
            let entry = memory.entry
            let date = entry.dayKey.startDate(in: store.calendar)
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("On this day").font(.display(19))
                    Spacer()
                    Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.body(13, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Polaroid(entry: entry, rotation: -4, emojiSize: 54, captionSize: 17, plate: 0.46, badgeSize: 22)
                    .frame(width: 140)
                Spacer(minLength: 12)
                Text(sentence(memory))
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            .frame(maxHeight: .infinity)
            .card(padding: 20)
        }
    }

    private func sentence(_ memory: FoodMemory) -> AttributedString {
        let entry = memory.entry
        let people = store.eaters(of: entry)
        let who = store.ateTogether(entry) || people.isEmpty ? "you" : ListFormat.join(people.map(\.name))
        let how = entry.source == .home ? "home-cooked" : "delivered"
        var text = AttributedString("\(memory.whenText) \(who) had ")
        var dish = AttributedString(entry.title.lowercased())
        dish.font = .hand(20, weight: 700)
        dish.foregroundColor = Theme.ink
        text += dish
        text += AttributedString(", \(how) \(entry.slot.lowercased())")
        if let rating = entry.rating { text += AttributedString(". Verdict: \(rating.emoji)") }
        return text
    }
}
