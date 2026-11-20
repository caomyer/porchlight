import Foundation

/// A care log with the people who did it.
struct CareEntry: Equatable, Identifiable, Sendable {
    var log: CareLog
    var people: [Person.ID]

    var id: CareLog.ID { log.id }
    var time: Date { log.occurredAt }
    var isTogether: Bool { people.count > 1 }
}

/// One slot of a routine on one day: "Morning 6-10am", done by Mia at 8:12.
struct CareSlot: Equatable, Identifiable, Sendable {
    enum State: Equatable, Sendable {
        /// Logged; `onTime` when it happened inside the window.
        case done(onTime: Bool)
        /// Today, before the window opens.
        case upcoming
        /// Today, inside the window.
        case open
        /// Today, inside the window and past the routine's nudge time.
        case due
        /// Today, after the window closed, not logged yet.
        case late
        /// A past day that was never logged.
        case missed
        /// A day after today.
        case future
    }

    var index: Int
    var window: CareWindow
    var entry: CareEntry?
    var state: State

    var id: Int { index }
    var isDone: Bool { entry != nil }
    var isOnTime: Bool { state == .done(onTime: true) }
    /// Not logged yet, but still expected today.
    var isPendingToday: Bool { [.upcoming, .open, .due, .late].contains(state) }
}

