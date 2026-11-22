#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The phone's sheets for adding and changing events (docs/design/calendar-add-edit.md),
/// hosted in the unit bundle in each look: the home calendar chooser, a new event read from
/// one line, the page of a weekly event this phone may change, and that event being edited.
/// The clock is pinned to the UI tests' Wednesday, so the days read the same as their shots.
/// Asking "this event or future ones" is a system dialog, which only the journey shows.
@Suite("The phone's event sheets")
@MainActor
struct PocketEventSheetsScreenTests {
    /// Wednesday, Nov 18, 2026, 08:00 in Los Angeles: `UITestClock.at(8, 0)`.
    static let now = Date(timeIntervalSince1970: 1_795_017_600)
    static let us = ExternalCalendar(id: "us", title: "Us", account: "Google · us@example.com", colorHex: 0xC9A040, accountKind: "Google", allowsWrites: true)
    static let mine = ExternalCalendar(id: "james", title: "James", account: "iCloud", colorHex: 0x3F6EA8, accountKind: "iCloud", allowsWrites: true)

    private enum Sheet: String { case chooser, new, page, edit }

    private func host(_ sheet: Sheet, _ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "event-sheets")
        var household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        household.timeZoneIdentifier = "America/Los_Angeles"
        try await db.writer.write { [household] db in try household.update(db) }
        try db.saveThisDevice(ThisDevice(name: "James's iPhone", role: .personal, model: "iPhone"), in: household.id)
        let calendar = household.calendar
        // Piano every Thursday at 4, the first tomorrow.
        let thursday = DayKey(rawValue: "2026-11-19").startDate(in: calendar).addingTimeInterval(16 * 3600)
        let piano = ExternalEvent(
            id: "piano@1", calendarId: "us", title: "Piano lesson", start: thursday, end: thursday.addingTimeInterval(3600),
            isAllDay: false, externalItemId: "piano", repeats: .weekly
        )
        try db.syncCalendarSources(householdId: household.id, calendars: [Self.us, Self.mine])
        try db.markCalendarChoicesSeen()
        let store = CalendarStore(
            database: db, provider: FixedCalendarProvider(calendars: [Self.us, Self.mine], events: [piano]), now: { Self.now }, passesOn: false
        )
        if sheet != .chooser { store.chooseHome(Self.us) }
        for _ in 0..<50 where store.events.isEmpty || (sheet != .chooser && store.home.calendar == nil) {
            try await Task.sleep(for: .milliseconds(100))
        }
        let event = try #require(store.events.first { $0.title == "Piano lesson" })
        let screen: AnyView = switch sheet {
        case .chooser: AnyView(PocketHomeCalendarSheet())
        case .new: AnyView(PocketEventEditor(start: .new(Self.us), startingLine: "Mia piano tomorrow 4pm"))
        case .page: AnyView(PocketEventPage(event: event))
        case .edit: AnyView(PocketEventEditor(start: .edit(event, try #require(store.draft(for: event)))))
        }
        let model = AppModel(database: db)
        let snapshot = try db.snapshot()
        let hosted = try await HostedScreen.host(
            screen.environment(model).environment(store).environment(ToastCenter()).environment(\.me, snapshot.people[0]), look: look
        )
        try hosted.saveShot("event-\(sheet.rawValue)-\(look.name)")
        return hosted
    }

    /// The phone's clock, moved on while the app stays open.
    private final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_795_017_600) }

    @Test("A new event starts at the next hour of the store's clock, the new day when the phone has sat open overnight")
    func nextMorning() async throws {
        let db = try AppDatabase.inMemory(installId: "next-morning")
        var household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        household.timeZoneIdentifier = "America/Los_Angeles"
        try await db.writer.write { [household] db in try household.update(db) }
        try db.syncCalendarSources(householdId: household.id, calendars: [Self.us])
        let clock = Clock()
        let store = CalendarStore(database: db, provider: FixedCalendarProvider(calendars: [Self.us], events: []), now: { clock.now }, passesOn: false)
        for _ in 0..<50 where store.snapshot.household == nil { try await Task.sleep(for: .milliseconds(100)) }
        let model = AppModel(database: db)
        let me = try #require(try db.snapshot().people.first)
        func open() async throws -> HostedScreen {
            try await HostedScreen.host(
                PocketEventEditor(start: .new(Self.us)).environment(model).environment(store).environment(ToastCenter()).environment(\.me, me),
                look: .light
            )
        }
        let wednesday = try await open()
        #expect(wednesday.elements.contains { $0.label == "Nov 18, 2026" }, "today, Wednesday:\n\(wednesday.listing)")
        // The next morning, the same app: a sheet opened now starts on Thursday.
        clock.now = Self.now.addingTimeInterval(23.5 * 3600)
        let thursday = try await open()
        #expect(thursday.elements.contains { $0.label == "Nov 19, 2026" }, "the new day:\n\(thursday.listing)")
        #expect(!thursday.elements.contains { $0.label == "Nov 18, 2026" })
    }

    @Test(
        "The chooser, a new event, a weekly event's page and its editor fit across the screen and say what they are, in each look",
        arguments: ["chooser", "new", "page", "edit"], ["light", "dark", "largest", "largest-dark"]
    )
    func fits(sheetName: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let sheet = try #require(Sheet(rawValue: sheetName))
        let page = try await host(sheet, look)
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(sheet), \(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        switch sheet {
        case .chooser:
            #expect(page.elements.contains { $0.label.contains("Choose a home calendar") }, "the question:\n\(page.listing)")
            #expect(page.elements.contains { $0.isButton && $0.label.contains("Us") }, "the household's calendars")
        case .new:
            #expect(page.elements.contains { $0.label.contains("Mia piano") && $0.label.contains("Thursday, Nov 19") }, "Reads as, on the pinned week:\n\(page.listing)")
            #expect(page.elements.contains { $0.label.contains("Saved in Us") }, "where it goes")
        case .page:
            #expect(page.elements.contains { $0.label.contains("Repeats every week") }, "that it repeats:\n\(page.listing)")
            #expect(page.elements.contains { $0.isButton && $0.label == "Edit" }, "Edit, as this phone may change it")
            #expect(page.elements.contains { $0.isButton && $0.label == "Delete" }, "and Delete")
        case .edit:
            #expect(page.elements.contains { $0.label == "TITLE" }, "a title field, not the line (the title itself is the field's value):\n\(page.listing)")
            #expect(page.elements.contains { $0.label.contains("Every week") }, "and that it repeats")
        }
    }
}
#endif
