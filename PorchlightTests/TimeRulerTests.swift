import Foundation
import Testing
@testable import Porchlight

/// The day ruler's labels and shaded bands.
@Suite("Time ruler")
struct TimeRulerLogicTests {
    @Test func clockText() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        func at(_ hour: Int, _ minute: Int) -> String {
            ClockText.spoken(calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day)!, calendar: calendar)
        }
        #expect(at(0, 5) == "12:05 AM")
        #expect(at(8, 40) == "8:40 AM")
        #expect(at(12, 0) == "12:00 PM")
        #expect(at(19, 12) == "7:12 PM")
    }

    @Test func hourLabels() {
        #expect(DayRuler.hourLabel(6 * 60) == "6a")
        #expect(DayRuler.hourLabel(12 * 60) == "12p")
        #expect(DayRuler.hourLabel(21 * 60) == "9p")
        #expect(DayRuler.hourLabel(24 * 60) == "12a")
    }

    @Test func mealBandsFollowTheDiarysSlots() {
        let bands = TimeBand.meals(["Breakfast", "Dinner", "Brunch"])
        #expect(bands.map(\.label) == ["Breakfast", "Dinner"], "A custom slot has no usual time to shade")
        #expect(bands[1].start == 17 * 60)
    }

    @Test func anAllDayWindowShadesNothing() {
        #expect(TimeBand.windows([CareWindow("Any time", start: 0, end: 24 * 60)]).isEmpty)
        let walks = TimeBand.windows([.hours("Morning", 6, 10), .hours("Evening", 17, 20)])
        #expect(walks.map(\.label) == ["Morning", "Evening"])
    }
}
