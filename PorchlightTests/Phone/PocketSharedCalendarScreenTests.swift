#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The phone's Calendar tab and Today's card with what another device passed on
/// (docs/design/calendar-shared.md, "Showing"), hosted in the unit bundle: Mia's work as one
/// quiet row a day, her own events, her Busy only one, and, when her phone has been quiet two
/// days, the line that says so. The clock is pinned, so the days and times are always the same.
@Suite("The phone's household calendar: the quiet row and the stale line")
@MainActor
struct PocketSharedCalendarScreenTests {
    /// Tuesday, Nov 24, 2026, 08:00 in Los Angeles.
    static let now = Date(timeIntervalSince1970: 1_795_536_000)

    private func page(_ value: String, _ look: HostedScreen.Look, card: Bool = false) async throws -> HostedScreen {
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
        let screen: AnyView = card
            ? AnyView(ScrollView { PocketAgendaCard(open: { _ in }).padding(.horizontal, 16) }.background(Theme.background))
            : AnyView(PocketCalendarScreen())
        let hosted = try await HostedScreen.host(
            screen.environment(model).environment(store).environment(\.me, snapshot.people[0]), look: look
        )
        try hosted.saveShot("shared-calendar-\(card ? "card-" : "")\(value)-\(look.name)")
        return hosted
    }

    /// Tuesday, December 1: a week across November and December, a title as long as they
    /// come, and a day with eight things, in this phone's own calendar.
    private func busyWeek(_ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "busy-week")
        var household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        household.timeZoneIdentifier = "America/Los_Angeles"
        household.firstWeekday = 1
        try await db.writer.write { [household] db in try household.update(db) }
        let calendar = household.calendar
        let day = DayKey(rawValue: "2026-12-01")
        let start = day.startDate(in: calendar)
        let home = ExternalCalendar(id: "home", title: "Home", account: "iCloud", colorHex: 0x336699)
        var events: [ExternalEvent] = []
        for index in 0..<7 {
            let from: Double = Double(8 + index * 2) * 3600
            events.append(ExternalEvent(
                id: "e\(index)@1", calendarId: "home", title: "Thing \(index + 1)", location: "Room \(index)",
                start: start.addingTimeInterval(from), end: start.addingTimeInterval(from + 3600), isAllDay: false
            ))
        }
        events.append(ExternalEvent(
            id: "long@1", calendarId: "home", title: "Parent-teacher conferences for the whole of the fourth grade, bring the reading log",
            location: "Lincoln Elementary School, the library on the second floor", start: start.addingTimeInterval(7 * 3600), end: start.addingTimeInterval(7.5 * 3600), isAllDay: false
        ))
        try db.syncCalendarSources(householdId: household.id, calendars: [home])
        let store = CalendarStore(
            database: db, provider: FixedCalendarProvider(calendars: [home], events: events), now: { Self.now }, passesOn: false
        )
        let model = AppModel(database: db)
        let snapshot = try db.snapshot()
        let hosted = try await HostedScreen.host(
            PocketCalendarScreen(start: day).environment(model).environment(store).environment(\.me, snapshot.people[0]), look: look
        )
        try hosted.saveShot("calendar-busy-week-\(look.name)")
        return hosted
    }

    @Test(
        "A week across two months, a long title and a day of eight things fit, the dates in seven even columns, in each look",
        arguments: ["light", "dark", "largest", "largest-dark"]
    )
    func busyWeek(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await busyWeek(look)
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        #expect(page.elements.contains { $0.label.contains("Nov - Dec 2026") }, "both months:\n\(page.listing)")
        let strip = page.elements.filter { $0.isButton && ($0.label.contains("November") || $0.label.contains("December")) && $0.label.contains(",") && $0.frame.height < 200 }
        #expect(strip.count >= 7, "seven days in the strip:\n\(page.listing)")
        // Even to within a point (half points round either way) and level.
        let widths = strip.prefix(7).map(\.frame.width)
        let tops = strip.prefix(7).map(\.frame.minY)
        #expect(widths.max()! - widths.min()! <= 1 && tops.max()! - tops.min()! <= 1, "even and level: \(strip.prefix(7).map(\.frame))")
        #expect(page.elements.contains { $0.label.contains("8 things") }, "the day's count")
        #expect(page.elements.contains { $0.label.contains("Parent-teacher conferences") && $0.label.contains("reading log") }, "the long title whole")
    }

    @Test(
        "Today's \"At home today\" card shows another device's quiet row, and a row to add this phone's calendars, in each look",
        arguments: ["light", "dark", "largest", "largest-dark"]
    )
    func card(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await page("stale", look, card: true)
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        #expect(page.elements.contains { $0.label.contains("Mia at work") && $0.label.contains("3 meetings") }, "the quiet row:\n\(page.listing)")
        #expect(page.elements.contains { $0.label.contains("Mia's calendar, updated Sunday") }, "the stale line")
        #expect(page.elements.contains { $0.isButton && $0.label.contains("Add this") }, "a way to add this phone's own")
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
        #expect(page.elements.contains { $0.label.contains("Busy") && $0.label.contains("Busy only") }, "the Busy only event")
        let stale = page.elements.contains { $0.label.contains("Mia's calendar, updated") }
        #expect(stale == (value == "stale"), "the line only for a phone two days quiet:\n\(page.listing)")
        if value == "stale" {
            #expect(page.elements.contains { $0.label.contains("Mia's calendar, updated Sunday") })
        }
    }
}
#endif
