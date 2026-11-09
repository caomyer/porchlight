import Foundation

// Pure calendar logic: resolving provider events against the household's
// mapping, and the layout math for the week, month and Today views. No UI and
// no database here, so it is all directly testable.

/// An event as the wall shows it: owner and redaction applied, emoji picked.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    var id: String
    var calendarId: String
    /// Display title, without a leading emoji; "Busy" for busy-only calendars.
    var title: String
    var emoji: String?
    var celebration: EventDecoration.Celebration?
    var location: String?
    var notes: String?
    var start: Date
    var end: Date
    var isAllDay: Bool
    var owner: Owner
    /// True when the calendar is shown as "Busy only": no details at all.
    var isBusy: Bool
    var calendarTitle: String
    /// From a calendar named like Birthdays or Holidays (or Contacts' birthdays).
    var isFromSpecialCalendar: Bool

    /// Spans the all-day lane: all-day events and anything a day or longer.
    var isAllDayLike: Bool { isAllDay || end.timeIntervalSince(start) >= 24 * 3600 }

    /// The sticker drawn in the month view, if this is a celebration.
    var sticker: String? { celebration == nil || isBusy ? nil : emoji }

    /// Applies a calendar's mapping to one occurrence. Returns nil when the
    /// calendar is hidden from the wall.
    static func resolve(_ event: ExternalEvent, source: CalendarSource, kind: ExternalCalendar.Kind = .regular) -> CalendarEvent? {
        guard source.isShown else { return nil }
        let special = kind == .birthdays || isSpecialCalendarTitle(source.title)
        var resolved = CalendarEvent(
            id: event.id,
            calendarId: event.calendarId,
            title: "Busy",
            emoji: nil,
            celebration: nil,
            location: nil,
            notes: nil,
            start: event.start,
            end: max(event.end, event.start),
            isAllDay: event.isAllDay,
            owner: source.owner,
            isBusy: source.visibility == .busy,
            calendarTitle: source.title,
            isFromSpecialCalendar: special
        )
        guard !resolved.isBusy else { return resolved }

        var title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let typed = EventDecoration.leadingEmoji(of: title) {
            title = typed.rest
            resolved.emoji = typed.emoji
        }
        let match = EventDecoration.match(title)
        resolved.emoji = resolved.emoji ?? match?.emoji
        resolved.celebration = match?.celebration
        if kind == .birthdays {
            resolved.celebration = .birthday
            resolved.emoji = resolved.emoji ?? "🎂"
        }
        resolved.title = title.isEmpty ? "Untitled" : title
        resolved.location = event.location
        resolved.notes = event.notes
        return resolved
    }

    static func isSpecialCalendarTitle(_ title: String) -> Bool {
        EventDecoration.tokens(title).contains { $0.hasPrefix("birthday") || $0.hasPrefix("holiday") }
    }

    // MARK: Days

    /// The first and last day this event touches. An end at exactly midnight
    /// does not touch the next day.
    func dayRange(in calendar: Calendar) -> (first: DayKey, last: DayKey) {
        let lastInstant = end > start ? end.addingTimeInterval(-1) : start
        return (DayKey(start, calendar: calendar), DayKey(lastInstant, calendar: calendar))
    }

    func touches(_ day: DayKey, in calendar: Calendar) -> Bool {
        let range = dayRange(in: calendar)
        return range.first <= day && day <= range.last
    }
}

// MARK: - Owner guess

/// Guesses who a newly found calendar belongs to. nil means the whole household.
enum CalendarOwnerGuess {
    /// Title words that mark a calendar as shared.
    private static let sharedWords: Set<String> = [
        "us", "our", "ours", "family", "home", "household", "shared", "both", "everyone", "kids", "house",
    ]

    static func owner(for calendar: ExternalCalendar, people: [Person]) -> Int64? {
        let titleWords = Set(EventDecoration.tokens(calendar.title))
        let inTitle = people.filter { titleWords.contains(firstName($0)) }
        if inTitle.count == 1 { return inTitle[0].id }
        if inTitle.count > 1 { return nil }
        if calendar.kind != .regular || !titleWords.isDisjoint(with: sharedWords) || CalendarEvent.isSpecialCalendarTitle(calendar.title) {
            return nil
        }
        let accountWords = Set(EventDecoration.tokens(calendar.account))
        let inAccount = people.filter { accountWords.contains(firstName($0)) }
        return inAccount.count == 1 ? inAccount[0].id : nil
    }

