import BackgroundTasks
import Foundation
import os

/// The work iOS wakes the app for when nobody is using it (`BGAppRefreshTask`): registered,
/// started and ended in this one place.
///
/// iOS calls a task's handler on a queue of its own, never the main one. A handler written
/// inside a main-actor type is itself main-actor, and Swift 6 stops the app at the handler's
/// first line when anything else calls it. The widgets' turn to the new day was written that
/// way, so the app crashed just after midnight on phones where nobody had it open ("Porchlight
/// crashed", seen the next morning). So the handler here belongs to no actor and only starts
/// the work, and the work runs on the main actor. Register background work through this and
/// nowhere else.
///
/// iOS is also told that a task ended exactly once: by the work when it ends, or by the
/// expiry when iOS runs out of patience first, whichever comes first. The expiry cancels the
/// work, and what the work says when it then ends goes nowhere.
enum BackgroundRefresh {
    /// Registers `work` for `identifier`; must run before the app finishes launching. The
    /// work answers whether it succeeded.
    static func register(_ identifier: String, work: @escaping @MainActor @Sendable () async -> Bool) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let task = UncheckedTask(task: task)
            let run = Run(work: work) { task.task.setTaskCompleted(success: $0) }
            task.task.expirationHandler = { run.expire() }
            run.start()
        }
    }

    /// One waking: the work, and the one answer iOS gets about it. Safe from any thread,
    /// since iOS starts it on one queue and may expire it on another.
    final class Run: Sendable {
        private struct State {
            var ended = false
            var task: Task<Void, Never>?
        }

        private let work: @MainActor @Sendable () async -> Bool
        private let complete: @Sendable (Bool) -> Void
        private let state = OSAllocatedUnfairLock(initialState: State())

        init(work: @escaping @MainActor @Sendable () async -> Bool, complete: @escaping @Sendable (Bool) -> Void) {
            self.work = work
            self.complete = complete
        }

        /// Starts the work on the main actor, from whatever thread this is called on.
        func start() {
            let task = Task { @MainActor in
                let succeeded = await work()
                end(succeeded)
            }
            state.withLock { $0.task = task }
        }

        /// iOS ran out of patience: the work is cancelled and iOS is told it didn't succeed.
        func expire() {
            state.withLock { $0.task }?.cancel()
            end(false)
        }

        private func end(_ succeeded: Bool) {
            let first = state.withLock { state in
                defer { state.ended = true }
                return !state.ended
            }
            if first { complete(succeeded) }
        }
    }
}

/// The task, carried into the closures that end it.
private struct UncheckedTask: @unchecked Sendable {
    let task: BGTask
}
