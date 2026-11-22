import Foundation

// The phone's Calendar tab (docs/design/calendar-phone-tab.md), as pure functions of the
// household's calendar (its time zone and first weekday), the day picked and the events:
// the week strip, its dots, the person filter, the list's days and the month grid. No UI and
// no clock here; the screen hands in today.

enum PocketCalendarLogic {
    /// How many days the list runs on through, the picked day first.
    static let listDays = 14

    // MARK: Weeks and months

    /// The seven days of the week holding `day`, from the household's first weekday.
    static func week(containing day: DayKey, calendar: Calendar) -> [DayKey] {
        let start = weekStart(of: day, calendar: calendar)
        return (0..<7).map { start.adding(days: $0, calendar: calendar) }
    }

    /// The first day of the week holding `day`.
    static func weekStart(of day: DayKey, calendar: Calendar) -> DayKey {
        let weekday = calendar.component(.weekday, from: day.startDate(in: calendar))
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return day.adding(days: -back, calendar: calendar)
    }

    /// The week `offset` weeks after the one holding `today`.
    static func week(offset: Int, from today: DayKey, calendar: Calendar) -> [DayKey] {
        week(containing: today.adding(days: offset * 7, calendar: calendar), calendar: calendar)
    }

    /// How many weeks after today's week `day` falls.
    static func weekOffset(of day: DayKey, from today: DayKey, calendar: Calendar) -> Int {
        let a = weekStart(of: today, calendar: calendar).startDate(in: calendar)
        let b = weekStart(of: day, calendar: calendar).startDate(in: calendar)
        let days = calendar.dateComponents([.day], from: a, to: b).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    /// The month's days in whole weeks from the first weekday: the days before and after
    /// the month fill its first and last rows.
    static func monthGrid(containing day: DayKey, calendar: Calendar) -> [[DayKey]] {
        let date = day.startDate(in: calendar)
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let first = DayKey(month.start, calendar: calendar)
        let last = DayKey(month.end.addingTimeInterval(-1), calendar: calendar)
        var start = weekStart(of: first, calendar: calendar)
        var rows: [[DayKey]] = []
        while start <= last && rows.count < 6 {
            rows.append((0..<7).map { start.adding(days: $0, calendar: calendar) })
            start = start.adding(days: 7, calendar: calendar)
        }
        return rows
    }

    /// Whether `day` is in the month of `month`.
    static func isInMonth(_ day: DayKey, of month: DayKey, calendar: Calendar) -> Bool {
        calendar.isDate(day.startDate(in: calendar), equalTo: month.startDate(in: calendar), toGranularity: .month)
    }

    /// The header: "November 2026", or "Nov - Dec 2026" for a week across two months, and
    /// "Dec 2026 - Jan 2027" across two years.
    static func title(for days: [DayKey], calendar: Calendar) -> String {
        guard let first = days.first?.startDate(in: calendar), let last = days.last?.startDate(in: calendar) else { return "" }
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return EventText.format(first, calendar, "MMMM y")
        }
        if calendar.isDate(first, equalTo: last, toGranularity: .year) {
            return "\(EventText.format(first, calendar, "MMM")) - \(EventText.format(last, calendar, "MMM y"))"
        }
        return "\(EventText.format(first, calendar, "MMM y")) - \(EventText.format(last, calendar, "MMM y"))"
    }

    // MARK: People

    /// Who the tab shows: everyone, or one person.
    enum Filter: Hashable {
        case everyone
        case person(Person.ID)
    }

    /// The events for the chosen filter. A person's are theirs, and those for the whole
    /// household, which are theirs too; an event two people share is in both.
    static func filter(_ events: [CalendarEvent], by filter: Filter) -> [CalendarEvent] {
        guard case let .person(id) = filter else { return events }
        return events.filter { $0.owners.contains(.person(id)) || $0.owners.contains(.everyone) }
    }

