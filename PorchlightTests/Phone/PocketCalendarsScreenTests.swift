#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The phone's Calendars page (docs/design/calendar-shared.md, "Whose a calendar is"),
/// hosted in each look: every calendar with whose it is and what the household sees, a
/// calendar titled with an email address among them, the two menus under the calendar's
/// name and wrapping onto a second line where they don't fit.
@Suite("The phone's Calendars page")
@MainActor
struct PocketCalendarsScreenTests {
    static let calendars = [
        ExternalCalendar(id: "address", title: "james.chen.1984@gmail.com", account: "Google · james.chen.1984@gmail.com", colorHex: 0x3F6EA8, accountKind: "Google"),
        ExternalCalendar(id: "work", title: "Work", account: "Exchange · j.chen@company.example", colorHex: 0x7E8CA0, accountKind: "Exchange"),
        ExternalCalendar(id: "family", title: "Family", account: "Google · james.chen.1984@gmail.com", colorHex: 0xC9A040, accountKind: "Google"),
        ExternalCalendar(id: "mia", title: "Mia", account: "iCloud", colorHex: 0xDD7558, accountKind: "iCloud"),
    ]

    private func page(_ look: HostedScreen.Look) async throws -> HostedScreen {
        let db = try AppDatabase.inMemory(installId: "calendars-page")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        let snapshot = try db.snapshot()
        let james = try #require(snapshot.people.first { $0.name == "James" })
        try db.saveThisDevice(ThisDevice(name: "James's iPhone", role: .personal, model: "iPhone", personId: james.id), in: household.id)
        try db.syncCalendarSources(householdId: household.id, calendars: Self.calendars)
        let store = CalendarStore(database: db, provider: FixedCalendarProvider(calendars: Self.calendars, events: []), passesOn: false)
        for _ in 0..<50 where store.mappings.count < Self.calendars.count { try await Task.sleep(for: .milliseconds(100)) }
        let model = AppModel(database: db)
        let hosted = try await HostedScreen.host(
            PocketCalendars().environment(model).environment(store).environment(\.me, james), look: look
        )
        try hosted.saveShot("calendars-page-\(look.name)")
        return hosted
    }

    @Test("Each calendar says whose it is and what the household sees, across the screen, in each look", arguments: ["light", "dark", "largest", "largest-dark"])
    func fits(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let page = try await page(look)
        #expect(page.offSides.isEmpty, "nothing runs off either side (\(look)): \(page.offSides.map { "\($0.label.prefix(30)) \($0.frame.integral)" })")
        let owners = page.elements.filter { $0.isButton && $0.label.contains(" belongs to ") }.map(\.label)
        #expect(owners.sorted() == [
            "Family belongs to Everyone", "Mia belongs to Mia", "Work belongs to James", "james.chen.1984@gmail.com belongs to James",
        ], "whose each is:\n\(page.listing)")
        #expect(page.elements.filter { $0.isButton && $0.label.contains(" is shared as ") }.count == 4, "and each choice")
    }
}
#endif