    private static func firstName(_ person: Person) -> String {
        EventDecoration.tokens(person.name).first ?? ""
    }
}

// MARK: - Countdowns

/// A special day coming up, for the "Coming up" card.
struct Countdown: Identifiable, Equatable, Sendable {
    var event: CalendarEvent
    var daysUntil: Int
    var id: String { event.id }
}

enum CountdownPicker {
    /// Birthdays, anniversaries and holidays (by keyword), plus all-day events
    /// from Birthdays/Holidays calendars, starting today or within `horizon`
    /// days. Repeats of the same title on the same day are shown once.
    static func pick(
        from events: [CalendarEvent],
        today: DayKey,
        calendar: Calendar,
        horizon: Int = 30,
        limit: Int = 3
    ) -> [Countdown] {
        let todayStart = today.startDate(in: calendar)
        var seen = Set<String>()
        var result: [Countdown] = []
        let candidates = events
            .filter { !$0.isBusy && ($0.celebration != nil || ($0.isAllDay && $0.isFromSpecialCalendar)) }
            .sorted { ($0.start, $0.title.lowercased(), $0.id) < ($1.start, $1.title.lowercased(), $1.id) }
        for event in candidates {
            let startDay = DayKey(event.start, calendar: calendar)
            guard startDay >= today else { continue }
            let days = calendar.dateComponents([.day], from: todayStart, to: startDay.startDate(in: calendar)).day ?? 0
            guard days <= horizon else { continue }
            let key = "\(startDay.rawValue)|\(event.title.lowercased())"
            guard seen.insert(key).inserted else { continue }
            result.append(Countdown(event: event, daysUntil: days))
            if result.count == limit { break }
        }
        return result
    }
}

// MARK: - Week layout

/// Side-by-side placement for overlapping timed events.
enum OverlapLayout {
    struct Slot: Equatable {
        var column: Int
        var columns: Int
    }

    struct Item<ID: Hashable> {
        var id: ID
        var start: Date
        var end: Date
    }

