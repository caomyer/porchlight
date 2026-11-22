import SwiftUI

/// Free together on the wall (docs/design/calendar-free-together.md): a row under the week,
/// one cell a day, green where everyone is free that evening or weekend day, otherwise who
/// isn't. Days past, or beyond the two weeks ahead, are left empty. A green cell plans
/// something when this iPad can add to the home calendar.
enum WallFreeTogether {
    @MainActor
    static func lane(store: CalendarStore, now: Date, onPlan: ((Date) -> Void)?) -> CalendarLane {
        let calendar = store.calendar
        let people = store.people
        let times = FreeTogetherLogic.times(events: store.events, people: people.map(\.id), from: now, calendar: calendar)
        let byDay = Dictionary(times.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let words = FreeWords(calendar: calendar)
        return CalendarLane(
            id: "free-together",
            styles: [.week],
            label: AnyView(
                Image(systemName: "person.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.good)
                    .accessibilityLabel("Free together")
            ),
            cell: { day, _ in
                AnyView(WallFreeCell(time: byDay[day], people: people, words: words, onPlan: onPlan))
            }
        )
    }
}

private struct WallFreeCell: View {
    let time: FreeTime?
    let people: [Person]
    let words: FreeWords
    let onPlan: ((Date) -> Void)?

    var body: some View {
        if let time {
            let headline = words.headline(time, asked: people.count)
            let busy = words.busyLines(time, people: people, household: people.count)
            let content = cell(time, headline: headline, busy: busy)
            if let onPlan, let from = time.everyoneFrom {
                Button { onPlan(from) } label: { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plans something then")
            } else {
                content
            }
        } else {
            Color.clear
        }
    }

    private func cell(_ time: FreeTime, headline: String?, busy: [FreeWords.Line]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(FreeWords.kindLabel(time).uppercased())
                .font(.body(10.5, weight: 800))
                .tracking(0.8)
                .foregroundStyle(headline == nil ? Theme.muted : Theme.goodInk)
            if let headline {
                Text(headline)
                    .font(.body(13.5, weight: 800))
                    .foregroundStyle(Theme.goodInk)
            } else if let summary = words.summary(time, asked: people.count) {
                Text(summary)
                    .font(.body(13, weight: 700))
                    .foregroundStyle(Theme.ink)
                ForEach(Array(busy.prefix(2).enumerated()), id: \.offset) { _, line in
                    Text(line.listed)
                        .font(.body(11.5, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                ForEach(Array(busy.prefix(2).enumerated()), id: \.offset) { _, line in
                    Text(line.title)
                        .font(.body(13, weight: 700))
                        .foregroundStyle(Theme.ink)
                    Text(line.detail)
                        .font(.body(11.5, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                if busy.count > 2 {
                    Text("and \(busy.count - 2) more")
                        .font(.body(11.5, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                let free = people.filter { time.free[$0.id] != nil }
                if !free.isEmpty {
                    HStack(spacing: 4) {
                        OwnerFaces(owners: free.map { .person($0.id) }, people: people, size: 18)
                        Text("free").font(.body(11.5, weight: 700)).foregroundStyle(Theme.goodInk)
                    }
                }
            }
        }
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(headline == nil ? Color.clear : Theme.goodSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(time, headline: headline, busy: busy))
        .accessibilityIdentifier("wall-free-\(time.day.rawValue)")
    }

    private func spoken(_ time: FreeTime, headline: String?, busy: [FreeWords.Line]) -> String {
        let day = "\(FreeWords.kindLabel(time)), \(words.dayLabel(time))"
        let free = words.freeLines(time, people: people)
        let summary = words.summary(time, asked: people.count).map { [$0] } ?? []
        return ([day] + (headline.map { [$0] } ?? summary + busy.map(\.sentence) + free) + time.allDay.map { "All day: \($0)" }).joined(separator: ". ")
    }
}
