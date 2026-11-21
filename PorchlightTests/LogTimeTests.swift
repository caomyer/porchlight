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

    /// The card's one-tap choices, with the clock pinned and walked through the day a minute
    /// at a time in two time zones: "1 hr ago" is offered only once an hour ago is still
    /// today, and "Just got back" always, even for a walk that began before midnight. The
    /// wall's UI test used to check this by branching on the real time of day.
    @Test("Earlier choices are offered only while they are still today; just now always is", arguments: ["America/Los_Angeles", "Pacific/Auckland"])
    func suggestionsThroughTheDay(zone: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 7)))
        let choices = LogTime.recentSuggestions(justNow: "Just got back")
        for minute in 0..<(24 * 60) {
            let now = midnight.addingTimeInterval(Double(minute) * 60)
            let day = LogTimeDay(range: midnight...now, calendar: calendar, clock: ClockStyle(uses24Hours: false))
            for lasting in [0, 20] {
                let offered = day.suggestions(choices, selected: .justNow, now: now, lasting: lasting) { _ in }
                var expected = ["Just got back"]
                for ago in [30, 60, 120] where minute >= ago { expected.append(LogTime.agoText(ago)) }
                #expect(offered.map(\.title) == expected, "at minute \(minute), lasting \(lasting)")
                #expect(offered.first?.isSelected == true, "a new log starts on just now")
                #expect(offered.dropFirst().allSatisfy { !$0.isSelected })
            }
        }
        // 5:20 pm: an hour ago reads 4:20 PM, and picking it marks it.
        let evening = midnight.addingTimeInterval(17 * 3600 + 20 * 60)
        let day = LogTimeDay(range: midnight...evening, calendar: calendar, clock: ClockStyle(uses24Hours: false))
        var picked: LogTime?
        let offered = day.suggestions(choices, selected: .minutesAgo(60), now: evening, lasting: 20) { picked = $0 }
        let hourAgo = try #require(offered.first { $0.title == "1 hr ago" })
        #expect(hourAgo.detail == "4:20 PM")
        #expect(hourAgo.isSelected && offered.filter(\.isSelected).count == 1)
        #expect(hourAgo.apply() == nil)
        #expect(picked == .minutesAgo(60))
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
