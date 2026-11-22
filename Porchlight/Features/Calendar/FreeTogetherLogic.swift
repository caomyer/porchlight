import Foundation

/// The times a household plans things into, and how long free counts as free
/// (docs/design/calendar-free-together.md, "The windows"). One value, so a household
/// setting can change it later without touching the rule.
struct FreeWindows: Equatable, Sendable {
    /// Minutes after midnight.
    var eveningStart = 17 * 60 + 30
    var eveningEnd = 21 * 60 + 30
    var eveningNeed: TimeInterval = 2 * 3600
    var weekendStart = 9 * 60
    var weekendEnd = 21 * 60 + 30
    var weekendNeed: TimeInterval = 3 * 3600
    /// "Free after noon": the first free stretch starts from noon until this many minutes after.
    var afterNoonWithin = 60

    static let standard = FreeWindows()
}

/// One evening or weekend day, and who is free in it.
struct FreeTime: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case evening, weekend }

    /// Why someone isn't free: the busy time that takes most of the window.
    struct Busy: Equatable, Sendable {
        enum Reason: Equatable, Sendable {
            /// An event shown in full: its title.
            case event(String)
            /// A calendar passed on as Keep it quiet: "at work".
            case work
            /// A Busy only calendar.
            case busy
        }

        /// Everyone this keeps from being free, in the household's order.
        var people: [Person.ID]
        var reason: Reason
        var start: Date
        var end: Date
        /// Which event, so the same one for two people is said once.
        var eventId: String
        /// The household's own event: a plan together, said as the plan ("Movie night").
        var isHouseholds = false
    }

    var day: DayKey
    var kind: Kind
    var isToday: Bool
    /// The window, from now when it is today.
    var window: DateInterval
    /// The window's own start, before today's clipping.
    var opens: Date
    /// Each free person's first free stretch's start; a person missing here isn't free.
    var free: [Person.ID: Date]
    /// Where each of those stretches ends: the window's end, or what comes next.
    var freeUntil: [Person.ID: Date] = [:]
    /// The first stretch free for everyone asked about, nil when there is none.
    var everyoneFrom: Date?
    /// Where that stretch ends.
    var everyoneUntil: Date?
    /// Everyone asked about is free for the whole window.
    var everyoneAllWindow: Bool
    /// Why each person who isn't free isn't, grouped when it is one event.
    var busy: [Busy]
    /// The day's all-day events, for context: never busy (see "All-day events").
    var allDay: [String]

    var id: String { "\(day.rawValue)-\(kind)" }
}

/// When the household is free together (docs/design/calendar-free-together.md). Pure: the
/// events, people, clock and calendar are handed in, so it is swept in unit tests.
enum FreeTogetherLogic {
    /// Today and the next `days - 1` days' evenings and weekend days, from `now`. A window
    /// already over, or with less left than counts as free, is left out. `people` are the ones
    /// asked about: the household, or one person when their chip is picked.
    static func times(
        events: [CalendarEvent], people: [Person.ID], from now: Date,
        days: Int = 14, windows: FreeWindows = .standard, calendar: Calendar
    ) -> [FreeTime] {
        let today = DayKey(now, calendar: calendar)
        let timed = events.filter { !$0.isAllDay && $0.end > $0.start }
        let allDay = events.filter(\.isAllDay)
        var result: [FreeTime] = []
        for offset in 0..<days {
            let day = today.adding(days: offset, calendar: calendar)
            let dayStart = day.startDate(in: calendar)
            // Midday, so a day the clocks change on is still read as itself.
            let isWeekend = calendar.isDateInWeekend(dayStart.addingTimeInterval(12 * 3600))
            let kind: FreeTime.Kind = isWeekend ? .weekend : .evening
            let (from, to, need) = isWeekend
                ? (windows.weekendStart, windows.weekendEnd, windows.weekendNeed)
                : (windows.eveningStart, windows.eveningEnd, windows.eveningNeed)
            guard let opens = at(from, on: dayStart, calendar: calendar), let closes = at(to, on: dayStart, calendar: calendar) else { continue }
            let start = offset == 0 ? max(opens, quarterUp(now)) : opens
            guard closes.timeIntervalSince(start) >= need else { continue }
            let window = DateInterval(start: start, end: closes)

            let inWindow = timed.filter { $0.start < window.end && $0.end > window.start }
            var busyByPerson: [Person.ID: [DateInterval]] = [:]
            for person in people {
                busyByPerson[person] = merged(inWindow.filter { isFor($0, person: person) }.map { clip($0, to: window) })
            }
            var free: [Person.ID: Date] = [:]
            var freeUntil: [Person.ID: Date] = [:]
            for person in people {
                if let stretch = firstStretch(window, busy: busyByPerson[person] ?? [], need: need) {
                    free[person] = stretch.start
                    freeUntil[person] = stretch.end
                }
            }
            let everyone = merged(people.flatMap { busyByPerson[$0] ?? [] })
            let shared = firstStretch(window, busy: everyone, need: need)

            var busy: [FreeTime.Busy] = []
            for person in people where free[person] == nil {
                let mine = inWindow.filter { isFor($0, person: person) }
                guard let main = mine.max(by: { overlap($0, window) < overlap($1, window) || (overlap($0, window) == overlap($1, window) && $0.start > $1.start) }) else { continue }
                if let index = busy.firstIndex(where: { $0.eventId == main.id }) {
                    busy[index].people.append(person)
                } else {
                    busy.append(FreeTime.Busy(
                        people: [person], reason: reason(main), start: main.start, end: main.end, eventId: main.id,
                        isHouseholds: main.owners.contains(.everyone)
                    ))
                }
            }

            var titles: [String] = []
            for event in allDay where event.touches(day, in: calendar) && people.contains(where: { isFor(event, person: $0) }) {
                if !titles.contains(event.title) { titles.append(event.title) }
            }

            result.append(FreeTime(
                day: day, kind: kind, isToday: offset == 0, window: window, opens: opens,
                free: free, freeUntil: freeUntil, everyoneFrom: shared?.start, everyoneUntil: shared?.end, everyoneAllWindow: everyone.isEmpty,
                busy: busy, allDay: titles
            ))
        }
        return result
    }

