import Foundation

/// How a companion is doing, as its character shows it: one pure rule for every screen
/// (docs/design/companion-characters.md, "Moods follow the day").
///
/// It reads only what the app already knows about today (the slots owed, what was logged
/// and when) and the time of day in the household's calendar. When more than one mood
/// applies, the first of these wins:
///
/// 1. **Waiting, overdue.** A slot that is late, or open past its nudge time, and still owed.
///    Care that is owed and running late is the one thing a face must never hide, so not
///    even a walk logged a minute ago covers a dinner that is late.
/// 2. **Zoomies.** Something was logged within the last hour. It is the thanks for logging,
///    and it only lasts the hour, so it shows over a slot that has merely opened: the card's
///    own words still say that slot is open.
/// 3. **Waiting.** A slot is open now.
/// 4. **Asleep.** It is night (9 PM to 6 AM), or everything owed today is done. Waiting
///    comes first, so at 9 PM a companion whose walk is still owed waits up for it.
/// 5. **Doing fine.** Anything else: the next slot hasn't opened, or nothing is owed today.
enum CharacterMoodRule {
    /// How long a log keeps the zoomies going.
    static let justLogged: TimeInterval = 60 * 60
    /// Night, in minutes of the household's day: from 9 PM until 6 AM.
    static let nightStart = 21 * 60
    static let nightEnd = 6 * 60

    /// A slot today, with what the rule needs of its routine.
    struct Owed: Equatable, Sendable {
        var window: CareWindow
        var isDone: Bool
        /// Minutes into the window after which an open slot is overdue; nil never nudges.
        var nudgeAfterMinutes: Int?

        /// Whether the slot is waiting at `minute` of the day, and whether it is overdue.
        func standing(at minute: Int) -> (waits: Bool, overdue: Bool) {
            guard !isDone, minute >= window.start else { return (false, false) }
            let late = minute > window.end
            let nudged = nudgeAfterMinutes.map { minute >= window.start + $0 } ?? false
            // An all-day slot is never "late": it has the whole day, and only its nudge hurries it.
            return (true, window.isAllDay ? nudged : late || nudged)
        }
    }

    /// The rule itself. `owed` are today's slots that are owed at all, `lastLogged` the
    /// newest log of any of the companion's routines, `minute` the minute of the household's day.
    static func mood(owed: [Owed], lastLogged: Date?, now: Date, minute: Int) -> CharacterMood {
        let standings = owed.map { $0.standing(at: minute) }
        if standings.contains(where: \.overdue) { return .waiting }
        if let lastLogged, lastLogged <= now, now.timeIntervalSince(lastLogged) < justLogged { return .zoomies }
        if standings.contains(where: \.waits) { return .waiting }
        let isNight = minute >= nightStart || minute < nightEnd
        if isNight || (!owed.isEmpty && owed.allSatisfy(\.isDone)) { return .asleep }
        return .fine
    }

    /// The mood of a companion at `now`, from its report. The report's slots are today's as
    /// of when it was made; once `now` is another day they say nothing, and only the time of
    /// day and the last log speak.
    static func mood(for report: CompanionReport, now: Date) -> CharacterMood {
        let calendar = report.calendar
        let routines = [report.primary].compactMap { $0 } + report.others
        let isSameDay = DayKey(now, calendar: calendar) == report.today
        let owed: [Owed] = isSameDay ? routines.flatMap { today in
            today.slots
                // A slot whose window closed before the companion arrived was never owed.
                .filter { CareLogic.isOwed($0, of: today.routine, on: report.today, since: report.companion.createdAt, now: now, calendar: calendar) }
                .map { Owed(window: $0.window, isDone: $0.isDone, nudgeAfterMinutes: today.routine.nudgeAfterMinutes) }
        } : []
        return mood(
            owed: owed,
            lastLogged: routines.compactMap { $0.lastEntry?.time }.max(),
            now: now,
            minute: CareLogic.minuteOfDay(now, calendar: calendar)
        )
    }
}

extension CompanionReport {
    /// The companion's mood at the report's own moment, for its character.
    var characterMood: CharacterMood { CharacterMoodRule.mood(for: self, now: now) }
}
