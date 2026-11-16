import SwiftUI

/// "Next 7 days": the calendars on this phone, read-only, grouped by day in each
/// person's color. An event opens in the Calendar app; nothing is stored here.
struct PocketNextWeek: View {
    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        let days = PocketAgendaLogic.nextDays(from: calendarStore.today, count: 7, calendar: calendarStore.calendar) { calendarStore.events(on: $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("From the calendars on this \(DeviceWords.this)")
                        .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                    Text("Next 7 days")
                        .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                }
                if days.isEmpty {
                    Text("Nothing on the calendars this week.")
                        .phoneFont(.body, 13.5, weight: 600)
                        .foregroundStyle(Theme.muted)
                        .phoneCard()
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(days.enumerated()), id: \.element.day) { index, day in
                            Text(PocketAgendaLogic.dayTitle(day.day, today: calendarStore.today, calendar: calendarStore.calendar).uppercased())
                                .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                                .tracking(1.1)
                                .foregroundStyle(Theme.muted)
                                .padding(.top, index == 0 ? 0 : 10)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(day.events.enumerated()), id: \.element.id) { row, event in
                                if row > 0 { RowDivider() }
                                eventRow(event, on: day.day)
                            }
                        }
                    }
                    .phoneCard()
                }
                Text("Tap an event to open it in Calendar. Events are made there, not here.")
                    .phoneFont(.body, 12.5, weight: 500, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
    }

    private func eventRow(_ event: CalendarEvent, on day: DayKey) -> some View {
        let calendar = calendarStore.calendar
        let time = event.isAllDayLike ? "All day" : ClockFormat.time(max(event.start, day.startDate(in: calendar)), calendar: calendar)
        let owner: String? = if case let .person(id) = event.owner { model.person(id)?.name } else { nil }
        let detail = event.isBusy ? [owner, "busy only"].compactMap { $0 }.joined(separator: " · ") : [owner, event.location].compactMap { $0 }.joined(separator: " · ")
        return Button {
            if let url = URL(string: "calshow:\(event.start.timeIntervalSinceReferenceDate)") { openURL(url) }
        } label: {
            AdaptiveRow {
                Text(time)
                    .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 46, alignment: .leading)
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(calendarStore.color(for: event.owner))
                        .frame(width: 4, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text([event.emoji, event.title].compactMap { $0 }.joined(separator: " "))
                            .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                        if !detail.isEmpty {
                            Text(detail)
                                .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if case let .person(id) = event.owner {
                        PersonAvatar(model.person(id), size: .small)
                    }
                }
            }
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Calendar")
    }
}

/// The days ahead from the calendar store. Pure, covered by PocketAgendaTests.
enum PocketAgendaLogic {
    struct Day: Equatable {
        var day: DayKey
        /// All-day events first, then by start.
        var events: [CalendarEvent]
    }

    /// The next `count` days from `today` that have events.
    static func nextDays(from today: DayKey, count: Int, calendar: Calendar, events: (DayKey) -> [CalendarEvent]) -> [Day] {
        (0..<count).compactMap { offset in
            let day = today.adding(days: offset, calendar: calendar)
            let list = events(day).sorted { ($0.isAllDayLike ? 0 : 1, $0.start, $0.id) < ($1.isAllDayLike ? 0 : 1, $1.start, $1.id) }
            return list.isEmpty ? nil : Day(day: day, events: list)
        }
    }

    /// "Today", "Tomorrow", "Wednesday".
    static func dayTitle(_ day: DayKey, today: DayKey, calendar: Calendar) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: 1, calendar: calendar) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide), calendar: calendar)
    }
}