    // MARK: Pieces

    /// An event is someone's when it is theirs, shared with them, or the household's.
    static func isFor(_ event: CalendarEvent, person: Person.ID) -> Bool {
        event.owners.contains { owner in
            switch owner {
            case .everyone: true
            case let .person(id): id == person
            }
        }
    }

    private static func reason(_ event: CalendarEvent) -> FreeTime.Busy.Reason {
        if event.isQuiet { return .work }
        if event.isBusy { return .busy }
        return .event(event.title)
    }

    /// `minutes` after midnight on the day starting at `dayStart`, by the clock on the wall
    /// that day (so 5:30 PM is 5:30 PM on the day the clocks change).
    private static func at(_ minutes: Int, on dayStart: Date, calendar: Calendar) -> Date? {
        if minutes >= 24 * 60 { return calendar.date(byAdding: .day, value: 1, to: dayStart) }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dayStart)
    }

    /// The next quarter hour, or `date` itself when it is on one.
    static func quarterUp(_ date: Date) -> Date {
        let step: TimeInterval = 15 * 60
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
    }

    private static func clip(_ event: CalendarEvent, to window: DateInterval) -> DateInterval {
        DateInterval(start: max(event.start, window.start), end: min(event.end, window.end))
    }

    private static func overlap(_ event: CalendarEvent, _ window: DateInterval) -> TimeInterval {
        min(event.end, window.end).timeIntervalSince(max(event.start, window.start))
    }

    /// Sorted, and joined where they touch or overlap.
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// The first gap in `window` between `busy` (merged) at least `need` long.
    /// It starts on a quarter hour: free from 5:45, not from 5:31.
    static func firstStretch(_ window: DateInterval, busy: [DateInterval], need: TimeInterval) -> DateInterval? {
        var cursor = window.start
        for interval in busy + [DateInterval(start: window.end, duration: 0)] {
            let start = quarterUp(cursor)
            if interval.start.timeIntervalSince(start) >= need { return DateInterval(start: start, end: interval.start) }
            cursor = max(cursor, interval.end)
        }
        return nil
    }
}

/// The words of Free together: "Everyone free from 5:30 PM", "Sam out: Book club, 7:00 to
/// 9:00 PM", "Alex at work until 7:30 PM". Times in the phone's style (`ClockFormat.phoneTime`),
/// 12 or 24 hours as the device says.
struct FreeWords {
    var calendar: Calendar
    var twelveHour = ClockFormat.usesTwelveHourClock
    var locale = Locale.current
    var windows = FreeWindows.standard

    func clock(_ date: Date) -> String {
        ClockFormat.phoneTime(date, calendar: calendar, twelveHour: twelveHour, locale: locale)
    }

