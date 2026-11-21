import Foundation
import Testing
@testable import Porchlight

/// The phone diary's other weeks (docs/proposals/food-diary-polish.html): which seven days
/// each is, how far back it goes, which week a saved meal shows in, and what the pager and
/// an empty week say. The week ending today is the wall's week; earlier ones step back by
/// seven days, so "Last week" on the phone is the wall's previous week.
@Suite("Phone food, other weeks")
struct PocketFoodWeeksTests {
    private typealias F = CareFixture

    @Test("Each week is seven days in a row, seven days before the one after it")
    func weeks() {
        let today = F.key(21)
        #expect(PocketFood.week(endingOn: today, weeksBack: 0, calendar: F.calendar) == PocketFood.week(endingOn: today, calendar: F.calendar))
        let last = PocketFood.week(endingOn: today, weeksBack: 1, calendar: F.calendar)
        #expect(last.first == F.key(8) && last.last == F.key(14))
        let three = PocketFood.week(endingOn: today, weeksBack: 3, calendar: F.calendar)
        #expect(PocketFood.range(three, calendar: F.calendar) == "Oct 25 to 31")
        #expect(PocketFood.range(PocketFood.week(endingOn: today, weeksBack: 2, calendar: F.calendar), calendar: F.calendar) == "Nov 1 to 7")
    }

    /// Every half hour of a day, in Los Angeles across the end of daylight saving (November 1,
    /// 2026) and in Tokyo, which has none: the weeks are whole days, in a row, ending on the
    /// right day.
    @Test("Weeks hold across the day, a daylight saving change and time zones", arguments: ["America/Los_Angeles", "Asia/Tokyo"])
    func sweep(zone: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5)))
        for halfHour in 0..<48 {
            let now = start.addingTimeInterval(TimeInterval(halfHour) * 1800)
            let today = DayKey(now, calendar: calendar)
            #expect(today.rawValue == "2026-11-05", "\(zone) \(halfHour)")
            for back in 0...3 {
                let days = PocketFood.week(endingOn: today, weeksBack: back, calendar: calendar)
                #expect(days.count == 7)
                #expect(days.last == today.adding(days: -7 * back, calendar: calendar))
                for (day, next) in zip(days, days.dropFirst()) {
                    #expect(day.adding(days: 1, calendar: calendar) == next, "\(zone) \(day) then \(next)")
                }
                #expect(PocketFood.weeksBack(of: days.first!, today: today, calendar: calendar) == back)
                #expect(PocketFood.weeksBack(of: days.last!, today: today, calendar: calendar) == back)
            }
        }
        // The week with the change in it, as the phone names it.
        let first = DayKey(start, calendar: calendar)
        #expect(PocketFood.range(PocketFood.week(endingOn: first, calendar: calendar), calendar: calendar) == "Oct 30 to Nov 5")
    }

    @Test("Back goes as far as the week of the first meal, and no further")
    func limit() {
        let today = F.key(21)
        #expect(PocketFood.weeksBackLimit(firstDay: nil, today: today, calendar: F.calendar) == 0, "no meals: this week only")
        #expect(PocketFood.weeksBackLimit(firstDay: F.key(21), today: today, calendar: F.calendar) == 0)
        #expect(PocketFood.weeksBackLimit(firstDay: F.key(15), today: today, calendar: F.calendar) == 0, "this week's first day")
        #expect(PocketFood.weeksBackLimit(firstDay: F.key(14), today: today, calendar: F.calendar) == 1)
        #expect(PocketFood.weeksBackLimit(firstDay: F.key(8), today: today, calendar: F.calendar) == 1)
        #expect(PocketFood.weeksBackLimit(firstDay: F.key(7), today: today, calendar: F.calendar) == 2)
        #expect(PocketFood.weeksBackLimit(firstDay: F.key(1), today: today, calendar: F.calendar) == 2)
    }

    @Test("A saved meal shows in its own week: one logged now in this week, a past slot's in its week")
    func savedMealsWeek() {
        let today = F.key(21)
        #expect(PocketFood.weeksBack(of: today, today: today, calendar: F.calendar) == 0, "Snap a meal logs now")
        #expect(PocketFood.weeksBack(of: F.key(12), today: today, calendar: F.calendar) == 1, "a slot filled last week stays there")
        #expect(PocketFood.weeksBack(of: F.key(22), today: today, calendar: F.calendar) == 0, "never ahead of this week")
    }

    @Test("The pager names a week from now, and says it whole to VoiceOver")
    func words() {
        #expect(PocketFood.weekName(weeksBack: 0) == "This week")
        #expect(PocketFood.weekName(weeksBack: 1) == "Last week")
        #expect(PocketFood.weekName(weeksBack: 2) == "2 weeks ago")
        #expect(PocketFood.weekName(weeksBack: 12) == "12 weeks ago")
        let last = PocketFood.week(endingOn: F.key(21), weeksBack: 1, calendar: F.calendar)
        #expect(PocketFood.weekSpoken(last, weeksBack: 1, meals: 18, calendar: F.calendar) == "Last week, Nov 8 to 14, 18 meals")
        #expect(PocketFood.weekSpoken(last, weeksBack: 1, meals: 1, calendar: F.calendar) == "Last week, Nov 8 to 14, 1 meal")
        #expect(PocketFood.weekLine(last, meals: 18, calendar: F.calendar) == "Nov 8 to 14 · 18 meals")
        #expect(PocketFood.weekLine(last, meals: 0, calendar: F.calendar) == "Nov 8 to 14 · no meals")
        #expect(PocketFood.weekSpoken(last, weeksBack: 1, meals: 0, calendar: F.calendar) == "Last week, Nov 8 to 14, no meals")
    }

    @Test("An empty past week invites filling a slot in")
    func emptyWeek() {
        let days = PocketFood.week(endingOn: F.key(21), weeksBack: 2, calendar: F.calendar)
        let words = PocketFood.emptyWeek(days, calendar: F.calendar)
        #expect(words.title == "Nothing logged Nov 1 to 7")
        #expect(words.detail == "Tap a slot to add a meal you remember.")
    }
}
