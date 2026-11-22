#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// Free together on the phone (docs/design/calendar-free-together.md), hosted in each look on
/// the UI tests' Wednesday: Mia's work passed on quietly (late on Monday), a book club of
/// James's, a party for everyone, a Busy only evening, a free Saturday afternoon and a
/// visitor all weekend.
@Suite("The phone's Free together")
@MainActor
struct PocketFreeTogetherScreenTests {
    /// Wednesday, Nov 18, 2026, 08:00 in Los Angeles: `UITestClock.at(8, 0)`.
    static let now = Date(timeIntervalSince1970: 1_795_017_600)

    private func page(_ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "free-together")
        var household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        household.timeZoneIdentifier = "America/Los_Angeles"
        household.firstWeekday = 1
        try await db.writer.write { [household] db in try household.update(db) }
        let calendar = household.calendar
        let snapshot = try db.snapshot()
        let james = try #require(snapshot.people.first { $0.name == "James" })
        func at(_ day: String, _ hour: Double) -> Date { DayKey(rawValue: day).startDate(in: calendar).addingTimeInterval(hour * 3600) }
        let mine = ExternalCalendar(id: "james", title: "James", account: "iCloud", colorHex: 0x3F6EA8, accountKind: "iCloud")
        let family = ExternalCalendar(id: "family", title: "Family", account: "Google", colorHex: 0xC9A040, accountKind: "Google")
        let events = [
            ExternalEvent(id: "club@1", calendarId: "james", title: "📚 Book club", start: at("2026-11-19", 19), end: at("2026-11-19", 21), isAllDay: false),
            ExternalEvent(id: "party@1", calendarId: "family", title: "🎂 Grandma's 80th", start: at("2026-11-20", 18), end: at("2026-11-20", 21), isAllDay: false),
            ExternalEvent(id: "soccer@1", calendarId: "family", title: "⚽️ Soccer game", start: at("2026-11-21", 9), end: at("2026-11-21", 12), isAllDay: false),
            ExternalEvent(id: "rosa@1", calendarId: "family", title: "🧳 Aunt Rosa visiting", start: at("2026-11-28", 0), end: at("2026-11-30", 0), isAllDay: true),
        ]
        try db.syncCalendarSources(householdId: household.id, calendars: [mine, family])
        for source in try db.calendarSnapshot().sources {
            try db.setCalendarSourceOwner(id: source.id, owner: source.externalId == "james" ? .person(james.id) : .everyone)
        }
        try db.markCalendarChoicesSeen()
        try CalendarSamples.seedShared(db, household: try #require(snapshot.household), people: snapshot.people, now: Self.now, value: "YES")
        let store = CalendarStore(
            database: db, provider: FixedCalendarProvider(calendars: [mine, family], events: events), now: { Self.now }, passesOn: false
        )
        for _ in 0..<50 where store.events.count < 6 { try await Task.sleep(for: .milliseconds(100)) }
        let model = AppModel(database: db)
        let hosted = try await HostedScreen.host(
            PocketCalendarScreen(free: true).environment(model).environment(store).environment(ToastCenter()).environment(\.me, james), look: look
        )
        try hosted.saveShot("free-together-\(look.name)")
        // The whole page at the largest sizes is taller than a picture can be drawn
        // (`drawHierarchy` gives a blank one past 8192 pixels): the first rows alone, to look at.
        if look.textSize.isAccessibilityCategory {
            let rows = try await HostedScreen.host(
                ScrollView { PocketFreeTogether(filter: .everyone, days: 5).padding(16) }.background(Theme.background)
                    .environment(model).environment(store).environment(\.me, james), look: look
            )
            try rows.saveShot("free-together-rows-\(look.name)")
        }
        return hosted
    }

    @Test("Tonight, then each evening and weekend day: who is free, who is out and why, in each look", arguments: ["light", "dark", "largest", "largest-dark"])
    func fits(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await page(look)
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        func row(_ day: String) -> String? { page.elements.first { $0.label.hasPrefix(day) }?.label }
        #expect(row("Tonight")?.contains("Everyone free from 5:30") == true, "tonight:\n\(page.listing)")
        #expect(row("Evening, Thursday 19")?.contains("James out: Book club, 7:00 to 9:00") == true, "the book club:\n\(page.listing)")
        #expect(row("Evening, Thursday 19")?.contains("Mia free from 7:30") == true, "and who is free, after her ballet recital")
        #expect(row("Evening, Friday 20")?.contains("Everyone out: Grandma's 80th") == true)
        #expect(row("Weekend, Saturday 21")?.contains("Everyone free after noon") == true)
        #expect(row("Weekend, Saturday 28")?.contains("All day: Aunt Rosa visiting") == true)
        #expect(page.elements.contains { $0.label == "Free together" && $0.isButton }, "the way back and forth")
    }
}
#endif
