#if DEBUG
import Foundation
import GRDB
import Testing
@testable import Porchlight

/// What the sample household holds depends on when it is seeded: it is built backwards
/// from "now" so it always looks lived-in. A UI test that launches it on the real clock
/// therefore finds different things at different hours and on different days, and two
/// failed that way at midnight on Sunday, November 22, 2026 (docs/design/testing.md,
/// "Flaky tests"). These pin what the UI tests rely on at the instant they pin
/// (`UITestClock.midweek` in the UI tests: Wednesday, November 18, 2026 at 10:30 am), and
/// show the two edges that failed, so the reason the UI tests pin is on record and stays
/// true.
@Suite("The sample household at the UI tests' pinned time, at midnight and at the week's first minutes")
struct SampleClockTests {
    private struct Sample {
        let calendar: Calendar
        let now: Date
        let walks: [Date]
        let meals: [JournalEntry]

        /// The week `now` is in, as the wall's week grid shows it.
        var week: DateInterval { calendar.dateInterval(of: .weekOfYear, for: now)! }
        var today: String { DayKey(now, calendar: calendar).rawValue }
        var walksThisWeek: [Date] { walks.filter { week.contains($0) } }
        func meals(named title: String) -> [JournalEntry] { meals.filter { $0.title == title } }
    }

    private func sample(year: Int = 2026, month: Int = 11, day: Int, hour: Int, minute: Int) throws -> Sample {
        let db = try AppDatabase.inMemory(installId: "sample-clock")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        let snapshot = try db.snapshot()
        let seeded = try #require(snapshot.household)
        let calendar = seeded.calendar
        let now = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
        try CompanionSamples.seed(db, household: seeded, people: snapshot.people, now: now)
        try FoodSamples.seed(db, household: seeded, people: snapshot.people, now: now)
        _ = household
        return try db.writer.read { db in
            let walkRoutines = try CareRoutine.filter(Column("kind") == CareKind.walk.rawValue).fetchAll(db).map(\.id)
            let walks = try CareLog.filter(walkRoutines.contains(Column("careRoutineId"))).fetchAll(db).map(\.occurredAt)
            return Sample(calendar: calendar, now: now, walks: walks, meals: try JournalEntry.fetchAll(db))
        }
    }

    /// The app is the unit tests' host, and its clock is pinned there too, so a hosted
    /// screen, the sample it shows and every default `now` agree on the day.
    @Test("The unit tests themselves run on the pinned Wednesday morning")
    func theUnitTestsAreOnThePinnedClock() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let pinned = try #require(formatter.date(from: CompanionClock.unitTestsNow))
        #expect(CompanionClock.now() == pinned)
        #expect(CompanionClock.at(.distantPast) == pinned, "and a screen's own date gives way to it")
        #expect(CompanionClock.unitTestsNow == "2026-11-18T10:30", "the same time as `UITestClock.midweek` in the UI tests")
    }

    @Test("At the UI tests' pinned time the week has walks, today has its breakfast, and the pancakes are six days back")
    func thePinnedTime() throws {
        let sample = try sample(day: 18, hour: 10, minute: 30)
        #expect(sample.calendar.component(.weekday, from: sample.now) == 4, "a Wednesday, so the week before it is not empty")
        #expect(sample.walksThisWeek.count >= 3, "walks this week for the week grid: \(sample.walksThisWeek.count)")
        #expect(sample.walks.contains { sample.calendar.isDate($0, inSameDayAs: sample.now) }, "this morning's walk is done by 10:30")
        #expect(sample.meals(named: "Avocado toast").contains { $0.day == sample.today && $0.slot == "Breakfast" }, "today's breakfast")
        let sixBack = DayKey(sample.now, calendar: sample.calendar).adding(days: -6, calendar: sample.calendar).rawValue
        #expect(sample.meals(named: "Pancakes").contains { $0.day == sixBack && $0.slot == "Breakfast" }, "the pancakes the time field's test opens")
    }

    @Test("Nothing the sample logs for the companion is after the time it was seeded at", arguments: [
        [18, 10, 30], [21, 23, 59], [22, 0, 0], [22, 0, 6], [22, 12, 0],
    ])
    func nothingFromTheFuture(at: [Int]) throws {
        let sample = try sample(day: at[0], hour: at[1], minute: at[2])
        #expect(sample.walks.allSatisfy { $0 <= sample.now })
        #expect(sample.walks.count > 50, "and the history is there: \(sample.walks.count)")
    }

    /// The failure of run 44961571844: the week grid on the real clock, six minutes into a
    /// Sunday. No walk has happened yet today, and every earlier one is in last week.
    @Test("In a Sunday's first minutes the week has no walk yet: why the week grid's test pins its clock")
    func theWeeksFirstMinutes() throws {
        let sample = try sample(day: 22, hour: 0, minute: 6)
        #expect(sample.calendar.component(.weekday, from: sample.now) == sample.calendar.firstWeekday, "the week's first day")
        #expect(sample.walksThisWeek.isEmpty)
        #expect(!sample.walks.isEmpty)
    }

    /// The failure of run 44961571872: the Food page opened at 11:59 pm on the real clock
    /// showed the pancakes of six days before, and at midnight they were seven days back.
    @Test("A minute before midnight the pancakes are six days back, and a minute after they are seven")
    func acrossMidnight() throws {
        let before = try sample(day: 21, hour: 23, minute: 59)
        let pancakes = try #require(before.meals(named: "Pancakes").map(\.day).max())
        let today = DayKey(before.now, calendar: before.calendar)
        #expect(pancakes == today.adding(days: -6, calendar: before.calendar).rawValue)
        let after = try #require(before.calendar.date(byAdding: .minute, value: 2, to: before.now))
        #expect(pancakes == DayKey(after, calendar: before.calendar).adding(days: -7, calendar: before.calendar).rawValue)
    }
}
#endif
