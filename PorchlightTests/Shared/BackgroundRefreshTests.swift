#if DEBUG
import Foundation
import os
import Testing
@testable import Porchlight

/// The work iOS wakes the app for (`BackgroundRefresh`): iOS starts it on a queue of its own
/// and may expire it on another, the work itself runs on the main actor, and iOS hears that
/// it ended exactly once.
@Suite("Background refresh")
struct BackgroundRefreshTests {
    /// What iOS was told, in order.
    private final class Answers: Sendable {
        private let said = OSAllocatedUnfairLock(initialState: [Bool]())
        func add(_ success: Bool) { said.withLock { $0.append(success) } }
        var all: [Bool] { said.withLock { $0 } }
    }

    /// Starts a run the way iOS does: from a queue that is not the main one.
    private func startOffMain(_ run: BackgroundRefresh.Run) async {
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                run.start()
                started.resume()
            }
        }
    }

    @Test("Started from a queue of iOS's own, the work runs on the main thread and iOS hears its answer once")
    func worksOffMain() async {
        let answers = Answers()
        let (ended, end) = AsyncStream.makeStream(of: Void.self)
        let run = BackgroundRefresh.Run(work: {
            #expect(pthread_main_np() != 0)
            return true
        }, complete: { success in
            answers.add(success)
            end.yield()
        })
        await startOffMain(run)
        for await _ in ended { break }
        // An expiry that comes after the work ended says nothing more.
        run.expire()
        #expect(answers.all == [true])
    }

    @Test("When iOS runs out of patience first, it hears no once, the work is cancelled, and the work's own ending says nothing more")
    func expiresFirst() async {
        let answers = Answers()
        let (events, event) = AsyncStream.makeStream(of: String.self)
        let run = BackgroundRefresh.Run(work: {
            event.yield("started")
            // Waits as a send to iCloud would, until it is cancelled.
            try? await Task.sleep(for: .seconds(60))
            event.yield(Task.isCancelled ? "cancelled" : "ran out")
            return true
        }, complete: { answers.add($0) })
        await startOffMain(run)
        var seen: [String] = []
        for await name in events {
            seen.append(name)
            if name == "started" {
                DispatchQueue.global().async { run.expire() }
            } else {
                break
            }
        }
        #expect(seen == ["started", "cancelled"])
        // The work's own answer comes just after its last line: give the main actor a turn.
        await MainActor.run {}
        await MainActor.run {}
        #expect(answers.all == [false])
    }
}
#endif
