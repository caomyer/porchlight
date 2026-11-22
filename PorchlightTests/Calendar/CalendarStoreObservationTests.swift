import Foundation
import Observation
import Testing
@testable import Porchlight

/// What redraws when the shared calendar changes. A pass writes this device's feed every
/// time; the settings' table of this device's own calendars must not redraw for it, or a
/// menu open in it loses the tap it is given (FirstRunTests failed so in run 45013168902:
/// "Calendar should now belong to Mia", the owner menu still open).
@MainActor
@Suite("The calendar store: a pass redraws only what shows the household's calendar")
struct CalendarStoreObservationTests {
    /// Whether reading `read` registers for a change that `change` then makes: the database's
    /// answer reaches the store a moment later, so this waits up to ten seconds for it (two
    /// were enough on a development Mac; a hosted one has taken longer over less), and the
    /// whole ten before saying no change came.
    private func notifies(_ read: @escaping () -> Void, when change: () async throws -> Void) async throws -> Bool {
        let told = Told()
        withObservationTracking(read) { told.value = true }
        try await change()
        for _ in 0..<100 where !told.value { try await Task.sleep(for: .milliseconds(100)) }
        return told.value
    }

    private final class Told: @unchecked Sendable { var value = false }

    private func store() throws -> (CalendarStore, AppDatabase, Household) {
        let db = try AppDatabase.inMemory(installId: "observation")
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "Mia", color: .coral)])
        try db.saveThisDevice(ThisDevice(name: "Hallway iPad", role: .sharedScreen, model: "iPad"), in: household.id)
        try db.syncCalendarSources(householdId: household.id, calendars: SharedCalendarFixture.calendars)
        try db.markCalendarChoicesSeen()
        let provider = FixedCalendarProvider(calendars: SharedCalendarFixture.calendars, events: SharedCalendarFixture.events)
        let store = CalendarStore(database: db, provider: provider, now: { SharedCalendarFixture.now }, passesOn: false)
        return (store, db, household)
    }

    @Test("A pass leaves the calendar choices alone, and tells what shows the household's calendar")
    func passLeavesChoicesAlone() async throws {
        let (store, _, _) = try store()
        try await Task.sleep(for: .milliseconds(300))
        let choices = Told(), shared = Told()
        withObservationTracking({ _ = store.mappings }) { choices.value = true }
        withObservationTracking({ _ = store.shared }) { shared.value = true }
        // The first pass writes the feed, the calendars and their events.
        #expect(store.passOn(.open)?.events == SharedCalendarFixture.events.count)
        for _ in 0..<100 where !shared.value { try await Task.sleep(for: .milliseconds(100)) }
        #expect(shared.value, "what shows the household's calendar is told")
        #expect(!choices.value, "the table of this device's calendars isn't")
    }

    @Test("Changing a calendar's owner tells the table")
    func ownerChangeNotifies() async throws {
        let (store, _, _) = try store()
        try await Task.sleep(for: .milliseconds(300))
        // The work calendar, guessed as Mia's from her account, given to the whole household.
        let work = try #require(store.mappings.first { $0.calendar.id == "mia-work" }?.source)
        #expect(work.ownerId != nil)
        #expect(try await notifies({ _ = store.mappings }) { store.setOwner(.everyone, for: work) })
    }
}
