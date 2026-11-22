import SwiftUI

/// Free together on the phone (docs/design/calendar-free-together.md): tonight, then each
/// evening and weekend day of the next two weeks, green where everyone asked about is free,
/// otherwise who isn't and why. A green row plans something: the add sheet, on that day,
/// from when everyone is free.
struct PocketFreeTogether: View {
    let filter: PocketCalendarLogic.Filter
    /// How many days, today first (fewer in a hosted look too tall to draw whole).
    var days = 14
    /// Opens the add sheet starting at this time.
    var onPlan: (Date) -> Void = { _ in }

    @Environment(CalendarStore.self) private var store

    var body: some View {
        let calendar = store.calendar
        let asked: [Person] = switch filter {
        case .everyone: store.people
        case let .person(id): store.people.filter { $0.id == id }
        }
        let times = FreeTogetherLogic.times(events: store.events, people: asked.map(\.id), from: store.now(), days: days, calendar: calendar)
        let words = FreeWords(calendar: calendar)
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                ForEach(Array(times.enumerated()), id: \.element.id) { index, time in
                    if index > 0 { RowDivider() }
                    PocketFreeRow(time: time, asked: asked, words: words, onPlan: onPlan)
                }
            }
            .phoneCard()
            Text("From the calendars your household shares. All-day events are listed, never counted as busy.")
                .phoneFont(.body, 12, weight: 600, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("free-together")
    }
}

/// "Evening / Thu 19" beside "Everyone free from 5:30 PM", or "Sam out" over "Book club,
/// 7:00 to 9:00 PM"; at the accessibility sizes the day goes over the answer.
private struct PocketFreeRow: View {
    let time: FreeTime
    let asked: [Person]
    let words: FreeWords
    let onPlan: (Date) -> Void

    @Environment(CalendarStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var dayColumn: CGFloat = 64

    var body: some View {
        let headline = words.headline(time, asked: asked.count)
        let busy = words.busyLines(time, people: store.people, household: store.people.count)
        let free = words.freeLines(time, people: asked)
        let content = HStack(alignment: .center, spacing: 10) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
            layout {
                day.frame(width: typeSize.isAccessibilitySize ? nil : dayColumn, alignment: .leading)
                answer(headline: headline, busy: busy, free: free)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if time.everyoneFrom != nil {
                Image(systemName: "plus.circle.fill")
                    .phoneFont(.body, 20, weight: 600, relativeTo: .title3)
                    .foregroundStyle(Theme.good)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if let from = time.everyoneFrom {
            Button { onPlan(from) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(headline: headline, busy: busy, free: free))
                .accessibilityHint("Plans something then")
                .accessibilityIdentifier("free-\(time.day.rawValue)")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(headline: headline, busy: busy, free: free))
                .accessibilityIdentifier("free-\(time.day.rawValue)")
        }
    }

    private var day: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(FreeWords.kindLabel(time))
                .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
            Text(EventText.format(time.day.startDate(in: words.calendar), words.calendar, "EEEd"))
                .phoneFont(.body, 15, weight: 700, relativeTo: .subheadline)
                .foregroundStyle(Theme.ink)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func answer(headline: String?, busy: [FreeWords.Line], free: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let headline {
                Text(headline)
                    .phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                    .foregroundStyle(Theme.goodInk)
                if time.everyoneAllWindow && time.allDay.isEmpty {
                    detail("Nothing planned")
                }
            } else {
                ForEach(Array(busy.enumerated()), id: \.offset) { _, line in
                    Text(line.title)
                        .phoneFont(.body, 14.5, weight: 700, relativeTo: .subheadline)
                        .foregroundStyle(Theme.ink)
                    detail(line.detail)
                }
                ForEach(free, id: \.self) { line in
                    Text(line)
                        .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                        .foregroundStyle(Theme.goodInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(time.allDay, id: \.self) { detail("All day: \($0)") }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Evening, Thursday 19. Sam out: Book club, 7:00 to 9:00 PM. Alex free from 5:30 PM."
    private func spoken(headline: String?, busy: [FreeWords.Line], free: [String]) -> String {
        let day = "\(FreeWords.kindLabel(time)), \(EventText.format(time.day.startDate(in: words.calendar), words.calendar, "EEEEd"))"
        let parts = [day] + (headline.map { [$0] } ?? busy.map(\.sentence) + free) + time.allDay.map { "All day: \($0)" }
        return parts.joined(separator: ". ")
    }
}