/// Pure care computations: slots, streaks, stats and mood.
/// Everything takes `now` and a calendar so it is deterministic and testable.
enum CareLogic {
    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(_ day: DayKey, minute: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: minute, to: day.startDate(in: calendar)) ?? day.startDate(in: calendar)
    }

    /// Groups entries by household day, each day sorted by time.
    static func byDay(_ entries: [CareEntry], calendar: Calendar) -> [DayKey: [CareEntry]] {
        Dictionary(grouping: entries) { DayKey($0.time, calendar: calendar) }
            .mapValues { $0.sorted { $0.time < $1.time } }
    }

    // MARK: Slots

    /// Which window a log at `minute` belongs to: the one it falls in, else the nearest (earlier wins ties).
    static func windowIndex(forMinute minute: Int, in windows: [CareWindow]) -> Int {
        var best = 0
        var bestDistance = Int.max
        for (index, window) in windows.enumerated() {
            let distance = window.distance(to: minute)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// The slot a log at `minute` is for, when it was meant for `intended`: that slot, unless
    /// the time lies inside another slot's window (a time moved into the evening is the
    /// evening's). With nothing intended, the window the time belongs to.
    static func slot(forMinute minute: Int, intended: Int?, in windows: [CareWindow]) -> Int {
        if let intended, windows.indices.contains(intended),
           !windows.indices.contains(where: { $0 != intended && windows[$0].contains(minute: minute) }) {
            return intended
        }
        return windowIndex(forMinute: minute, in: windows)
    }

    /// Fills each window with the first log of the day that belongs to it: the one logged
    /// for that slot, else the first whose time falls in or nearest it. A log made for a
    /// slot (`CareLog.slot`) fills that slot whatever time of day it was written, so a late
    /// breakfast logged at 1:30 pm is breakfast, not dinner. A second log for an already
    /// filled window is an extra and fills nothing. Every screen, the widgets and the
    /// write that checks a slot is free go through here.
    static func assign(_ dayEntries: [CareEntry], to windows: [CareWindow], calendar: Calendar) -> [CareEntry?] {
        var filled = [CareEntry?](repeating: nil, count: windows.count)
        guard !windows.isEmpty else { return filled }
        let ordered = dayEntries.sorted { $0.time < $1.time }
        var placed = Set<CareEntry.ID>()
        for entry in ordered {
            guard let slot = entry.log.slot, windows.indices.contains(slot), filled[slot] == nil else { continue }
            filled[slot] = entry
            placed.insert(entry.id)
        }
        for entry in ordered where !placed.contains(entry.id) {
            let index = windowIndex(forMinute: minuteOfDay(entry.time, calendar: calendar), in: windows)
            if filled[index] == nil { filled[index] = entry }
        }
        return filled
    }

    /// The slots for a routine on one day, with their state relative to `now`.
    /// A routine has no slots on days it isn't due (unless it was logged anyway).
    static func slots(
        for routine: CareRoutine,
        on day: DayKey,
        byDay: [DayKey: [CareEntry]],
        now: Date,
        calendar: Calendar
    ) -> [CareSlot] {
        let windows = routine.effectiveWindows
        let dayEntries = byDay[day] ?? []
        let today = DayKey(now, calendar: calendar)
        if dayEntries.isEmpty && !routine.occurs(on: day, calendar: calendar) {
            return []
        }
        let filled = assign(dayEntries, to: windows, calendar: calendar)
        let nowMinute = minuteOfDay(now, calendar: calendar)
        return windows.enumerated().map { index, window in
            let state: CareSlot.State
            if let entry = filled[index] {
                state = .done(onTime: window.contains(minute: minuteOfDay(entry.time, calendar: calendar)))
            } else if day > today {
                state = .future
            } else if day < today {
                state = .missed
            } else if nowMinute < window.start {
                state = .upcoming
            } else if nowMinute > window.end {
                state = .late
            } else if let nudge = routine.nudgeAfterMinutes, nowMinute >= window.start + nudge {
                state = .due
            } else {
                state = .open
            }
            return CareSlot(index: index, window: window, entry: filled[index], state: state)
        }
    }

    // MARK: Owed

    /// Whether a slot was owed at all. On the day a routine starts, a slot whose window
    /// had closed before the companion was added (`added`) never was: a companion added at
    /// 9 pm doesn't owe that evening's dinner. The one rule for it: the paw trail, the week's
    /// numbers, the streak, the on-time run, the missed list and Today's banner all ask here.
    static func isOwed(_ slot: CareSlot, of routine: CareRoutine, on day: DayKey, since added: Date?, calendar: Calendar) -> Bool {
        guard let added, day == routine.start else { return true }
        return date(day, minute: slot.window.end, calendar: calendar) > added
    }

    // MARK: Streak

    /// Consecutive days, ending today, on which every owed slot was filled. Today
    /// only counts once complete; an unfinished today never breaks the streak.
    static func streak(for routine: CareRoutine, entries: [CareEntry], now: Date, calendar: Calendar, since added: Date?) -> Int {
        guard let first = entries.map(\.time).min() else { return 0 }
        let byDay = byDay(entries, calendar: calendar)
        let firstDay = DayKey(first, calendar: calendar)
        var day = DayKey(now, calendar: calendar)
        var count = 0
        if isComplete(routine, on: day, byDay: byDay, now: now, calendar: calendar, since: added) { count += 1 }
        day = day.adding(days: -1, calendar: calendar)
        while day >= firstDay, isComplete(routine, on: day, byDay: byDay, now: now, calendar: calendar, since: added) {
            count += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return count
    }

    static func isComplete(_ routine: CareRoutine, on day: DayKey, byDay: [DayKey: [CareEntry]], now: Date, calendar: Calendar, since added: Date?) -> Bool {
        slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar)
            .allSatisfy { $0.isDone || !isOwed($0, of: routine, on: day, since: added, calendar: calendar) }
    }

    // MARK: Weekly stats

    struct WeekStats: Equatable, Sendable {
        var count = 0
        var slotsOnTime = 0
        /// Owed slots that were due so far this week (today's count once logged or closed).
        var slotsSoFar = 0
        var totalMinutes = 0
        var timedCount = 0
        var pee = 0
        var poo = 0
        var stars = 0

        var averageMinutes: Int? { timedCount > 0 ? Int((Double(totalMinutes) / Double(timedCount)).rounded()) : nil }
    }

    static func weekStats(for routine: CareRoutine, entries: [CareEntry], days: [DayKey], now: Date, calendar: Calendar, since added: Date?) -> WeekStats {
        let byDay = byDay(entries, calendar: calendar)
        var stats = WeekStats()
        for day in days {
            for entry in byDay[day] ?? [] {
                stats.count += 1
                stats.stars += entry.log.stars
                if let minutes = entry.log.durationMinutes {
                    stats.totalMinutes += minutes
                    stats.timedCount += 1
                }
                if entry.log.pee == true { stats.pee += 1 }
                if entry.log.poo == true { stats.poo += 1 }
            }
            for slot in slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar) {
                switch slot.state {
                case let .done(onTime):
                    stats.slotsSoFar += 1
                    if onTime { stats.slotsOnTime += 1 }
                case .late, .missed:
                    if isOwed(slot, of: routine, on: day, since: added, calendar: calendar) { stats.slotsSoFar += 1 }
                case .upcoming, .open, .due, .future:
                    break
                }
            }
        }
        return stats
    }

    // MARK: Leaderboard

    enum Carer: Hashable, Sendable {
        case person(Person.ID)
        case together
    }

    struct Standing: Equatable, Sendable {
        var carer: Carer
        var count: Int
    }

    /// Solo logs per person, plus logs done together as their own entry.
    /// Sorted by count, then by household order (`people`), with Together last on ties.
    static func leaderboard(_ entries: [CareEntry], people: [Person.ID]) -> [Standing] {
        var counts: [Carer: Int] = [:]
        for entry in entries where !entry.people.isEmpty {
            let carer: Carer = entry.isTogether ? .together : .person(entry.people[0])
            counts[carer, default: 0] += 1
        }
        func rank(_ carer: Carer) -> Int {
            switch carer {
            case let .person(id): people.firstIndex(of: id) ?? people.count
            case .together: people.count + 1
            }
        }
        return counts
            .map { Standing(carer: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : rank($0.carer) < rank($1.carer) }
    }

    // MARK: Milestones

    static let runMilestones = [10, 25, 50, 100, 250, 500, 1000]
    static let countMilestones = [10, 25, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000]

    /// How many slots in a row, most recent first, were done on time. Slots
    /// still open today, and slots never owed, are skipped; anything late or missed ends the run.
    static func onTimeRun(for routine: CareRoutine, entries: [CareEntry], now: Date, calendar: Calendar, since added: Date?) -> Int {
        guard let first = entries.map(\.time).min() else { return 0 }
        let byDay = byDay(entries, calendar: calendar)
        let firstDay = DayKey(first, calendar: calendar)
        var day = DayKey(now, calendar: calendar)
        var run = 0
        while day >= firstDay {
            for slot in slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar).reversed() {
                switch slot.state {
                case .done(onTime: true): run += 1
                case .upcoming, .open, .due, .future: continue
                case .late, .missed:
                    if isOwed(slot, of: routine, on: day, since: added, calendar: calendar) { return run }
                case .done(onTime: false): return run
                }
            }
            day = day.adding(days: -1, calendar: calendar)
        }
        return run
    }

    /// The next milestone above `value`, e.g. 93 -> 100.
    static func nextMilestone(after value: Int, in steps: [Int]) -> Int {
        if let next = steps.first(where: { $0 > value }) { return next }
        let last = steps.last ?? 100
        return (value / last + 1) * last
    }

    // MARK: Mood

    /// Time between expected care: 12 h for twice a day, 3 days for every 3 days.
    static func interval(for routine: CareRoutine) -> TimeInterval {
        routine.recurrence.averageDaysBetween * 24 * 3600 / Double(routine.slotsPerDay)
    }

    /// 0...1. Peaks right after care, settles, then decays as the time since the last
    /// care approaches 1.25 cadence intervals. Nil before anything was ever logged.
    static func mood(lastCare: Date?, interval: TimeInterval, now: Date) -> Double? {
        guard let lastCare else { return nil }
        let elapsed = max(now.timeIntervalSince(lastCare), 0)
        let freshness = max(0, 1 - elapsed / (1.25 * interval))
        let afterglow = max(0, 1 - elapsed / (45 * 60))
        return min(1, 0.08 + 0.77 * freshness + 0.15 * afterglow)
    }

    // MARK: Expected time

    /// When a slot usually happens: the median time of its recent logs, rounded to
    /// 15 minutes; else a third of the way into the window. Nil for all-day windows.
    static func typicalMinute(slot index: Int, windows: [CareWindow], history: [CareEntry], calendar: Calendar) -> Int? {
        guard windows.indices.contains(index) else { return nil }
        let window = windows[index]
        let minutes = byDay(history, calendar: calendar).values
            .compactMap { assign($0, to: windows, calendar: calendar)[index] }
            .map { minuteOfDay($0.time, calendar: calendar) }
            .sorted()
        if !minutes.isEmpty {
            let median = minutes[minutes.count / 2]
            return Int((Double(median) / 15).rounded()) * 15
        }
        guard !window.isAllDay else { return nil }
        return Int((Double(window.start + (window.end - window.start) / 3) / 15).rounded()) * 15
    }
}
