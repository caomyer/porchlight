import Foundation
import GRDB
import UserNotifications

/// Makes iOS's pending notifications match the planner: removes what is no longer planned
/// (done, handed off, a choice turned off), adds what is new, and leaves the rest alone.
/// Reminders are local: nothing is sent to or from a server, and a change arriving from
/// another device later simply leads to another reschedule.
@MainActor
enum ReminderScheduler {
    static let careCategoryPrefix = "porchlight.care."
    static let logAction = "log"
    static let snoozeAction = "snooze"
    static let handOffAction = "handOff"

    /// Reads every household this phone belongs to, "me" in each and this phone's choices,
    /// plans, and applies the plan. Reminders come from every household, not only the one on
    /// screen, each named by its household when there is more than one (journey A5). The
    /// same path runs from the app and from a notification action with the app closed.
    static func refresh(database: AppDatabase, defaults: UserDefaults = .standard, now: Date = CompanionClock.now()) async {
        let center = UNUserNotificationCenter.current()
        // Only a personal device reminds; a shared screen never asks and never schedules.
        let device = DeviceSettings(defaults: defaults)
        guard device.role == .personal, await NotificationAccess.current() == .allowed else {
            await apply([], settled: [], now: now, center: center)
            return
        }
        var choices = ReminderSettings.load(defaults)
        let households = (try? await database.writer.read { try Household.order(Column("createdAt"), Column("id")).fetchAll($0) }) ?? []
        if let first = households.first {
            choices.prune(before: DayKey(now, calendar: first.calendar).adding(days: -2, calendar: first.calendar))
            ReminderSettings.save(choices, to: defaults)
        }
        var plan: [PlannedReminder] = []
        var settled = Set<String>()
        for household in households {
            let plans = plans(for: household, named: households.count > 1, database: database, device: device, choices: choices, now: now)
            plan += plans.plan
            settled.formUnion(plans.settled)
        }
        await apply(plan, settled: settled, now: now, center: center)
    }

    /// One household's reminders, for this phone's person there. Pure but for the reads.
    static func plans(
        for household: Household, named: Bool, database: AppDatabase, device: DeviceSettings, choices: ReminderChoices, now: Date
    ) -> (plan: [PlannedReminder], settled: Set<String>) {
        guard let companions = try? database.writer.read({ try CompanionSnapshot.fetch($0, householdId: household.id) }) else { return ([], []) }
        let since = DayKey(now, calendar: household.calendar).adding(days: -1, calendar: household.calendar)
        let home = try? database.writer.read { try HomeSnapshot.fetch($0, since: since, householdId: household.id) }
        let me = device.me(in: household.id)
        var plan = ReminderPlanner.plan(
            companions: companions, chores: home?.chores ?? [], completions: home?.completions ?? [],
            me: me, choices: choices, now: now
        )
        #if DEBUG
        if let soon = debugReminder(companions: companions, me: me, now: now) { plan.append(soon) }
        #endif
        if named { plan = plan.map { ReminderPlanner.named($0, household: household.name) } }
        return (plan, ReminderPlanner.settledIDs(companions: companions, now: now))
    }

    #if DEBUG
    /// `-debugReminderIn N`: the day's first care reminder, as if every slot were set to
    /// "if missed", N seconds from now, to check delivery and the actions by hand.
    private static func debugReminder(companions: CompanionSnapshot, me: Person.ID?, now: Date) -> PlannedReminder? {
        let seconds = UserDefaults.standard.double(forKey: "debugReminderIn")
        guard seconds > 0 else { return nil }
        var choices = ReminderChoices(chores: false)
        for slot in ReminderSlots.all(companions) { choices.care[slot.id] = .missed }
        guard var soon = ReminderPlanner.plan(companions: companions, chores: [], completions: [], me: me, choices: choices, now: now).first else { return nil }
        soon.id = PlannedReminder.prefix + "debug." + (companions.household?.id.description ?? "")
        soon.fireDate = now.addingTimeInterval(seconds)
        return soon
    }
    #endif

    private static func apply(_ plan: [PlannedReminder], settled: Set<String>, now: Date, center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(PlannedReminder.prefix) }
        let wanted = Dictionary(plan.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = Dictionary(pending.map { ($0.identifier, $0.content.userInfo["fingerprint"] as? String) }, uniquingKeysWith: { first, _ in first })
        let stale = current.filter { id, fingerprint in wanted[id].map(Self.fingerprint) != fingerprint }.map(\.key)
        center.removePendingNotificationRequests(withIdentifiers: stale)
        // What has been done since a reminder showed leaves the Lock Screen too.
        center.removeDeliveredNotifications(withIdentifiers: Array(settled))
        center.setNotificationCategories(categories(for: plan))
        for reminder in plan where current[reminder.id].map({ $0 != Self.fingerprint(reminder) }) ?? true {
            try? await center.add(request(for: reminder, now: now))
        }
    }

    /// Changes whenever anything shown or the time changes, so only those are replaced.
    private static func fingerprint(_ reminder: PlannedReminder) -> String {
        "\(reminder.fireDate.timeIntervalSince1970)|\(reminder.title)|\(reminder.body)|\(reminder.logTitle ?? "")"
    }

    private static func request(for reminder: PlannedReminder, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        // One thread per household, so each household's reminders stack together.
        content.threadIdentifier = reminder.household.map { "porchlight.\($0)" } ?? "porchlight"
        var info: [String: String] = ["fingerprint": fingerprint(reminder)]
        if case let .care(routine, slot, day) = reminder.kind {
            content.categoryIdentifier = careCategoryPrefix + routine.description
            info["routine"] = routine.description
            info["slot"] = "\(slot)"
            info["day"] = day.rawValue
        }
        #if DEBUG
        if AppFiles.isSandboxed { info["sample"] = "1" }
        #endif
        content.userInfo = info
        // Counted from the planner's "now", which DEBUG builds can pin.
        let interval = max(1, reminder.fireDate.timeIntervalSince(now))
        return UNNotificationRequest(
            identifier: reminder.id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
    }

    /// One category per routine, since the log action says what it logs ("I walked Yo-Yo").
    private static func categories(for plan: [PlannedReminder]) -> Set<UNNotificationCategory> {
        var seen = Set<String>()
        return Set(plan.compactMap { reminder -> UNNotificationCategory? in
            guard case let .care(routine, _, _) = reminder.kind, let logTitle = reminder.logTitle,
                  seen.insert(routine.description).inserted else { return nil }
            return UNNotificationCategory(
                identifier: careCategoryPrefix + routine.description,
                actions: [
                    UNNotificationAction(identifier: logAction, title: logTitle, options: []),
                    UNNotificationAction(identifier: snoozeAction, title: "Remind me in an hour", options: []),
                    UNNotificationAction(identifier: handOffAction, title: "Someone else is on it", options: []),
                ],
                intentIdentifiers: []
            )
        })
    }
}
