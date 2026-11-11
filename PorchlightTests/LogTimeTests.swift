import Foundation
import Testing
@testable import Porchlight

@Suite("Logged times")
struct LogTimeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Relative choices resolve against now; just now means it just ended")
    func logTime() {
        #expect(LogTime.justNow.start(now: now) == now)
        #expect(LogTime.justNow.start(now: now, lasting: 20) == now.addingTimeInterval(-20 * 60))
        #expect(LogTime.minutesAgo(60).start(now: now, lasting: 20) == now.addingTimeInterval(-3600))
        let exact = now.addingTimeInterval(-5000)
        #expect(LogTime.at(exact).start(now: now, lasting: 20) == exact)
        #expect(LogTime.agoText(30) == "30 min ago")
        #expect(LogTime.agoText(120) == "2 hr ago")
    }

    @Test("A meal edit keeps a picked time, and moves to the new slot's usual time otherwise")
    func mealEditTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let day = DayKey(rawValue: "2026-11-07")
        let dinner = try #require(calendar.date(byAdding: .minute, value: 19 * 60, to: day.startDate(in: calendar)))
        let entry = JournalEntry(
            journalId: 1, day: day.rawValue, slot: "Dinner", source: .home, title: "Pho",
            eatenAt: dinner, createdAt: dinner
        )

        var edit = MealEdit(entry: entry, eaterIds: [1])
        #expect(edit.draft(for: entry, calendar: calendar).eatenAt == dinner)

        edit.slot = "Lunch"
        #expect(edit.draft(for: entry, calendar: calendar).eatenAt == MealSlot.usualTime(of: "Lunch", on: day, calendar: calendar))

        let picked = dinner.addingTimeInterval(-90 * 60)
        edit.time = .at(picked)
        #expect(edit.draft(for: entry, calendar: calendar).eatenAt == picked)

        edit.time = .at(dinner.addingTimeInterval(-30 * 3600))
        #expect(edit.draft(for: entry, calendar: calendar).eatenAt == day.startDate(in: calendar), "times stay on the meal's day")
    }
}
