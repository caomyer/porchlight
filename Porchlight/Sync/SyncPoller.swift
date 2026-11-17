import Foundation

/// Asks iCloud for changes on a schedule while the app is in front (docs/design/sync-icloud.md,
/// "Staying current"). Pushes are the fast path, but builds installed by cable don't get
/// CloudKit's production pushes and iOS throttles silent pushes anyway, so a screen that
/// must be current can't wait for one.
///
/// It fetches at once when it starts (the app came to the front, the network came back, sync
/// was turned on), then every `interval`, never two at a time. Failures back off, doubling up
/// to `maxBackoff`; offline or in the background it does nothing at all. It is not
/// observable, so a check that finds nothing changes nothing on screen.
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

        /// The wait before the next check after `failures` failed in a row.
        @MainActor func delay(afterFailures failures: Int) -> Duration {
            let base = interval()
            guard failures > 0 else { return base }
            let factor = 1 << min(failures, 16)
            return min(base * factor, maxBackoff)
        }
    }

    private let policy: Policy
    private let fetch: () async throws -> Outcome
    private let sleep: (Duration) async throws -> Void
    private let onOutcome: (Outcome, _ failures: Int) -> Void

    private(set) var isActive = false
    private(set) var isOnline = true
    private(set) var isFetching = false
    /// Checks that failed in a row.
    private(set) var failures = 0
    private var loop: Task<Void, Never>?

    /// - Parameters:
    ///   - fetch: One check; it reports `skipped` when there is nothing to ask.
    ///   - sleep: Waits; tests pass a clock they control.
    ///   - onOutcome: Called after each check with the failures in a row so far.
    init(
        policy: Policy,
        fetch: @escaping () async throws -> Outcome,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onOutcome: @escaping (Outcome, _ failures: Int) -> Void = { _, _ in }
    ) {
        self.policy = policy
        self.fetch = fetch
        self.sleep = sleep
        self.onOutcome = onOutcome
    }

    /// The app came to the front (checks now, then on the interval) or left it (stops).
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { restart() } else { stop() }
    }

    /// Offline it stops; back online it checks at once, with the backoff forgotten.
    func setOnline(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        if online {
            failures = 0
            restart()
        } else {
            stop()
        }
    }

    /// Checks now, then goes on with the interval: sync was just turned on. In the
    /// background it does nothing; starting the engine fetches by itself there.
    func checkNow() {
        if isActive { restart() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    private func restart() {
        stop()
        guard isActive, isOnline else { return }
        loop = Task { [weak self] in
            var first = true
            while !Task.isCancelled {
                if !first {
                    guard let delay = self?.policy.delay(afterFailures: self?.failures ?? 0) else { return }
                    do { try await self?.sleep(delay) } catch { return }
                }
                first = false
                guard !Task.isCancelled, let self else { return }
                await self.check()
            }
        }
    }

    /// One check, unless one is already running.
    private func check() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        let outcome: Outcome
        do {
            outcome = try await fetch()
        } catch {
            // Stopping cancels the check in flight; that is no failure of iCloud's.
            if Task.isCancelled { return }
            outcome = .failed
        }
        switch outcome {
        case .checked: failures = 0
        case .failed: failures += 1
        case .skipped: break
        }
        onOutcome(outcome, failures)
    }
}
