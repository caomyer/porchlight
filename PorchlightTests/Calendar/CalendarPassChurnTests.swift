import Foundation
import Testing
@testable import Porchlight

/// What an idle device writes (docs/design/calendar-shared.md, "Passing on"): a pass that
/// changes nothing writes nothing within the hour, then only the feed's stamp; a real change
/// or the window rolling at the day's turn writes at once; and no pass leads to another.
/// The clock is handed in and moved by hand.
@MainActor
@Suite("Passing on when nothing changed")
struct CalendarPassChurnTests {
    private final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_795_363_200) }

    private func make() throws -> (CalendarStore, FixedCalendarProvider, AppDatabase, Clock) {
        let db = try AppDatabase.inMemory(installId: "churn")
        var household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "Mia", color: .coral)])
        household.timeZoneIdentifier = "America/Los_Angeles"
        try db.writer.write { [household] db in try household.update(db) }
        try db.saveThisDevice(ThisDevice(name: "Mia's iPhone", role: .personal, model: "iPhone"), in: household.id)
        try db.syncCalendarSources(householdId: household.id, calendars: SharedCalendarFixture.calendars)
        try db.markCalendarChoicesSeen()
        let provider = FixedCalendarProvider(calendars: SharedCalendarFixture.calendars, events: SharedCalendarFixture.events)
        let clock = Clock()
        let store = CalendarStore(database: db, provider: provider, now: { clock.now }, passesOn: false)
        return (store, provider, db, clock)
    }

    /// Rows the database changed since it opened.
    private func changes(_ db: AppDatabase) throws -> Int {
        try db.writer.write { $0.totalChangesCount }
    }

    private func stamp(_ db: AppDatabase) throws -> Date? {
        try db.writer.read { try CalendarFeed.fetchAll($0).first?.passedOnAt }
    }

    private func settle(_ store: CalendarStore) async throws {
        for _ in 0..<50 where store.snapshot.household == nil { try await Task.sleep(for: .milliseconds(100)) }
    }

    @Test("Unchanged passes within the hour write nothing; an hour on, only the stamp; a real change at once")
    func hourly() async throws {
        let (store, provider, db, clock) = try make()
        try await settle(store)
        let first = try #require(store.passOn(.open))
        #expect(first.inserted > 0)
        let start = clock.now
        #expect(try stamp(db) == start)

        var before = try changes(db)
        for minutes in [1.0, 10, 30, 59] {
            clock.now = start.addingTimeInterval(minutes * 60)
            #expect(store.passOn(.open)?.inserted == 0)
        }
        #expect(try changes(db) == before, "four unchanged passes in the hour wrote nothing")
        #expect(try stamp(db) == start)
        #expect(store.lastChecked == start.addingTimeInterval(59 * 60), "but this device knows it looked")
        for _ in 0..<50 where store.shared.feeds.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        let line = CalendarFreshness.detailLines(store.shared, now: clock.now, calendar: store.calendar, checkedHere: store.lastChecked).first?.line ?? ""
        #expect(line.contains("passed on 8:00") && line.contains("checked 8:59") && line.hasSuffix("nothing new"), "Sync details says both: \(line)")

        clock.now = start.addingTimeInterval(61 * 60)
        before = try changes(db)
        _ = store.passOn(.day)
        #expect(try changes(db) == before + 1, "an hour on, the feed's stamp alone")
        #expect(try stamp(db) == clock.now)

        clock.now = start.addingTimeInterval(62 * 60)
        provider.store.events.append(ExternalEvent(
            id: "own-2@1", calendarId: "mia-own", title: "Dentist", start: start.addingTimeInterval(30 * 3600),
            end: start.addingTimeInterval(31 * 3600), isAllDay: false
        ))
        store.reload()
        before = try changes(db)
        #expect(store.passOn(.change)?.inserted == 1)
        #expect(try changes(db) > before + 1, "a new event writes at once, with the stamp")
        #expect(try stamp(db) == clock.now)
    }

    @Test("The window rolling at the day's turn counts as a change and writes")
    func dayTurn() async throws {
        let (store, _, db, clock) = try make()
        try await settle(store)
        _ = store.passOn(.open)
        // 11:50 PM, then 12:05 AM in Los Angeles: ten minutes apart, a new day's window.
        clock.now = Date(timeIntervalSince1970: 1_795_363_200 + 15.83 * 3600)
        _ = store.passOn(.day)
        let lateStamp = try stamp(db)
        clock.now = clock.now.addingTimeInterval(15 * 60)
        let before = try changes(db)
        _ = store.passOn(.day)
        #expect(try changes(db) > before, "the window moved a day")
        #expect(try stamp(db) == clock.now && lateStamp != clock.now)
    }

    @Test("A pass with nothing to change does not lead to another")
    func noLoop() async throws {
        let (store, _, _, _) = try make()
        try await settle(store)
        _ = store.passOn(.open)
        // What the first pass wrote reaches the store and settles; the debounce is 2 seconds.
        try await Task.sleep(for: .seconds(3))
        let settled = store.passes
        _ = store.passOn(.open)
        try await Task.sleep(for: .seconds(3))
        #expect(store.passes == settled + 1, "one pass, and nothing it wrote asked for another")
    }
}