    /// The green line, when everyone asked about is free; nil when they aren't.
    func headline(_ time: FreeTime, asked: Int) -> String? {
        guard let from = time.everyoneFrom else { return nil }
        let who = asked > 1 ? "Everyone free" : "Free"
        if time.kind == .weekend && time.everyoneAllWindow && time.window.start == time.opens { return "\(who) all day" }
        return "\(who) \(when(from, time.everyoneUntil ?? time.window.end, in: time))"
    }

    /// When a free stretch is: "from 7:30 PM" to the window's end ("after noon" on a weekend
    /// day), "until 1:00 PM" from its start, "2:00 to 6:00 PM" between.
    func when(_ from: Date, _ until: Date, in time: FreeTime) -> String {
        if until >= time.window.end {
            if time.kind == .weekend {
                let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: from) ?? from
                let minutes = from.timeIntervalSince(noon) / 60
                if minutes >= 0 && minutes <= Double(windows.afterNoonWithin) { return "after noon" }
            }
            return "from \(clock(from))"
        }
        if from <= time.window.start { return "until \(clock(until))" }
        return range(from, until)
    }

    /// Why someone isn't free, as a row shows it ("Sam busy" over "Book club, 7:00 to 9:00 PM",
    /// or the household's plan, "Movie night" over "Everyone, 7:00 to 8:30 PM"), as it is listed
    /// under "Everyone busy" ("Sam: Book club, 7:00 to 9:00 PM"), and read out in one sentence.
    struct Line: Equatable, Sendable {
        var title: String
        var detail: String
        var listed: String
        var sentence: String
    }

    /// One line for each reason someone isn't free.
    func busyLines(_ time: FreeTime, people: [Person], household: Int) -> [Line] {
        time.busy.map { busy in
            let names = Self.names(busy.people, people: people, household: household)
            let when = range(busy.start, busy.end)
            switch busy.reason {
            case let .event(title) where busy.isHouseholds:
                let detail = "Everyone, \(when)"
                return Line(title: title, detail: detail, listed: "\(title), \(when)", sentence: "\(title): \(detail)")
            case let .event(title):
                let detail = "\(title), \(when)"
                return Line(title: "\(names) busy", detail: detail, listed: "\(names): \(detail)", sentence: "\(names) busy: \(detail)")
            case .work:
                let until = "until \(clock(busy.end))"
                return Line(title: "\(names) at work", detail: "Until \(clock(busy.end))", listed: "\(names) at work \(until)", sentence: "\(names) at work \(until)")
            case .busy:
                return Line(title: "\(names) busy", detail: when, listed: "\(names): Busy, \(when)", sentence: "\(names) busy, \(when)")
            }
        }
    }

    /// "Everyone busy", when no one asked about is free and each for something different;
    /// the lines are then listed under it.
    func summary(_ time: FreeTime, asked: Int) -> String? {
        guard asked > 1, time.free.isEmpty, time.busy.count > 1 else { return nil }
        return "Everyone busy"
    }

    /// "Mia free from 7:30 PM", for those who are, when not everyone is.
    func freeLines(_ time: FreeTime, people: [Person]) -> [String] {
        guard time.everyoneFrom == nil else { return [] }
        return people.compactMap { person in
            time.free[person.id].map { "\(person.name) free \(when($0, time.freeUntil[person.id] ?? time.window.end, in: time))" }
        }
    }

    /// "Sam", "Sam and Alex", or "Everyone" when it is the whole household.
    static func names(_ ids: [Person.ID], people: [Person], household: Int) -> String {
        if ids.count == household && household > 1 { return "Everyone" }
        let names = people.filter { ids.contains($0.id) }.map(\.name)
        switch names.count {
        case 0: return "Someone"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    /// "7:00 to 9:00 PM"; "11:00 AM to 1:00 PM" across noon; "19:00 to 21:00" in 24 hours.
    func range(_ start: Date, _ end: Date) -> String {
        let samePeriod = (calendar.component(.hour, from: start) < 12) == (calendar.component(.hour, from: end) < 12)
        guard twelveHour, samePeriod else { return "\(clock(start)) to \(clock(end))" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm"
        return "\(formatter.string(from: start)) to \(clock(end))"
    }

    /// "Tonight", "Today", or "Evening" and "Weekend" for the days after.
    static func kindLabel(_ time: FreeTime) -> String {
        if time.isToday { return time.kind == .evening ? "Tonight" : "Today" }
        return time.kind == .evening ? "Evening" : "Weekend"
    }

    /// "Thu, Nov 19"
    func dayLabel(_ time: FreeTime) -> String {
        EventText.format(time.day.startDate(in: calendar), calendar, "EEEMMMd")
    }
}
