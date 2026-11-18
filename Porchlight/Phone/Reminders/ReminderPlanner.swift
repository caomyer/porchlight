import Foundation

/// One local notification the phone should have pending.
struct PlannedReminder: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A care slot on a day, for a routine this person looks after.
        case care(routine: CareRoutine.ID, slot: Int, day: DayKey)
        /// My chores due on a day, the evening before.
        case chores(day: DayKey)
    }

    /// Stable: the same reminder always has the same id, so rescheduling only changes
    /// what changed. Every id starts with `PlannedReminder.prefix`.
    var id: String
    var kind: Kind
    var fireDate: Date
    var title: String
    var body: String
    /// The log action's title on a care reminder: "I walked Yo-Yo".
    var logTitle: String?
    /// The household's name, set when the phone is in more than one; the title starts with it.
    var household: String?

    static let prefix = "porchlight.reminder."
}

/// Which notifications this phone should have pending, worked out from the household's
/// data, who "me" is, this phone's choices and the time. Pure, so it can be tested; the
/// scheduler only makes iOS's pending list match it.
///
/// Rules (the atlas's C1 and rule 3): only what this person chose, only their own
/// chores, never for something already done or handed off, nothing when "me" has been
/// removed from the household.
enum ReminderPlanner {
    /// iOS keeps at most 64 pending local notifications per app.
    static let limit = 64
    /// How far ahead to plan. Reschedules happen daily at the latest, on every launch.
    static let horizonDays = 7
    /// When "my chores" remind, the evening before.
    static let choresMinute = 19 * 60
    /// An all-day slot reminds at 9 am when it opens, and at 7 pm if it was missed.
    static let allDayOpens = 9 * 60
    static let allDayMissed = 19 * 60

    static func plan(
        companions: CompanionSnapshot,
        chores: [Chore],
        completions: [ChoreCompletion],
        me: Person.ID?,
        choices: ReminderChoices,
        now: Date,
        limit: Int = limit
    ) -> [PlannedReminder] {
        guard let me, companions.people.contains(where: { $0.id == me }) else { return [] }
        let calendar = companions.calendar
        let today = DayKey(now, calendar: calendar)
        let days = (0..<horizonDays).map { today.adding(days: $0, calendar: calendar) }
        let planned = care(companions, days: days, choices: choices, now: now, calendar: calendar)
            + (choices.chores ? self.chores(chores, completions: completions, me: me, days: days, now: now, calendar: calendar) : [])
        return Array(planned.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(limit))
    }

    /// Reminders that may already be showing (yesterday's and today's) for something that
    /// has since been done, so they can be taken off the Lock Screen too.
    /// The same reminder, prefixed with its household's name: "Grandma Rosa's · Water the
    /// tomatoes", for a phone in more than one household (journey A5's `a5notif`).
    static func named(_ reminder: PlannedReminder, household: String) -> PlannedReminder {
        var named = reminder
        named.household = household
        named.title = "\(household) · \(reminder.title)"
        return named
    }