    /// One dot per person with something on the day, in the household's order, the whole
    /// household's last; at most `limit`. Under a person's chip the dots answer "what does
    /// she have": hers (a shared event among them) and the household's, no one else's.
    static func dots(_ events: [CalendarEvent], people: [Person], filter: Filter = .everyone, limit: Int = 4) -> [Owner] {
        var owners = Set(events.flatMap(\.owners))
        if case let .person(id) = filter { owners = owners.intersection([.person(id), .everyone]) }
        var dots: [Owner] = people.map { Owner.person($0.id) }.filter(owners.contains)
        if owners.contains(.everyone) { dots.append(.everyone) }
        return Array(dots.prefix(limit))
    }

    // MARK: The list

    struct Section: Equatable, Identifiable {
        var day: DayKey
        /// "Today, Tuesday", "Tomorrow, Wednesday", "Thursday", "Mon, Dec 7".
        var title: String
        /// "4 things", "1 thing".
        var count: String
        /// All-day first, then by start.
        var events: [CalendarEvent]
        var id: DayKey { day }
    }

    /// The picked day and the days after it that have something, through `listDays`: the
    /// picked day always, saying so when it is empty, the empty ones after it left out.
    static func sections(from picked: DayKey, today: DayKey, calendar: Calendar, events: (DayKey) -> [CalendarEvent]) -> [Section] {
        (0..<listDays).compactMap { offset in
            let day = picked.adding(days: offset, calendar: calendar)
            let list = sorted(events(day))
            guard offset == 0 || !list.isEmpty else { return nil }
            return Section(day: day, title: dayTitle(day, today: today, calendar: calendar), count: count(list.count), events: list)
        }
    }

    /// All-day events first, then timed ones by start.
    static func sorted(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted { a, b in
            if a.isAllDayLike != b.isAllDayLike { return a.isAllDayLike }
            return (a.start, a.end, a.title, a.id) < (b.start, b.end, b.title, b.id)
        }
    }

    static func count(_ n: Int) -> String {
        n == 1 ? "1 thing" : "\(n) things"
    }

    static func dayTitle(_ day: DayKey, today: DayKey, calendar: Calendar) -> String {
        let date = day.startDate(in: calendar)
        let weekday = EventText.format(date, calendar, "EEEE")
        let days = calendar.dateComponents([.day], from: today.startDate(in: calendar), to: date).day ?? 0
        switch days {
        case 0: return "Today, \(weekday)"
        case 1: return "Tomorrow, \(weekday)"
        case -1: return "Yesterday, \(weekday)"
        case 2..<7: return weekday
        default: return EventText.format(date, calendar, "EEE MMM d")
        }
    }

    /// When an event is, in its row: "All day", "6:00 PM" ("18:00" on a 24-hour phone), or
    /// for a quiet calendar's day, "Until 5:30 PM · 3 meetings" under its start.
    static func time(_ event: CalendarEvent, on day: DayKey, calendar: Calendar) -> String {
        if event.isAllDayLike { return "All day" }
        return ClockFormat.phoneTime(max(event.start, day.startDate(in: calendar)), calendar: calendar)
    }

    /// The line under the title: the end and the place, a quiet day's words, or "Busy only".
    static func detail(_ event: CalendarEvent, calendar: Calendar) -> String? {
        if event.isQuiet { return QuietWords.detail(event, calendar: calendar) }
        if event.isBusy { return "Busy only" }
        var parts: [String] = []
        if !event.isAllDayLike { parts.append("to \(ClockFormat.phoneTime(event.end, calendar: calendar))") }
        if let location = event.location { parts.append(location) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension ClockFormat {
    /// The phone's one time style: "6:00 PM" on a 12-hour phone, "18:00" on a 24-hour one,
    /// so a time never leaves morning or afternoon to be guessed.
    static func phoneTime(_ date: Date, calendar: Calendar = .current, twelveHour: Bool = usesTwelveHourClock, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = twelveHour ? "h:mm" : "H:mm"
        let time = formatter.string(from: date)
        guard twelveHour else { return time }
        let period = calendar.component(.hour, from: date) < 12 ? formatter.amSymbol ?? "AM" : formatter.pmSymbol ?? "PM"
        return "\(time)\u{202F}\(period)"
    }
}