    /// Events that overlap (directly or through a chain) form a cluster; each
    /// gets the first free column and every event in a cluster shares its width.
    static func slots<ID: Hashable>(_ items: [Item<ID>]) -> [ID: Slot] {
        let sorted = items.sorted { ($0.start, -$0.end.timeIntervalSince1970) < ($1.start, -$1.end.timeIntervalSince1970) }
        var result: [ID: Slot] = [:]
        var cluster: [(id: ID, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            for entry in cluster { result[entry.id] = Slot(column: entry.column, columns: columnEnds.count) }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for item in sorted {
            if item.start >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[free] = item.end
                cluster.append((item.id, free))
            } else {
                columnEnds.append(item.end)
                cluster.append((item.id, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, item.end)
        }
        flush()
        return result
    }
}

/// Bars in the week's all-day lane, packed into as few rows as possible.
enum AllDayLayout {
    struct Bar: Equatable, Identifiable {
        var id: String
        /// Day indexes within the visible days, inclusive.
        var startIndex: Int
        var endIndex: Int
        var row: Int
        /// The event started before / ends after the visible days.
        var continuesBefore: Bool
        var continuesAfter: Bool
    }

    static func bars(for events: [CalendarEvent], days: [DayKey], calendar: Calendar) -> [Bar] {
        guard let firstDay = days.first, let lastDay = days.last else { return [] }
        var placed: [(start: Int, end: Int, id: String, before: Bool, after: Bool)] = []
        for event in events where event.isAllDayLike {
            let range = event.dayRange(in: calendar)
            guard range.last >= firstDay, range.first <= lastDay else { continue }
            let start = days.firstIndex { $0 >= range.first } ?? 0
            let end = days.lastIndex { $0 <= range.last } ?? days.count - 1
            placed.append((start, end, event.id, range.first < firstDay, range.last > lastDay))
        }
        // Earlier first, then longer first, so long bars sit on top.
        placed.sort { ($0.start, -($0.end - $0.start), $0.id) < ($1.start, -($1.end - $1.start), $1.id) }
        var rowEnds: [Int] = []
        return placed.map { item in
            let row: Int
            if let free = rowEnds.firstIndex(where: { $0 < item.start }) {
                row = free
                rowEnds[free] = item.end
            } else {
                row = rowEnds.count
                rowEnds.append(item.end)
            }
            return Bar(id: item.id, startIndex: item.start, endIndex: item.end, row: row, continuesBefore: item.before, continuesAfter: item.after)
        }
    }
}

/// The hours shown by the time grid: 8a-9p, widened to fit every event.
enum HourRange {
    static let standard = 8...21

    /// The standard hours, widened to fit the timed events and `moments` (walks, meals) on `days`.
    static func fitting(_ events: [CalendarEvent], moments: [Date] = [], days: [DayKey], calendar: Calendar) -> ClosedRange<Int> {
        var lower = standard.lowerBound
        var upper = standard.upperBound
        for moment in moments {
            lower = min(lower, calendar.component(.hour, from: moment))
            upper = max(upper, calendar.component(.hour, from: moment) + 1)
        }
        for day in days {
            let dayStart = day.startDate(in: calendar)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            for event in events where !event.isAllDayLike && event.end > dayStart && event.start < dayEnd {
                let start = max(event.start, dayStart)
                let end = min(event.end, dayEnd)
                let startHour = calendar.component(.hour, from: start)
                let endHours = end.timeIntervalSince(dayStart) / 3600
                lower = min(lower, startHour)
                upper = max(upper, Int(endHours.rounded(.up)))
            }
        }
        return max(0, lower)...min(24, upper)
    }
}

// MARK: - Moments

enum MomentLayout {
    /// Top edges for marks of `size` centered on `centers` (in order), each pushed down just
    /// enough not to overlap the one before, and pulled back up from the bottom `limit`.
    static func tops(centers: [CGFloat], size: CGFloat, spacing: CGFloat, limit: CGFloat) -> [CGFloat] {
        var tops: [CGFloat] = []
        for center in centers {
            let wanted = max(2, center - size / 2)
            tops.append(tops.last.map { max(wanted, $0 + size + spacing) } ?? wanted)
        }
        // Marks pushed past the bottom slide back up as a stack.
        var floor = limit - size
        for index in tops.indices.reversed() where tops[index] > floor {
            tops[index] = floor
            floor -= size + spacing
        }
        return tops
    }
}

// MARK: - Text

enum EventText {
    /// "10:00 - 11:30", with weekdays when the event spans days.
    /// `withPeriod` adds AM/PM where the locale uses it ("7:00 PM").
    static func timeRange(_ event: CalendarEvent, calendar: Calendar, withPeriod: Bool = false) -> String {
        func time(_ date: Date) -> String {
            withPeriod ? format(date, calendar, "jmm") : ClockFormat.time(date, calendar: calendar)
        }
        let start = time(event.start)
        let end = time(event.end)
        let range = event.dayRange(in: calendar)
        if range.first == range.last {
            return "\(start) - \(end)"
        }
        return "\(weekday(event.start, calendar)) \(start) - \(weekday(event.end, calendar)) \(end)"
    }

    /// Compact grid label: "10a", "11:30a", "Noon" style hours.
    static func shortTime(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        guard ClockFormat.usesTwelveHourClock else { return String(format: "%d:%02d", hour, minute) }
        let h12 = (hour + 11) % 12 + 1
        let suffix = hour < 12 ? "a" : "p"
        return minute == 0 ? "\(h12)\(suffix)" : String(format: "%d:%02d%@", h12, minute, suffix)
    }

    /// Hour labels for the grid's left column.
    static func hourLabel(_ hour: Int) -> String {
        guard ClockFormat.usesTwelveHourClock else { return String(format: "%d:00", hour % 24) }
        switch hour % 24 {
        case 0: return "12a"
        case 12: return "Noon"
        case let h where h < 12: return "\(h)a"
        case let h: return "\(h - 12)p"
        }
    }

    /// "Fri-Sun" for a multi-day event, nil for a single day.
    static func daySpan(_ event: CalendarEvent, calendar: Calendar) -> String? {
        let range = event.dayRange(in: calendar)
        guard range.first != range.last else { return nil }
        let first = range.first.startDate(in: calendar)
        let last = range.last.startDate(in: calendar)
        let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        if days < 7 {
            return "\(weekday(first, calendar))-\(weekday(last, calendar))"
        }
        return "\(monthDay(first, calendar))-\(monthDay(last, calendar))"
    }

    static func weekday(_ date: Date, _ calendar: Calendar) -> String {
        format(date, calendar, "EEE")
    }

    /// "Thu Nov 12"
    static func shortDate(_ date: Date, calendar: Calendar) -> String {
        format(date, calendar, "EEE MMM d")
    }

    static func monthDay(_ date: Date, _ calendar: Calendar) -> String {
        format(date, calendar, "MMM d")
    }

    static func format(_ date: Date, _ calendar: Calendar, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
