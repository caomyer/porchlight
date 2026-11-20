import Foundation

/// A slot this week that was never logged. It shows as a faint mark where its record
/// would be (the calendar, Paw trail, the diary), and tapping it logs it for that day.
struct MissedCare: Equatable, Identifiable, Sendable {
    var routine: CareRoutine
    var day: DayKey
    var slot: CareSlot
    /// When it usually happens, on that day.
    var usual: Date

    var id: String { "\(routine.id)-\(day.rawValue)-\(slot.index)" }
}

/// Catching up on care that was never logged. Pure and covered by CareCatchUpTests.
enum CareCatchUp {
    /// Days before today that can be caught up on: the rest of the 7-day week that
    /// Paw trail and the diary show. Older days only show what was logged.
    static let daysBack = 6

    /// Whether `day` is one of the days that can be caught up on.
    static func isCatchUpDay(_ day: DayKey, today: DayKey, calendar: Calendar) -> Bool {
        day < today && day >= today.adding(days: -daysBack, calendar: calendar)
    }

    /// The routine's slots on `day` that were never logged, oldest first. Empty for today
    /// (still expected, not missed) and for days outside the catch-up week.
    static func missed(_ routine: CareRoutine, entries: [CareEntry], on day: DayKey, now: Date, calendar: Calendar, since added: Date? = nil) -> [MissedCare] {
        let today = DayKey(now, calendar: calendar)
        guard isCatchUpDay(day, today: today, calendar: calendar) else { return [] }
        let byDay = CareLogic.byDay(entries, calendar: calendar)
        return CareLogic.slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar)
            .filter { $0.state == .missed && CareLogic.isOwed($0, of: routine, on: day, since: added, now: now, calendar: calendar) }
            .map { slot in
                MissedCare(
                    routine: routine, day: day, slot: slot,
                    usual: usualTime(slot.index, of: routine, on: day, entries: entries, now: now, calendar: calendar)
                )
            }
    }

    /// Every missed slot of `routines` this week, newest day first.
    static func missed(_ routines: [CareRoutine], entries: (CareRoutine) -> [CareEntry], now: Date, calendar: Calendar, since added: Date? = nil) -> [MissedCare] {
        let today = DayKey(now, calendar: calendar)
        return (1...daysBack).flatMap { back in
            let day = today.adding(days: -back, calendar: calendar)
            return routines.flatMap { missed($0, entries: entries($0), on: day, now: now, calendar: calendar, since: added) }
                .sorted { $0.usual > $1.usual }
        }
    }

    /// When a slot usually happens on `day`: its typical time over the two weeks before,
    /// else noon for an all-day slot.
    static func usualTime(_ index: Int, of routine: CareRoutine, on day: DayKey, entries: [CareEntry], now: Date, calendar: Calendar) -> Date {
        let history = entries.filter { $0.time > now.addingTimeInterval(-14 * 24 * 3600) }
        let minute = CareLogic.typicalMinute(slot: index, windows: routine.effectiveWindows, history: history, calendar: calendar) ?? 12 * 60
        return CareLogic.date(day, minute: minute, calendar: calendar)
    }

    /// "yesterday's", "Saturday's".
    static func dayPossessive(_ day: DayKey, today: DayKey, calendar: Calendar) -> String {
        if day == today { return "today's" }
        if day == today.adding(days: -1, calendar: calendar) { return "yesterday's" }
        return day.formatted(.dateTime.weekday(.wide), calendar: calendar) + "'s"
    }

    /// What the slot is called in a sentence: "dinner", "morning walk", "litter".
    static func slotName(_ window: CareWindow, of routine: CareRoutine) -> String {
        if routine.kind == .walk { return window.isAllDay ? "walk" : "\(window.label.lowercased()) walk" }
        if routine.kind == .feed && !window.isAllDay { return window.label.lowercased() }
        let title = routine.title.lowercased()
        return window.isAllDay || routine.slotsPerDay == 1 ? title : "\(window.label.lowercased()) \(title)"
    }

    /// "For yesterday's dinner": the log sheet's subtitle when catching up.
    static func subtitle(_ window: CareWindow, of routine: CareRoutine, on day: DayKey, today: DayKey, calendar: Calendar) -> String {
        "For \(dayPossessive(day, today: today, calendar: calendar)) \(slotName(window, of: routine))"
    }
}
