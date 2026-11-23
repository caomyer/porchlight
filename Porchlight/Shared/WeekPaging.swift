import Foundation

/// Weeks counted back from the one ending today, as Food's diary and a companion's page
/// page through them: seven-day steps, so this week always ends today and is full, back to
/// the week of the first thing there is to show. Pure, covered by `WeekPagingTests` and
/// `PocketFoodTests`.
enum WeekPaging {
    /// The seven days ending today.
    static func week(endingOn today: DayKey, calendar: Calendar) -> [DayKey] {
        (-6...0).map { today.adding(days: $0, calendar: calendar) }
    }

    /// The seven days `weeksBack` weeks before the ones ending today.
    static func week(endingOn today: DayKey, weeksBack: Int, calendar: Calendar) -> [DayKey] {
        week(endingOn: today.adding(days: -7 * weeksBack, calendar: calendar), calendar: calendar)
    }

    /// How far back it goes: to the week holding `firstDay`, and no further. With nothing,
    /// or nothing before this week, it stays on this week.
    static func weeksBackLimit(firstDay: DayKey?, today: DayKey, calendar: Calendar) -> Int {
        firstDay.map { weeksBack(of: $0, today: today, calendar: calendar) } ?? 0
    }

    /// Which week a day is in, counted back from the one ending today.
    static func weeksBack(of day: DayKey, today: DayKey, calendar: Calendar) -> Int {
        guard day < today else { return 0 }
        let days = calendar.dateComponents([.day], from: day.startDate(in: calendar), to: today.startDate(in: calendar)).day ?? 0
        return max(0, days / 7)
    }

    /// The pager's name for a week: "This week", "Last week", "3 weeks ago".
    static func weekName(weeksBack: Int) -> String {
        switch weeksBack {
        case ...0: "This week"
        case 1: "Last week"
        default: "\(weeksBack) weeks ago"
        }
    }

    /// "Nov 10 to 16", "Oct 27 to Nov 2".
    static func range(_ days: [DayKey], calendar: Calendar) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let start = first.startDate(in: calendar)
        let end = last.startDate(in: calendar)
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let from = start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
        let to = sameMonth
            ? "\(calendar.component(.day, from: end))"
            : end.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
        return "\(from) to \(to)"
    }
}
