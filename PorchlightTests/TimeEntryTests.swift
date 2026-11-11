import Foundation
import Testing
@testable import Porchlight

/// Typing a time: what's understood, and which half of the day it means.
@Suite("Time entry")
struct TimeEntryTests {
    private let twelve = ClockStyle(uses24Hours: false)
    private let twentyFour = ClockStyle(uses24Hours: true)

    @Test("Digits, colons and a or p are understood")
    func parsing() {
        #expect(TypedTime.parse("7") == TypedTime(hour: 7, minute: 0))
        #expect(TypedTime.parse("715") == TypedTime(hour: 7, minute: 15))
        #expect(TypedTime.parse("7:15") == TypedTime(hour: 7, minute: 15))
        #expect(TypedTime.parse("7.15") == TypedTime(hour: 7, minute: 15))
        #expect(TypedTime.parse("1930") == TypedTime(hour: 19, minute: 30))
        #expect(TypedTime.parse("12") == TypedTime(hour: 12, minute: 0))
        #expect(TypedTime.parse("7p") == TypedTime(hour: 7, minute: 0, meridiem: .pm))
        #expect(TypedTime.parse(" 7:15 AM ") == TypedTime(hour: 7, minute: 15, meridiem: .am))
        #expect(TypedTime.parse("0") == TypedTime(hour: 0, minute: 0))
    }

    @Test("Things that aren't times are refused")
    func refusing() {
        for text in ["", "abc", "7:5", "25", "760", "12345", "13p", "0a", "7::15", "٧"] {
            #expect(TypedTime.parse(text) == nil, "\(text)")
        }
    }

    @Test("Without a or p, a 12-hour clock offers both halves; a 24-hour clock means what it says")
    func candidates() throws {
        let seven = try #require(TypedTime.parse("7"))
        #expect(seven.candidates(twelve) == [7 * 60, 19 * 60])
        #expect(seven.candidates(twentyFour) == [7 * 60])
        #expect(try #require(TypedTime.parse("12")).candidates(twelve) == [0, 12 * 60])
        #expect(try #require(TypedTime.parse("12a")).candidates(twelve) == [0])
        #expect(try #require(TypedTime.parse("12p")).candidates(twelve) == [12 * 60])
        #expect(try #require(TypedTime.parse("19")).candidates(twelve) == [19 * 60])
    }

    @Test("A log takes the half of the day nearest the time shown, never later than now")
    func logged() {
        let byTwentyTo8 = 0...(19 * 60 + 40)
        let sevenFifteen = [7 * 60 + 15, 19 * 60 + 15]
        #expect(TimeEntry.pickLogged(sevenFifteen, allowed: byTwentyTo8, near: 19 * 60 + 12) == .success(19 * 60 + 15), "A dinner")
        #expect(TimeEntry.pickLogged(sevenFifteen, allowed: byTwentyTo8, near: 8 * 60 + 40) == .success(7 * 60 + 15), "A breakfast")
        #expect(TimeEntry.pickLogged([9 * 60, 21 * 60], allowed: byTwentyTo8, near: 19 * 60 + 40) == .success(9 * 60), "9 PM hasn't happened yet")
        #expect(TimeEntry.pickLogged([21 * 60], allowed: byTwentyTo8, near: 19 * 60) == .failure(.init(minute: 21 * 60, isLater: true)))
        let wholeDay = 0...(24 * 60 - 1)
        #expect(TimeEntry.pickLogged([8 * 60, 20 * 60], allowed: wholeDay, near: 8 * 60 + 40) == .success(8 * 60), "Yesterday's breakfast stays in the morning")
    }

    @Test("An end is the first time after its start, wrapping past midnight")
    func ends() {
        #expect(TimeEntry.pickEnd([1 * 60, 13 * 60], after: 20 * 60) == 1 * 60)
        #expect(TimeEntry.pickEnd([9 * 60, 21 * 60], after: 20 * 60) == 21 * 60)
        #expect(TimeEntry.pickEnd([6 * 60 + 30, 18 * 60 + 30], after: 21 * 60 + 30) == 6 * 60 + 30)
    }

    @Test("A start stays near where it was")
    func starts() {
        #expect(TimeEntry.pickNear([10 * 60, 22 * 60], to: 21 * 60 + 30) == 22 * 60)
        #expect(TimeEntry.pickNear([11 * 60, 23 * 60], to: 30) == 23 * 60, "Across midnight counts as near")
    }

    @Test("Times show in the iPad's clock style")
    func showing() {
        #expect(twelve.text(19 * 60 + 12) == "7:12 PM")
        #expect(twelve.text(0) == "12:00 AM")
        #expect(twelve.text(24 * 60) == "12:00 AM")
        #expect(twentyFour.text(19 * 60 + 12) == "19:12")
        #expect(twentyFour.text(5) == "00:05")
        #expect(ClockStyle(locale: Locale(identifier: "en_US")).uses24Hours == false)
        #expect(ClockStyle(locale: Locale(identifier: "en_GB")).uses24Hours == true)
    }

    @Test("A meal suggests now, a little earlier, and its usual time")
    func mealSuggestions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = DayKey(rawValue: "2026-11-10")
        let titles = MealSlot.timeSuggestions(slot: "Dinner", day: day, calendar: calendar).map(\.title)
        #expect(titles == ["Now", "30 min ago", "1 hr ago", "Usual dinner"])
        #expect(MealSlot.timeSuggestions(slot: "Brunch", day: day, calendar: calendar).count == 3, "A custom slot has no usual time")
    }
}
