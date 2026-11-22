#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The phone's Next 7 days with what another device passed on (docs/design/calendar-shared.md,
/// "Showing"), hosted in the unit bundle: Mia's work as one quiet row a day, her own events,
/// her Busy only one, and, when her phone has been quiet two days, the line that says so.
/// The clock is pinned, so the days and times are always the same.
@Suite("The phone's household calendar: the quiet row and the stale line")
@MainActor
struct PocketSharedCalendarScreenTests {
    /// Tuesday, Nov 24, 2026, 08:00 in Los Angeles.
    static let now = Date(timeIntervalSince1970: 1_795_536_000)

    private func page(_ value: String, _ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "shared-calendar")
        var household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        household.timeZoneIdentifier = "America/Los_Angeles"
        try await db.writer.write { [household] db in try household.update(db) }
        let snapshot = try db.snapshot()
        try CalendarSamples.seedShared(db, household: try #require(snapshot.household), people: snapshot.people, now: Self.now, value: value)
        let model = AppModel(database: db)
        let store = CalendarStore(
            database: db, provider: FixedCalendarProvider(calendars: [], events: []), now: { Self.now }, passesOn: false
        )
        let hosted = try await HostedScreen.host(
            PocketNextWeek().environment(model).environment(store).environment(\.me, snapshot.people[0]), look: look
        )
        try hosted.saveShot("shared-calendar-\(value)-\(look.name)")
        return hosted
    }

    @Test(
        "Another device's work is one quiet row a day, its Busy only event says only that, and a quiet phone is named, in each look",
        arguments: ["YES", "stale"], ["light", "dark", "largest", "largest-dark"]
    )
    func fits(value: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await page(value, look)
        #expect(page.elements.count >= 6, "the page was read (\(value), \(look)):\n\(page.listing)")
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        let quiet = page.elements.filter { $0.label.contains("Mia at work") }
        #expect(quiet.count == 2, "one quiet row on each of the two days:\n\(page.listing)")
        #expect(quiet.contains { $0.label.contains("3 meetings") && $0.label.contains("5:30") }, "until when, and how many:\n\(page.listing)")
        #expect(!page.elements.contains { $0.label.contains("Launch review") || $0.label.contains("Standup") }, "the meetings stay folded")
        #expect(page.elements.contains { $0.label.contains("Ava's ballet recital") }, "her own events in full")
        #expect(page.elements.contains { $0.label.contains("Busy") && $0.label.contains("busy only") }, "the Busy only event")
        let stale = page.elements.contains { $0.label.contains("Mia's calendar, updated") }
        #expect(stale == (value == "stale"), "the line only for a phone two days quiet:\n\(page.listing)")
        if value == "stale" {
            #expect(page.elements.contains { $0.label.contains("Mia's calendar, updated Sunday") })
        }
    }
}
#endif
