import BackgroundTasks
import Foundation

/// Sends again later what a background launch couldn't get to iCloud in time: a widget's
/// button, Siri or a reminder's action wrote a log, the app was launched only for that, and
/// the network was slow or gone before iOS suspended it. Without this, the log would wait in
/// the engine until the app next ran for another reason (docs/design/beyond-the-app.md,
/// "How a log from a widget or Siri reaches iCloud").
///
/// It asks iOS for background time a little later (`BGAppRefreshTask`), sends what is
/// pending, and asks again with a longer wait while changes are still waiting, up to
/// `waits.count` times; any send that gets everything up starts it over. iOS decides when
/// the time comes, and gives none with Background App Refresh or Low Power Mode on.
enum SyncSendRetry {
    static let identifier = "com.mingyucao.porchlight.sync.send"

    /// How long each try waits after the one before.
    static let waits: [TimeInterval] = [60, 5 * 60, 15 * 60, 60 * 60]

    private static let attemptsKey = "sync.sendRetryAttempts"

    /// Registers the task; must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let done = UncheckedTask(task: task)
            let work = Task { @MainActor in
                let outcome = await SyncController.current?.sendSoon(timeout: .seconds(25)) ?? .off
                after(outcome)
                done.task.setTaskCompleted(success: outcome != .waiting)
            }
            task.expirationHandler = {
                work.cancel()
                done.task.setTaskCompleted(success: false)
            }
        }
    }

    /// What to do after a send: nothing left, so start over; still waiting, so try again.
    @MainActor
    static func after(_ outcome: SyncController.SendOutcome, defaults: UserDefaults = .standard, submit: (TimeInterval) -> Void = { schedule(after: $0) }) {
        switch outcome {
        case .sent, .off:
            defaults.removeObject(forKey: attemptsKey)
        case .waiting:
            let attempts = defaults.integer(forKey: attemptsKey)
            guard let wait = waits[safe: attempts] else { return }
            defaults.set(attempts + 1, forKey: attemptsKey)
            submit(wait)
        }
    }

    /// Asks iOS for background time `wait` seconds from now; asking again replaces it.
    static func schedule(after wait: TimeInterval) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(wait)
        // The simulator and builds without the background mode refuse; the change then goes
        // up the next time the app runs.
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// The task, carried to the main actor where it is completed.
private struct UncheckedTask: @unchecked Sendable {
    let task: BGTask
}
