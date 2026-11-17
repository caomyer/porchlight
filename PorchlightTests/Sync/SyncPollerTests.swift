import Foundation
import Testing
@testable import Porchlight

/// A clock the test moves: each wait is recorded and returns only when the test says.
@MainActor
private final class TestClock {
    private(set) var waits: [Duration] = []
    private var pending: CheckedContinuation<Void, any Error>?

    func sleep(_ duration: Duration) async throws {
        waits.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending = $0 }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    var isWaiting: Bool { pending != nil }

    /// Ends the current wait.
    func advance() {
        pending?.resume()
        pending = nil
    }

    private func cancel() {
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
}

/// A stand-in for asking iCloud: counts checks, and can fail or hold a check open.
@MainActor
private final class FakeFetch {
    var calls = 0
    var fails = false
    var holds = false
    private var held: CheckedContinuation<Void, Never>?

    func run() async throws -> SyncPoller.Outcome {
        calls += 1
        if holds { await withCheckedContinuation { held = $0 } }
        if fails { throw URLError(.notConnectedToInternet) }
        return .checked
    }

    func release() {
        held?.resume()
        held = nil
    }
}

/// Lets the poller's tasks run up to their next wait.
@MainActor
private func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

@Suite("Staying current")
@MainActor
struct SyncPollerTests {
    private func poller(_ clock: TestClock, _ fetch: FakeFetch, role: DeviceRole = .sharedScreen, outcomes: ((SyncPoller.Outcome, Int) -> Void)? = nil) -> SyncPoller {
        let timing = SyncController.Timing()
        return SyncPoller(
            policy: .init(interval: { role == .sharedScreen ? timing.sharedScreenPoll : timing.personalPoll }, maxBackoff: timing.pollBackoff),
            fetch: { try await fetch.run() },
            sleep: { try await clock.sleep($0) },
            onOutcome: { outcomes?($0, $1) }
        )
    }

    @Test("Coming to the front checks at once, then every 15 seconds on a shared screen")
    func sharedScreenInterval() async {
        let clock = TestClock(), fetch = FakeFetch()
        let poller = poller(clock, fetch)
        poller.setActive(true)
        await settle()
        #expect(fetch.calls == 1)
        #expect(clock.waits == [.seconds(15)])
        clock.advance()
        await settle()
        #expect(fetch.calls == 2)
        #expect(clock.waits == [.seconds(15), .seconds(15)])
        poller.stop()
    }

    @Test("Someone's own phone checks every 30 seconds")
    func personalInterval() async {
        let clock = TestClock(), fetch = FakeFetch()
        let poller = poller(clock, fetch, role: .personal)
        poller.setActive(true)
        await settle()
        #expect(clock.waits == [.seconds(30)])
        poller.stop()
    }

    @Test("Leaving the front stops checking, and nothing runs in the background")
    func stopsWhenInactive() async {
        let clock = TestClock(), fetch = FakeFetch()
        let poller = poller(clock, fetch)
        poller.setActive(true)
        await settle()
        poller.setActive(false)
        await settle()
        #expect(!clock.isWaiting)
        clock.advance()
        await settle()
        #expect(fetch.calls == 1)
    }

    @Test("Failures back off, doubling up to five minutes; a success goes back to the interval")
    func backsOff() async {
        let clock = TestClock(), fetch = FakeFetch()
        fetch.fails = true
        var seen: [Int] = []
        let poller = poller(clock, fetch) { _, failures in seen.append(failures) }
        poller.setActive(true)
        await settle()
        for _ in 0..<5 {
            clock.advance()
            await settle()
        }
        #expect(clock.waits == [.seconds(30), .seconds(60), .seconds(120), .seconds(240), .seconds(300), .seconds(300)])
        #expect(seen == [1, 2, 3, 4, 5, 6])
        fetch.fails = false
        clock.advance()
        await settle()
        #expect(poller.failures == 0)
        #expect(clock.waits.last == .seconds(15))
        poller.stop()
    }

