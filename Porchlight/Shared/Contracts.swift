import SwiftUI

// Shared contracts between features. Features (Calendar, Companions, Food,
// Home) never import each other; they meet through these types, and the
// Today / Week / Month screens compose what each feature provides.

// MARK: - Days

/// A calendar day in the household's time zone, stored as "yyyy-MM-dd".
/// Used as the key for anything that belongs to a day (walk logs, meals, pages).
struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Midnight at the start of this day in the given calendar's time zone.
    func startDate(in calendar: Calendar) -> Date {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? .distantPast
    }

    func adding(days: Int, calendar: Calendar) -> DayKey {
        DayKey(calendar.date(byAdding: .day, value: days, to: startDate(in: calendar)) ?? .distantPast, calendar: calendar)
    }

    var description: String { rawValue }
    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Household {
    /// The calendar every household date computation must use.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        calendar.firstWeekday = firstWeekday
        calendar.locale = .current
        return calendar
    }
}

extension Calendar {
    /// The 7 days of the week containing `date`, starting on `firstWeekday`.
    func weekDays(containing date: Date) -> [Date] {
        guard let interval = dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { self.date(byAdding: .day, value: $0, to: interval.start) }
    }

    /// The days shown in a month grid: whole weeks covering the month.
    func monthGridDays(containing date: Date) -> [Date] {
        guard let month = dateInterval(of: .month, for: date),
              let firstWeek = dateInterval(of: .weekOfYear, for: month.start),
              let lastDay = self.date(byAdding: .day, value: -1, to: month.end),
              let lastWeek = dateInterval(of: .weekOfYear, for: lastDay) else { return [] }
        var days: [Date] = []
        var day = firstWeek.start
        while day < lastWeek.end {
            days.append(day)
            day = self.date(byAdding: .day, value: 1, to: day) ?? lastWeek.end
        }
        return days
    }
}

// MARK: - Ownership and color

/// Who something belongs to: one person, or the whole household ("Both").
enum Owner: Hashable, Sendable {
    case person(Int64)
    case everyone
}

extension Theme {
    /// The color for shared, whole-household things ("Both").
    static let everyone = Color(hex: 0xB8935A)
}

// MARK: - Today timeline

/// One row in the Today agenda. Calendar events, care logs (walks) and journal
/// entries (meals) all become timeline items so the day reads as one story.
struct TimelineItem: Identifiable {
    enum Kind: Sendable {
        /// A calendar event, drawn as a colored block.
        case event
        /// Something that happened (a walk, a meal), drawn quieter and solid-outlined.
        case log
        /// Something expected but not done yet (the evening walk), drawn dashed.
        case expected
    }

    var id: String
    var kind: Kind
    /// Sort key and the time shown in the left column.
    var time: Date
    /// Shown instead of a formatted `time`, e.g. "~6:00".
    var timeLabel: String?
    var title: String
    var subtitle: String?
    var owner: Owner
    /// The square on the left: an emoji, a companion face, a meal thumbnail...
    var leading: AnyView
    /// Optional view on the right, e.g. a walker's avatar or a ghost paw.
    var trailing: AnyView?
    /// What tapping the row opens; nil leaves it inert.
    var target: TimelineTarget? = nil
}

/// What a Today row (or a calendar mark) opens: a logged walk or meal to fix, a due walk
/// to log, an event's details, or a chore on a day.
enum TimelineTarget: Hashable, Sendable {
    case careLog(companionId: Int64, routineId: Int64, logId: Int64)
    case careDue(companionId: Int64, routineId: Int64)
    case meal(Int64)
    case event(String)
    case chore(choreId: Int64, day: DayKey)
}

/// Opens a `TimelineTarget` with the same sheet wherever it is tapped: Today, the calendar,
/// a feature's card. Set once by the wall; nil in previews and tests.
struct OpenTimelineTargetAction {
    var open: @MainActor (TimelineTarget) -> Void

    @MainActor func callAsFunction(_ target: TimelineTarget) { open(target) }
}

private struct OpenTimelineTargetKey: EnvironmentKey {
    static let defaultValue: OpenTimelineTargetAction? = nil
}

extension EnvironmentValues {
    var openTimelineTarget: OpenTimelineTargetAction? {
        get { self[OpenTimelineTargetKey.self] }
        set { self[OpenTimelineTargetKey.self] = newValue }
    }
}

/// A whole-day chip shown above the timeline ("Aunt Rosa visiting").
struct AllDayItem: Identifiable {
    var id: String
    var title: String
    var owner: Owner
}

// MARK: - Calendar lanes

/// A row of per-day marks shown under the week and day grids and inside month cells:
/// paw prints for walks, mini plates for meals, chores. Provided by features, drawn by Calendar.
struct CalendarLane: Identifiable {
    enum Style: Hashable { case week, day, month }

    var id: String
    /// Where the lane shows. Things with a time (walks, meals) are drawn in the week and day
    /// grids as moments, so their lanes only summarize the month.
    var styles: Set<Style> = [.week, .day, .month]
    /// Small label in the week view's left column.
    var label: AnyView
    /// Short legend text, e.g. "walks" or "meals".
    var title: String = ""
    /// Marks for one day.
    var cell: (_ day: DayKey, _ style: Style) -> AnyView
}

// MARK: - Errors shown to the user

extension Error {
    var userMessage: String {
        (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}
