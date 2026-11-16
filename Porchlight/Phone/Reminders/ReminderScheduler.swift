import Foundation
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

    /// Reads the household, "me" and this phone's choices, plans, and applies the plan.
    /// The same path runs from the app and from a notification action with the app closed.
    static func refresh(database: AppDatabase, defaults: UserDefaults = .standard, now: Date = CompanionClock.now()) async {
        let center = UNUserNotificationCenter.current()
        guard let companions = try? await database.writer.read(CompanionSnapshot.fetch), let household = companions.household else {
            await apply([], settled: [], now: now, center: center)
            return
        }
        // Only a personal device reminds; a shared screen never asks and never schedules.
        let device = DeviceSettings(defaults: defaults)
        guard device.role == .personal, await NotificationAccess.current() == .allowed else {
            await apply([], settled: [], now: now, center: center)
            return
        }
        var choices = ReminderSettings.load(defaults)
        choices.prune(before: DayKey(now, calendar: household.calendar).adding(days: -1, calendar: household.calendar))
        ReminderSettings.save(choices, to: defaults)
        let home = try? database.homeSnapshot(since: DayKey(now, calendar: household.calendar).adding(days: -1, calendar: household.calendar))
        var plan = ReminderPlanner.plan(
            companions: companions, chores: home?.chores ?? [], completions: home?.completions ?? [],
            me: device.me(in: household.id), choices: choices, now: now
        )
        #if DEBUG
        if let soon = debugReminder(companions: companions, me: device.me(in: household.id), now: now) { plan.append(soon) }
        #endif
        await apply(plan, settled: ReminderPlanner.settledIDs(companions: companions, now: now), now: now, center: center)
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
        soon.id = PlannedReminder.prefix + "debug"
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
        content.threadIdentifier = "porchlight"
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