    static func settledIDs(companions: CompanionSnapshot, now: Date) -> Set<String> {
        let calendar = companions.calendar
        let today = DayKey(now, calendar: calendar)
        var ids = Set<String>()
        for routine in companions.routines {
            let byDay = CareLogic.byDay(companions.entries(of: routine.id), calendar: calendar)
            for day in [today.adding(days: -1, calendar: calendar), today] {
                for slot in CareLogic.slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar) where slot.isDone {
                    ids.insert(PlannedReminder.prefix + "care.\(ReminderChoices.dayKey(routine.id, slot: slot.index, day: day))")
                }
            }
        }
        return ids
    }

    // MARK: Care

    private static func care(_ snapshot: CompanionSnapshot, days: [DayKey], choices: ReminderChoices, now: Date, calendar: Calendar) -> [PlannedReminder] {
        snapshot.routines.flatMap { routine -> [PlannedReminder] in
            guard let companion = snapshot.companions.first(where: { $0.id == routine.companionId }) else { return [] }
            let windows = routine.effectiveWindows
            let chosen = windows.indices.filter { choices.timing(routine.id, slot: $0) != .off }
            guard !chosen.isEmpty else { return [] }
            let byDay = CareLogic.byDay(snapshot.entries(of: routine.id), calendar: calendar)
            return days.flatMap { day -> [PlannedReminder] in
                let slots = CareLogic.slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar)
                return chosen.compactMap { index -> PlannedReminder? in
                    // No slot that day (not due), or already done: nothing to remind.
                    guard let slot = slots[safe: index], !slot.isDone else { return nil }
                    let dayKey = ReminderChoices.dayKey(routine.id, slot: index, day: day)
                    guard !choices.handedOff.contains(dayKey) else { return nil }
                    let timing = choices.timing(routine.id, slot: index)
                    let window = slot.window
                    let snooze = choices.snoozes[dayKey].flatMap { $0 > now ? $0 : nil }
                    let minute = switch timing {
                    case .missed: window.isAllDay ? allDayMissed : window.end
                    case .opens, .off: window.isAllDay ? allDayOpens : window.start
                    }
                    let fireDate = snooze ?? CareLogic.date(day, minute: minute, calendar: calendar)
                    guard fireDate > now else { return nil }
                    return PlannedReminder(
                        id: PlannedReminder.prefix + "care.\(dayKey)",
                        kind: .care(routine: routine.id, slot: index, day: day),
                        fireDate: fireDate,
                        title: "\(companion.name.possessive) \(CareCatchUp.slotName(window, of: routine))",
                        body: careBody(window, timing: timing, snoozed: snooze != nil),
                        logTitle: routine.kind.buttonTitle(name: companion.name, title: routine.title)
                    )
                }
            }
        }
    }

    /// "Open until 8pm. Nobody has logged it yet."
    static func careBody(_ window: CareWindow, timing: CareReminderTiming, snoozed: Bool) -> String {
        if snoozed { return "Reminding you, as you asked. Nobody has logged it yet." }
        if window.isAllDay { return timing == .missed ? "Due today, and nobody has logged it yet." : "Due today. Nobody has logged it yet." }
        let end = window.end >= 24 * 60 ? "midnight" : CareTime.hour(window.end)
        return timing == .missed
            ? "Nobody logged it before \(end)."
            : "Open until \(end). Nobody has logged it yet."
    }

    // MARK: Chores

    /// One reminder the evening before each day that has chores of mine due, leaving out
    /// the ones that repeat every day (an every-evening buzz is noise, rule 3).
    private static func chores(_ chores: [Chore], completions: [ChoreCompletion], me: Person.ID, days: [DayKey], now: Date, calendar: Calendar) -> [PlannedReminder] {
        let mine = chores.filter { $0.ownerId == me && !$0.archived && $0.recurrence != .daily }
        return days.dropFirst().compactMap { day -> PlannedReminder? in
            let due = mine.filter { chore in
                let done = completions.contains { $0.choreId == chore.id && (chore.recurrence.isOnce || $0.dayKey == day) }
                guard !done else { return false }
                return chore.recurrence.isOnce ? chore.anchor == day : ChoreSchedule.occurs(chore, on: day, calendar: calendar)
            }
            guard !due.isEmpty else { return nil }
            let eve = day.adding(days: -1, calendar: calendar)
            let fireDate = CareLogic.date(eve, minute: choresMinute, calendar: calendar)
            guard fireDate > now else { return nil }
            let weekday = day.formatted(.dateTime.weekday(.wide), calendar: calendar)
            let titles = due.map(\.title)
            return PlannedReminder(
                // Per household: two households' chores on the same day are two reminders.
                id: PlannedReminder.prefix + "chores.\(due[0].householdId).\(day.rawValue)",
                kind: .chores(day: day),
                fireDate: fireDate,
                title: due.count == 1 ? "Tomorrow: \(titles[0])" : "Tomorrow: \(due.count) chores",
                body: due.count == 1
                    ? "Your chore for \(weekday). \(StarWords.earned(due[0].stars))."
                    : "Your chores for \(weekday): \(ListFormatter.localizedString(byJoining: titles)).",
                logTitle: nil
            )
        }
    }
}
