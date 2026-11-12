import Foundation
import Testing
@testable import Porchlight

/// Typing into a time's hour and minutes, and showing times on the iPad's clock.
@Suite("Time entry")
struct TimeEntryTests {
    private let twelve = ClockStyle(uses24Hours: false)
    private let twentyFour = ClockStyle(uses24Hours: true)

    /// Types `digits` into `minute` from a fresh card (the hour selected).
    private func typing(_ digits: String, into minute: Int, _ clock: ClockStyle, from part: TimeTyping.Part = .hour) -> (minute: Int, typing: TimeTyping) {
        var typing = TimeTyping()
        typing.select(part)
        var minute = minute
        for digit in digits { minute = typing.type(Int(String(digit))!, into: minute, clock: clock) }
        return (minute, typing)
    }

    private let twentyTo8PM = 19 * 60 + 40

    @Test("Every digit counts at once: 2 to 1 is one tap")
    func digitsCountAtOnce() {
        let twoPM = 14 * 60 + 40
        let one = typing("1", into: twoPM, twelve)
        #expect(one.minute == 13 * 60 + 40, "1 makes it 1:40 PM straight away")
        #expect(one.typing.part == .hour && one.typing.open == 1, "and stays open for 10, 11 or 12")
        #expect(typing("12", into: twoPM, twelve).minute == 12 * 60 + 40)
        #expect(typing("10", into: 9 * 60, twelve).minute == 10 * 60, "AM stays AM")
    }

    @Test("A digit that can't follow goes on to the minutes")
    func spillsIntoMinutes() {
        #expect(typing("715", into: twentyTo8PM, twelve).minute == 19 * 60 + 15)
        #expect(typing("150", into: twentyTo8PM, twelve).minute == 13 * 60 + 50)
        #expect(typing("115", into: twentyTo8PM, twelve).minute == 23 * 60 + 5, "1 1 is 11, as on the web's time input")
        #expect(typing("1030", into: twentyTo8PM, twelve).minute == 22 * 60 + 30)
        #expect(typing("09", into: twentyTo8PM, twelve).minute == 21 * 60 + 40, "A leading 0 waits for the hour")
        let seven = typing("7", into: twentyTo8PM, twelve)
        #expect(seven.typing.part == .minute && seven.typing.open == nil, "7 can only be 7, so the minutes are next")
    }

    @Test("Minutes take one or two digits")
    func minutes() {
        let four = typing("4", into: twentyTo8PM, twelve, from: .minute)
        #expect(four.minute == 19 * 60 + 4)
        #expect(four.typing.open == 4)
        #expect(typing("45", into: twentyTo8PM, twelve, from: .minute).minute == 19 * 60 + 45)
        #expect(typing("7", into: twentyTo8PM, twelve, from: .minute).minute == 19 * 60 + 7)
        #expect(typing("455", into: twentyTo8PM, twelve, from: .minute).minute == 19 * 60 + 5, "A third digit starts over")
    }

    @Test("A 24-hour clock opens on 0, 1 and 2")
    func twentyFourHours() {
        #expect(typing("1830", into: twentyTo8PM, twentyFour).minute == 18 * 60 + 30)
        #expect(typing("25", into: twentyTo8PM, twentyFour).minute == 2 * 60 + 5)
        #expect(typing("0", into: twentyTo8PM, twentyFour).minute == 40, "0 is midnight's hour")
        #expect(typing("7", into: twentyTo8PM, twentyFour).minute == 7 * 60 + 40)
    }

    @Test("Delete ends an open digit, then steps back to the hour")
    func deleting() {
        var typing = typing("1", into: twentyTo8PM, twelve).typing
        typing.delete()
        #expect(typing.open == nil && typing.part == .hour)
        typing.select(.minute)
        typing.delete()
        #expect(typing.part == .hour)
    }

    @Test("AM | PM, arrows and the hint")
    func helpers() {
        #expect(TimeTyping.flipping(19 * 60, toPM: false) == 7 * 60)
        #expect(TimeTyping.flipping(19 * 60, toPM: true) == 19 * 60)
        var typing = TimeTyping()
        #expect(typing.nudging(23 * 60 + 30, by: 1) == 30, "An hour up wraps past midnight")
        typing.select(.minute)
        #expect(typing.nudging(19 * 60 + 59, by: 1) == 19 * 60, "Minutes wrap within the hour")
        #expect(typing.hint(twelve) == "Type to replace the minutes")
        #expect(self.typing("1", into: 0, twelve).typing.hint(twelve) == "Another 0, 1 or 2 makes it 10, 11 or 12")
        #expect(twelve.fields(19 * 60 + 5).hour == "7" && twelve.fields(19 * 60 + 5).minute == "05")
        #expect(twentyFour.fields(7 * 60 + 5).hour == "07")
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
