import Foundation

/// A care log with the people who did it.
struct CareEntry: Equatable, Identifiable, Sendable {
    var log: CareLog
    var people: [Int64]

    var id: Int64 { log.id ?? 0 }
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

    /// Fills each window with the first log of the day that belongs to it.
    /// A second log for an already filled window is an extra and fills nothing.
    static func assign(_ dayEntries: [CareEntry], to windows: [CareWindow], calendar: Calendar) -> [CareEntry?] {
        var filled = [CareEntry?](repeating: nil, count: windows.count)
        guard !windows.isEmpty else { return filled }
        for entry in dayEntries.sorted(by: { $0.time < $1.time }) {
            let index = windowIndex(forMinute: minuteOfDay(entry.time, calendar: calendar), in: windows)
            if filled[index] == nil { filled[index] = entry }
        }
        return filled
    }

    /// Whether an every-N-days routine expects care on `day`: nothing logged in the N-1 days before it.
    static func isDue(_ routine: CareRoutine, on day: DayKey, byDay: [DayKey: [CareEntry]], calendar: Calendar) -> Bool {
        guard !routine.isDaily else { return true }
        for back in 1..<routine.everyDays where byDay[day.adding(days: -back, calendar: calendar)]?.isEmpty == false {
            return false
        }
        return true
    }

    /// The slots for a routine on one day, with their state relative to `now`.
    /// An every-N-days routine has no slot on days it isn't due (unless it was logged anyway).
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
        if !routine.isDaily && dayEntries.isEmpty && (day > today || !isDue(routine, on: day, byDay: byDay, calendar: calendar)) {
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

    // MARK: Streak

    /// Consecutive days, ending today, on which every slot was filled. Today
    /// only counts once complete; an unfinished today never breaks the streak.
    static func streak(for routine: CareRoutine, entries: [CareEntry], now: Date, calendar: Calendar) -> Int {
        guard let first = entries.map(\.time).min() else { return 0 }
        let byDay = byDay(entries, calendar: calendar)
        let firstDay = DayKey(first, calendar: calendar)
        var day = DayKey(now, calendar: calendar)
        var count = 0
        if isComplete(routine, on: day, byDay: byDay, now: now, calendar: calendar) { count += 1 }
        day = day.adding(days: -1, calendar: calendar)
        while day >= firstDay, isComplete(routine, on: day, byDay: byDay, now: now, calendar: calendar) {
            count += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return count
    }

    static func isComplete(_ routine: CareRoutine, on day: DayKey, byDay: [DayKey: [CareEntry]], now: Date, calendar: Calendar) -> Bool {
        slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar).allSatisfy(\.isDone)
    }

    // MARK: Weekly stats

    struct WeekStats: Equatable, Sendable {
        var count = 0
        var slotsOnTime = 0
        /// Slots that were due so far this week (today's count once logged or closed).
        var slotsSoFar = 0
        var totalMinutes = 0
        var timedCount = 0
        var pee = 0
        var poo = 0
        var stars = 0

        var averageMinutes: Int? { timedCount > 0 ? Int((Double(totalMinutes) / Double(timedCount)).rounded()) : nil }
    }

    static func weekStats(for routine: CareRoutine, entries: [CareEntry], days: [DayKey], now: Date, calendar: Calendar) -> WeekStats {
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
                    stats.slotsSoFar += 1
                case .upcoming, .open, .due, .future:
                    break
                }
            }
        }
        return stats
    }

    // MARK: Leaderboard

    enum Carer: Hashable, Sendable {
        case person(Int64)
        case together
    }

    struct Standing: Equatable, Sendable {
        var carer: Carer
        var count: Int
    }

    /// Solo logs per person, plus logs done together as their own entry.
    /// Sorted by count, then by household order (`people`), with Together last on ties.
    static func leaderboard(_ entries: [CareEntry], people: [Int64]) -> [Standing] {
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
    /// still open today are skipped; anything late or missed ends the run.
    static func onTimeRun(for routine: CareRoutine, entries: [CareEntry], now: Date, calendar: Calendar) -> Int {
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
                case .done(onTime: false), .late, .missed: return run
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
        routine.isDaily ? 24 * 3600 / Double(routine.slotsPerDay) : Double(routine.everyDays) * 24 * 3600
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
