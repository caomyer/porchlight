#if DEBUG
import Foundation
import Testing
@testable import Porchlight

/// What the sample household's own calendars pass on, which the UI tests count on:
/// `WallSharedCalendarTests.testJustMeLeavesTheHousehold` sets one to Just me and looks for
/// one fewer, so the number it starts from is held here instead of read on screen.
@MainActor
@Suite("The sample's calendars")
struct CalendarSamplesTests {
    @Test("The sample wall passes on six calendars, and Just me on one leaves five")
    func passesOnSix() async throws {
        let db = try AppDatabase.inMemory(installId: "samples")
        _ = try db.createHousehold(
            name: "Home", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        let snapshot = try db.snapshot()
        let household = try #require(snapshot.household)
        try db.saveThisDevice(ThisDevice(name: "Hallway iPad", role: .sharedScreen, model: "iPad"), in: household.id)
        try CalendarSamples.seed(db, household: household, people: snapshot.people)
        try db.markCalendarChoicesSeen()
        let provider = SampleCalendarProvider(now: PocketSharedCalendarScreenTests.now)
        let store = CalendarStore(database: db, provider: provider, now: { PocketSharedCalendarScreenTests.now }, passesOn: false)
        // The store reads the database a moment after it is made.
        for _ in 0..<50 where !store.snapshot.choicesSeen { try await Task.sleep(for: .milliseconds(100)) }
        let first = store.passOn(.open)
        #expect(first?.calendars == 6, "\(String(describing: first)), access \(provider.access)")

        let mia = try #require(try db.calendarSnapshot().sources.first { $0.title == "Mia" })
        try db.setCalendarSourceSharing(id: mia.id, sharing: .justMe)
        for _ in 0..<50 where store.snapshot.sources.first(where: { $0.id == mia.id })?.sharing != .justMe {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(store.passOn(.open)?.calendars == 5)
    }
}
#endif
