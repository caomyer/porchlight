import Foundation
import GRDB
import UIKit
import UserNotifications

/// Receives Porchlight's notification actions, also when the app isn't running: iOS
/// launches it in the background, the app opens its data the usual way, and this does the
/// work without any screen. The app delegate makes it the notification center's delegate.
final class ReminderNotifications: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ReminderNotifications()

    // The completion-handler forms, not the async ones: UIKit asserts when the async form
    // finishes off the main thread, which it does when the app was launched for an action.

    /// While Porchlight is open, a reminder still shows as a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let routine = (info["routine"] as? String).flatMap(CareRoutine.ID.init)
        let slot = (info["slot"] as? String).flatMap(Int.init)
        let day = (info["day"] as? String).map(DayKey.init(rawValue:))
        let fromSample = info["sample"] as? String == "1"
        let done = UncheckedCompletion(run: completionHandler)
        Task { @MainActor in
            if let routine, let slot, let day {
                await ReminderActions.handle(action, routine: routine, slot: slot, day: day, fromSample: fromSample)
            }
            done.run()
        }
    }
}

/// The app couldn't open its data at launch, so an action has nothing to write to.
private enum ReminderActionError: Error {
    case notOpen
}

/// UIKit's completion handler, carried to the main actor where it is called.
private struct UncheckedCompletion: @unchecked Sendable {
    let run: () -> Void
}

/// What each action on a care reminder does. Logging goes through the same write as the
/// phone's one tap, which checks the slot first (rule 10), so a reminder acted on late
/// never adds a second log.
@MainActor
enum ReminderActions {
    static func handle(_ action: String, routine: CareRoutine.ID, slot: Int, day: DayKey, fromSample: Bool = false, defaults: UserDefaults = .standard) async {
        guard let database = try? database(fromSample: fromSample) else { return }
        let now = CompanionClock.now()
        switch action {
        case ReminderScheduler.logAction:
            await log(routine: routine, slot: slot, day: day, database: database, defaults: defaults, now: now)
        case ReminderScheduler.snoozeAction:
            var choices = ReminderSettings.load(defaults)
            choices.snoozes[ReminderChoices.dayKey(routine, slot: slot, day: day)] = now.addingTimeInterval(3600)
            ReminderSettings.save(choices, to: defaults)
        case ReminderScheduler.handOffAction:
            var choices = ReminderSettings.load(defaults)
            choices.handedOff.insert(ReminderChoices.dayKey(routine, slot: slot, day: day))
            ReminderSettings.save(choices, to: defaults)
        default:
            return
        }
        await ReminderScheduler.refresh(database: database, defaults: defaults, now: now)
    }

    /// The app's database; a reminder from a DEBUG sample launch reaches the sample data.
    private static func database(fromSample: Bool) throws -> AppDatabase {
        #if DEBUG
        if fromSample && !AppFiles.isSandboxed { return try AppDatabase.openOnDisk(folder: AppFiles.sampleRoot) }
        #endif
        guard let launched = AppDatabase.launched else { throw ReminderActionError.notOpen }
        return launched
    }

    private static func log(routine: CareRoutine.ID, slot: Int, day: DayKey, database: AppDatabase, defaults: UserDefaults, now: Date) async {
        guard let confirmation = await logSlot(routine: routine, slot: slot, day: day, database: database, defaults: defaults, now: now) else { return }
        // As for a widget's button: the widgets update, and the log goes to iCloud before
        // iOS suspends the app, or is tried again a little later.
        await IntentRunner.afterWrite()
        let content = UNMutableNotificationContent()
        content.title = confirmation.title
        content.body = confirmation.body
        content.threadIdentifier = "porchlight"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "porchlight.logged.\(UUID().uuidString)", content: content, trigger: nil)
        )
    }

    /// What the log action says afterwards.
    struct Confirmation: Equatable {
        var title: String
        var body: String
    }

    /// The log action's write, credited to this device's person and stamped with this
    /// device like every other phone write. Nil when there is no one to credit.
    static func logSlot(routine routineId: CareRoutine.ID, slot: Int, day: DayKey, database: AppDatabase, defaults: UserDefaults, now: Date) async -> Confirmation? {
        // The routine's own household, which needn't be the one on screen: reminders come
        // from every household this phone belongs to (journey A5).
        guard let snapshot = try? await database.writer.read({ db -> CompanionSnapshot? in
                  guard let householdId = try Household.ID.fetchOne(db, sql: """
                      SELECT companion.householdId FROM careRoutine JOIN companion ON companion.id = careRoutine.companionId
                      WHERE careRoutine.id = ?
                      """, arguments: [routineId]) else { return nil }
                  return try CompanionSnapshot.fetch(db, householdId: householdId)
              }) ?? nil,
              let household = snapshot.household,
              let me = DeviceSettings(defaults: defaults).me(in: household.id),
              let routine = snapshot.routines.first(where: { $0.id == routineId }),
              let companion = snapshot.companions.first(where: { $0.id == routine.companionId }) else { return nil }
        let draft = CareLogDraft(people: [me], occurredAt: now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        let slotName = CareCatchUp.slotName(routine.effectiveWindows[safe: slot] ?? .anyTime, of: routine)
        switch try? database.logCare(routineId: routineId, slot: slot, on: day, draft, now: now) {
        case .logged:
            return Confirmation(title: "Logged: \(slotName)", body: "Credited to you at \(CareText.timeWithPeriod(now, calendar: snapshot.calendar)).")
        case let .alreadyLogged(entry):
            return Confirmation(
                title: PocketToday.alreadyDone(entry, words: CareWords(routine, species: companion.species), companion: companion.name, me: me, names: snapshot.names, calendar: snapshot.calendar),
                body: "Already logged, so nothing was added."
            )
        case nil:
            return Confirmation(title: "That didn't save", body: "Open Porchlight to log \(companion.name.possessive) \(slotName).")
        }
    }
}
