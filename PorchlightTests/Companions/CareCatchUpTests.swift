import Foundation
import Testing
@testable import Porchlight

/// Catching up on care that was never logged earlier this week.
@Suite("Care catch-up")
struct CareCatchUpTests {
    typealias F = CareFixture
    /// The fixture's calendar with a real locale (as the household's has), so weekdays read in full.
    let calendar: Calendar = {
        var calendar = CareFixture.calendar
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()
    /// Saturday, November 7 at noon.
    let now = CareFixture.date(12)

    private let feed = CareRoutine(
        id: 12, companionId: 1, kind: .feed, title: "Feed", emoji: "🥣", everyDays: 1,
        windows: [.hours("Breakfast", 6, 9), .hours("Dinner", 17, 19)],
        trackedFields: [], stars: 1, nudgeAfterMinutes: nil, sortOrder: 1
    )

    @Test("A slot never logged earlier this week is missed, at its usual time")
    func missedEarlierThisWeek() {
        let entries = F.fullDays(1...6).filter { !($0.time == F.date(day: 6, 18)) }
        let missed = CareCatchUp.missed(F.walk, entries: entries, on: F.key(6), now: now, calendar: calendar)
        #expect(missed.map(\.slot.index) == [1])
        #expect(missed.first?.usual == F.date(day: 6, 18), "The evening walk usually happens at 6pm")
        #expect(CareCatchUp.missed(F.walk, entries: entries, on: F.key(5), now: now, calendar: calendar).isEmpty)
    }

    @Test("Today is still expected, not missed, and last week is past catching up")
    func onlyThisWeek() {
        let entries = F.fullDays(1...6)
        #expect(CareCatchUp.missed(F.walk, entries: entries, on: F.key(7), now: now, calendar: calendar).isEmpty)
        #expect(CareCatchUp.missed(F.walk, entries: [], on: F.key(1), now: now, calendar: calendar).count == 2, "6 days back still counts")
        let lastWeek = DayKey(F.date(day: 0, 12), calendar: calendar)
        #expect(CareCatchUp.missed(F.walk, entries: [], on: lastWeek, now: now, calendar: calendar).isEmpty)
    }

    @Test("The week's missed care, newest first, across routines")
    func acrossRoutines() {
        let walks = F.fullDays(1...6)
        let missed = CareCatchUp.missed([F.walk, feed], entries: { $0.id == F.walk.id ? walks : [] }, now: now, calendar: calendar)
        #expect(missed.count == 12, "Every breakfast and dinner this week")
        #expect(missed.first?.day == F.key(6) && missed.first?.slot.window.label == "Dinner")
        #expect(missed.last?.day == F.key(1) && missed.last?.slot.window.label == "Breakfast")
    }

    @Test("The log sheet says which day and slot it is for")
    func subtitles() {
        let today = F.key(7)
        #expect(CareCatchUp.subtitle(feed.windows[1], of: feed, on: F.key(6), today: today, calendar: calendar) == "For yesterday's dinner")
        #expect(CareCatchUp.subtitle(F.walk.windows[0], of: F.walk, on: F.key(5), today: today, calendar: calendar) == "For Thursday's morning walk")
        #expect(CareCatchUp.subtitle(F.water.windows[0], of: F.water, on: F.key(4), today: today, calendar: calendar) == "For Wednesday's water")
    }
}
