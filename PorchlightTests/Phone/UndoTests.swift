import Foundation
import Observation
import Testing
@testable import Porchlight

/// Undo on the phone: the toast runs it, and the screen shows it.
@Suite("Undo")
@MainActor
struct UndoTests {
    /// What a reader saw when it heard of the next change.
    final class Seen<Value: Sendable>: @unchecked Sendable {
        var value: Value?
    }

    /// Reads again the moment a change is announced, as SwiftUI may redraw a screen then.
    private func readOnChange<Value: Sendable>(_ read: @escaping @MainActor @Sendable () -> Value) -> Seen<Value> {
        let seen = Seen<Value>()
        withObservationTracking {
            _ = read()
        } onChange: {
            MainActor.assumeIsolated { seen.value = read() }
        }
        return seen
    }

    private func waitFor(_ done: () -> Bool) async {
        for _ in 0..<300 where !done() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A screen redrawn when a check-off or its undo is announced already reads it")
    func observersReadTheNewSnapshot() async throws {
        let db = try AppDatabase.inMemory(installId: "james-phone")
        let household = try db.createHousehold(name: "The Lake House", people: [PersonDraft(name: "James", color: .blue)])
        try db.markSetupCompleted(householdId: household.id)
        try db.rememberCurrentHousehold()
        let james = try #require(try db.snapshot().people.first).id
        let today = DayKey(CompanionClock.now(), calendar: household.calendar)
        _ = try db.saveChore(
            ChoreDraft(title: "Fix the leaky faucet", emoji: "🔧", ownerId: james, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 3),
            householdId: household.id
        )
        let home = HomeStore(database: db)
        let chore = try #require(home.snapshot.chores.first)
        #expect(home.snapshot.completions.isEmpty)

        let checked = readOnChange { home.snapshot.completions.count }
        guard case let .done(completion) = home.complete(chore, by: james) else {
            Issue.record("The chore wasn't checked off")
            return
        }
        await waitFor { checked.value != nil }
        #expect(checked.value == 1)

        let undone = readOnChange { home.snapshot.completions.count }
        home.undo(completion)
        await waitFor { undone.value != nil }
        #expect(undone.value == 0)
    }

    @Test("Undo on a toast already on its way out still runs, once")
    func leavingToastStillRuns() {
        let toasts = ToastCenter()
        var runs = 0
        let toast = UndoToast(emoji: "🔧", title: "Fix the leaky faucet done", action: .init(title: "Undo") { runs += 1 })
        toasts.show(toast)
        // It times out as the tap lands.
        toasts.dismiss()
        #expect(toasts.current == nil)
        toasts.run(toast)
        toasts.run(toast)
        #expect(runs == 1)
    }

    @Test("Undo on the toast that is up takes it away")
    func runningTakesTheToastAway() {
        let toasts = ToastCenter()
        var runs = 0
        let toast = UndoToast(emoji: "🔧", title: "Fix the leaky faucet done", action: .init(title: "Undo") { runs += 1 })
        toasts.show(toast)
        toasts.run(toast)
        #expect(toasts.current == nil)
        #expect(runs == 1)
    }
}
