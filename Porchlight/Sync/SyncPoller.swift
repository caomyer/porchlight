import Foundation

/// Asks iCloud for changes on a schedule while the app is in front (docs/design/sync-icloud.md,
/// "Staying current"). Pushes are the fast path, but builds installed by cable don't get
/// CloudKit's production pushes and iOS throttles silent pushes anyway, so a screen that
/// must be current can't wait for one.
///
/// It fetches at once when it starts (the app came to the front, the network came back, sync
/// was turned on), then every `interval`, never two at a time. A check that takes longer than
/// `timeout` counts as failed, so a fetch that never returns can't stop the checks.
/// Failures back off, doubling up to `maxBackoff`; offline or in the background it does
/// nothing at all. It is not observable, so a check that finds nothing changes nothing on
/// screen.
@MainActor
final class SyncPoller {
    enum Outcome: Equatable, Sendable {
        /// iCloud answered.
        case checked
        /// Sync isn't running, so there was nothing to ask.
        case skipped
        case failed
    }

    struct Policy {
        /// The time between checks, read before each wait so a role change applies at once.
        var interval: @MainActor () -> Duration
        var maxBackoff: Duration = .seconds(5 * 60)
        /// The longest one check may take.
        var timeout: Duration = .seconds(60)

        /// The wait before the next check after `failures` failed in a row.
        @MainActor func delay(afterFailures failures: Int) -> Duration {
            let base = interval()
            guard failures > 0 else { return base }
            let factor = 1 << min(failures, 16)
            return min(base * factor, maxBackoff)
        }
    }

    struct TimedOut: Error {}

    /// What started a check, for the log and "Sync details".
    enum Trigger: String, Sendable {
        case launch = "launch"
        case cameToFront = "came to front"
        case timer = "timer"
        case networkBack = "network back"
        case turnedOn = "sync turned on"
        case push = "push"
        case manual = "check now"
    }

    private let policy: Policy
    private let fetch: @MainActor @Sendable () async throws -> Outcome
    private let sleep: (Duration) async throws -> Void
    private let timeoutSleep: @Sendable (Duration) async throws -> Void
    private let onOutcome: (Outcome, _ failures: Int, _ error: (any Error)?, _ trigger: Trigger) -> Void
    private let onWait: (Duration) -> Void

    private(set) var isActive = false
    private(set) var isOnline = true
    private(set) var isFetching = false
    /// Checks that failed in a row.
    private(set) var failures = 0
    private var loop: Task<Void, Never>?

    /// - Parameters:
    ///   - fetch: One check; it reports `skipped` when there is nothing to ask.
    ///   - sleep: Waits between checks; tests pass a clock they control.
    ///   - timeoutSleep: Waits out a check's timeout.
    ///   - onOutcome: Called after each check with the failures in a row so far and the error.
    ///   - onWait: Called with each wait before it starts, for "next check".
    init(
        policy: Policy,
        fetch: @escaping @MainActor @Sendable () async throws -> Outcome,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        timeoutSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onOutcome: @escaping (Outcome, _ failures: Int, _ error: (any Error)?, _ trigger: Trigger) -> Void = { _, _, _, _ in },
        onWait: @escaping (Duration) -> Void = { _ in }
    ) {
        self.policy = policy
        self.fetch = fetch
        self.sleep = sleep
        self.timeoutSleep = timeoutSleep
        self.onOutcome = onOutcome
        self.onWait = onWait
    }

    /// The app came to the front (checks now, then on the interval) or left it (stops).
    func setActive(_ active: Bool, trigger: Trigger = .cameToFront) {
        guard active != isActive else { return }
        isActive = active
        if active { restart(trigger) } else { stop() }
    }

    /// Offline it stops; back online it checks at once, with the backoff forgotten.
    func setOnline(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        if online {
            failures = 0
            restart(.networkBack)
        } else {
            stop()
        }
    }

    /// Checks now, then goes on with the interval: sync was just turned on. In the
    /// background it does nothing; starting the engine fetches by itself there.
    func checkNow(_ trigger: Trigger = .turnedOn) {
        if isActive { restart(trigger) }
    }

    /// One check now, in front or not (a push, "Check now"), unless one is running; the
    /// schedule goes on as it was.
    func checkOnce(_ trigger: Trigger) async {
        guard isOnline else { return }
        await check(trigger)
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func restart(_ trigger: Trigger) {
        stop()
        guard isActive, isOnline else { return }
        loop = Task { [weak self] in
            var first = true
            var trigger = trigger
            while !Task.isCancelled {
                if !first {
                    guard let self else { return }
                    let delay = self.policy.delay(afterFailures: self.failures)
                    self.onWait(delay)
                    do { try await self.sleep(delay) } catch { return }
                }
                first = false
                guard !Task.isCancelled, let self else { return }
                await self.check(trigger)
                trigger = .timer
            }
        }
    }

    /// One check, unless one is already running.
    private func check(_ trigger: Trigger) async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        var outcome: Outcome
        var failure: (any Error)?
        do {
            outcome = try await withTimeout()
        } catch {
            // Stopping cancels the check in flight; that is no failure of iCloud's.
            if Task.isCancelled { return }
            outcome = .failed
            failure = error
        }
        switch outcome {
        case .checked: failures = 0
        case .failed: failures += 1
        case .skipped: break
        }
        onOutcome(outcome, failures, failure, trigger)
    }

    private func withTimeout() async throws -> Outcome {
        let timeout = policy.timeout
        let wait = timeoutSleep, run = fetch
        // Not a task group: a group waits for every child, so a fetch that ignores being
        // cancelled would hold the check forever. Here the timeout answers by itself and
        // the fetch is cancelled and left to end on its own.
        let answer = Answer()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                answer.continuation = continuation
                answer.fetch = Task { @MainActor in
                    do { answer.resume(.success(try await run())) } catch { answer.resume(.failure(error)) }
                }
                answer.timer = Task { @MainActor in
                    guard (try? await wait(timeout)) != nil else { return }
                    answer.resume(.failure(TimedOut()))
                }
            }
        } onCancel: {
            Task { @MainActor in answer.resume(.failure(CancellationError())) }
        }
    }
}

/// The first of a check's answer, its timeout or its cancellation, delivered once.
@MainActor
private final class Answer {
    var continuation: CheckedContinuation<SyncPoller.Outcome, any Error>?
    var fetch: Task<Void, Never>?
    var timer: Task<Void, Never>?

    func resume(_ result: Result<SyncPoller.Outcome, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        fetch?.cancel()
        timer?.cancel()
        continuation.resume(with: result)
    }
}