    @Test("Two checks never overlap")
    func noOverlap() async {
        let clock = TestClock(), fetch = FakeFetch()
        fetch.holds = true
        let poller = poller(clock, fetch)
        poller.setActive(true)
        await settle()
        #expect(poller.isFetching)
        poller.checkNow()
        await settle()
        #expect(fetch.calls == 1, "a check asked for while one runs doesn't start another")
        fetch.holds = false
        fetch.release()
        await settle()
        #expect(!poller.isFetching)
        poller.stop()
    }

    @Test("Offline it stops; back online it checks at once with the backoff forgotten")
    func offlineAndBack() async {
        let clock = TestClock(), fetch = FakeFetch()
        fetch.fails = true
        let poller = poller(clock, fetch)
        poller.setActive(true)
        await settle()
        #expect(poller.failures == 1)
        poller.setOnline(false)
        await settle()
        #expect(!clock.isWaiting)
        fetch.fails = false
        poller.setOnline(true)
        await settle()
        #expect(fetch.calls == 2)
        #expect(poller.failures == 0)
        #expect(clock.waits.last == .seconds(15))
        poller.stop()
    }

    @Test("Sync starting in the background asks for nothing more: the engine fetches as it starts")
    func checkNowInBackground() async {
        let clock = TestClock(), fetch = FakeFetch()
        let poller = poller(clock, fetch)
        poller.checkNow()
        await settle()
        #expect(fetch.calls == 0)
        #expect(!clock.isWaiting)
    }

    @Test("Sync turned on while in front checks at once and keeps the interval")
    func checkNowInFront() async {
        let clock = TestClock(), fetch = FakeFetch()
        let poller = poller(clock, fetch)
        poller.setActive(true)
        await settle()
        clock.advance()
        await settle()
        poller.checkNow()
        await settle()
        #expect(fetch.calls == 3)
        #expect(clock.isWaiting)
        poller.stop()
    }
}

@Suite("Staying current: what sync says")
@MainActor
struct SyncCheckStatusTests {
    @Test("Checks that keep failing show as waiting, and the next success clears it")
    func failingChecks() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        #expect(controller.status == .upToDate(lastSynced: controller.lastSynced))
        controller.checked(.failed, failures: 1)
        controller.checked(.failed, failures: 2)
        #expect(controller.status == .upToDate(lastSynced: controller.lastSynced), "a couple of misses say nothing")
        controller.checked(.failed, failures: 3)
        #expect(controller.status == .waiting(lastSynced: controller.lastSynced))
        #expect(controller.status.summary.hasPrefix("Can't reach iCloud right now"))
        controller.checked(.checked, failures: 0)
        #expect(controller.status == .upToDate(lastSynced: controller.lastSynced))
    }

    @Test("A check is the last-synced time, moved at most every five minutes when nothing else happens")
    func quietChecks() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        controller.checked(.checked, failures: 0, at: start)
        #expect(controller.lastSynced == start)
        #expect(harness.preferences.lastSynced == start)
        controller.checked(.checked, failures: 0, at: start.addingTimeInterval(4 * 60))
        #expect(controller.lastSynced == start, "a quiet poll redraws nothing")
        controller.checked(.checked, failures: 0, at: start.addingTimeInterval(5 * 60))
        #expect(controller.lastSynced == start.addingTimeInterval(5 * 60))
    }

    @Test("Up to date says when iCloud was last checked")
    func wording() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date.now
        #expect(SyncStatus.upToDate(lastSynced: now).summary.hasPrefix("Up to date, checked at "))
        #expect(SyncStatus.upToDate(lastSynced: nil).summary == "Up to date.")
        #expect(SyncStatus.waiting(lastSynced: now).summary.contains("last reached at"))
        #expect(SyncStatus.waiting(lastSynced: nil).summary == "Can't reach iCloud right now. Changes keep saving on this iPad and go up once it answers.")
    }

    @Test("Without an engine (sample data, unsigned builds) nothing polls")
    func inertWithoutEngine() {
        let defaults = UserDefaults(suiteName: "poll-\(UUID().uuidString)")!
        let controller = SyncController(.unavailable(.sampleData), preferences: SyncPreferences(defaults: defaults), hasHousehold: true, removeFiles: {})
        #expect(controller.poller == nil)
        controller.appActivityChanged(isActive: true)
        #expect(controller.poller == nil)
    }
}
