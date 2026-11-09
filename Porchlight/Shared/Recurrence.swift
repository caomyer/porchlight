import Foundation

/// How often something comes around. Chores and companion routines share it, so
/// "every day", "Mon, Wed, Fri", "every 3 days", "monthly" and "once" mean the same
/// thing everywhere, and all of them count from a start day.
enum Recurrence: Hashable, Sendable {
    case daily
    /// On these `Calendar` weekdays (1 = Sunday ... 7 = Saturday).
    case weekdays(Set<Int>)
    /// Every `n` days, counted from the start day.
    case everyNDays(Int)
    /// On the start day's day of the month (the month's last day when it is shorter).
    case monthly
    /// One time, due on the start day. Stays on the board until done.
    case once

    var isOnce: Bool { self == .once }

    // MARK: Storage

    /// The stored kind: "daily", "weekdays", "interval", "monthly" or "once".
    var kind: String {
        switch self {
        case .daily: "daily"
        case .weekdays: "weekdays"
        case .everyNDays: "interval"
        case .monthly: "monthly"
        case .once: "once"
        }
    }

    var weekdayMask: Int {
        if case let .weekdays(days) = self { return Self.mask(for: days) }
        return 0
    }

    var intervalDays: Int {
        if case let .everyNDays(n) = self { return n }
        return 1
    }

    init(kind: String, weekdayMask: Int, intervalDays: Int) {
        switch kind {
        case "weekdays": self = .weekdays(Self.weekdays(fromMask: weekdayMask))
        case "interval": self = .everyNDays(max(intervalDays, 1))
        case "monthly": self = .monthly
        case "once": self = .once
        default: self = .daily
        }
    }

    static func mask(for weekdays: Set<Int>) -> Int {
        weekdays.filter { (1...7).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    static func weekdays(fromMask mask: Int) -> Set<Int> {
        Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
    }

    // MARK: Rules

    /// Whether it lands on `day`, counting from `start`. Nothing lands before the start day.
    func occurs(on day: DayKey, start: DayKey, calendar: Calendar) -> Bool {
        switch self {
        case .once:
            return day == start
        case .daily:
            return day >= start
        case let .weekdays(weekdays):
            guard day >= start else { return false }
            return weekdays.contains(calendar.component(.weekday, from: day.startDate(in: calendar)))
        case let .everyNDays(n):
            let offset = Self.days(from: start, to: day, calendar: calendar)
            return offset >= 0 && offset % max(n, 1) == 0
        case .monthly:
            guard day >= start else { return false }
            let date = day.startDate(in: calendar)
            let wanted = calendar.component(.day, from: start.startDate(in: calendar))
            let length = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
            return calendar.component(.day, from: date) == min(wanted, length)
        }
    }

    /// Roughly how many days apart its days are, e.g. 3.5 for twice a week.
    var averageDaysBetween: Double {
        switch self {
        case .daily: 1
        case let .weekdays(days): 7 / Double(max(days.count, 1))
        case let .everyNDays(n): Double(max(n, 1))
        case .monthly: 30.4
        case .once: 365
        }
    }

    /// The first day on or after `from` it lands on, looking up to a year ahead.
    func nextDay(onOrAfter from: DayKey, start: DayKey, calendar: Calendar) -> DayKey? {
        var day = max(from, start)
        for _ in 0..<370 {
            if occurs(on: day, start: start, calendar: calendar) { return day }
            if isOnce { return nil }
            day = day.adding(days: 1, calendar: calendar)
        }
        return nil
    }

    /// Whole days from `from` to `to` (negative when `to` is earlier). DST-safe.
    static func days(from: DayKey, to: DayKey, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: from.startDate(in: calendar), to: to.startDate(in: calendar)).day ?? 0
    }

    // MARK: Wording

    /// "every day", "weekdays", "Mon, Wed", "every 3 days", "every week", "monthly on the 15th".
    /// One-off wording depends on today, see `describeDue`.
    func describe(start: DayKey, calendar: Calendar) -> String {
        switch self {
        case .daily: return "every day"
        case let .weekdays(days): return Self.describe(weekdays: days, calendar: calendar)
        case let .everyNDays(n):
            switch n {
            case 1: return "every day"
            case 7: return "every week"
            case 14: return "every 2 weeks"
            default: return "every \(n) days"
            }
        case .monthly:
            let day = calendar.component(.day, from: start.startDate(in: calendar))
            return "monthly on the \(Self.ordinal(day))"
        case .once:
            return "once, " + start.formatted(.dateTime.month(.abbreviated).day(), calendar: calendar)
        }
    }

    /// "due today", "due Fri", "overdue" for a one-off due on `start`.
    static func describeDue(_ start: DayKey, today: DayKey, calendar: Calendar) -> String {
        let offset = days(from: today, to: start, calendar: calendar)
        switch offset {
        case ..<0: return "overdue"
        case 0: return "due today"
        case 1: return "due tomorrow"
        case 2...6: return "due " + start.formatted(.dateTime.weekday(.wide), calendar: calendar)
        default: return "due " + start.formatted(.dateTime.month(.abbreviated).day(), calendar: calendar)
        }
    }

    /// "weekdays", "weekends", or "Mon, Wed, Fri" in the calendar's week order.
    static func describe(weekdays days: Set<Int>, calendar: Calendar) -> String {
        if days.count == 7 { return "every day" }
        if days == [2, 3, 4, 5, 6] { return "weekdays" }
        if days == [1, 7] { return "weekends" }
        let symbols = calendar.shortWeekdaySymbols
        let names = orderedWeekdays(calendar: calendar).filter(days.contains).map { symbols[$0 - 1] }
        return names.count == 1 ? "every \(calendar.weekdaySymbols[days.first! - 1])" : names.joined(separator: ", ")
    }

    /// Weekday numbers in display order, starting on the calendar's first weekday.
    static func orderedWeekdays(calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// "1st", "2nd", "23rd".
    static func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
