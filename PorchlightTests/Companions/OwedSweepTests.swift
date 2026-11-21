import Foundation
import Testing
@testable import Porchlight

/// The owed rule across a whole first day, on a pinned clock: every half hour of arrival
/// against every half hour of "now", with nothing logged, the morning walk logged, and both.
/// The streak, the week's numbers and the on-time run must agree with the rule written in
/// docs/design/phone-shell.md whatever the hour, so a time-of-day bug can't hide by hour.
@Suite("Owed slots, swept across the day")
struct OwedSweepTests {
    typealias F = CareFixture
    let calendar = CareFixture.calendar

    @Test("Arrival and now, every half hour: the streak, numbers and run follow one rule")
    func sweep() {
        var walk = F.walk
        walk.anchorDay = F.key(7).rawValue    // the routine starts the day the dog arrives
        let day = F.key(7)
        let windows = walk.effectiveWindows
        let morning = F.entry(1, day: 7, 8, by: [F.james], minutes: 20)
        let evening = F.entry(2, day: 7, 18, by: [F.mia], minutes: 30)
        for arrivalMinute in stride(from: 0, to: 24 * 60, by: 30) {
            for nowMinute in stride(from: 0, to: 24 * 60, by: 30) {
                let arrival = CareLogic.date(day, minute: arrivalMinute, calendar: calendar)
                let now = CareLogic.date(day, minute: nowMinute, calendar: calendar)
                for logged in [[CareEntry](), [morning], [morning, evening]] {
                    let entries = logged.filter { $0.time <= now }
                    let label = "arrived at minute \(arrivalMinute), now minute \(nowMinute), \(entries.count) logged"

                    // A slot is owed when its window closes after the arrival, and the
                    // arrival is never later than now.
                    let effective = min(arrivalMinute, nowMinute)
                    let owed = windows.map { $0.end > effective }
                    let byDay = CareLogic.byDay(entries, calendar: calendar)
                    let slots = CareLogic.slots(for: walk, on: day, byDay: byDay, now: now, calendar: calendar)
                    for slot in slots {
                        #expect(CareLogic.isOwed(slot, of: walk, on: day, since: arrival, now: now, calendar: calendar) == owed[slot.index], "\(label)")
                    }

                    // The day counts when something was done and nothing owed is undone;
                    // a day that owed nothing and did nothing neither counts nor breaks.
                    let done = slots.filter(\.isDone)
                    let owedUndone = slots.contains { !$0.isDone && owed[$0.index] }
                    let expected = !done.isEmpty && !owedUndone ? 1 : 0
                    #expect(CareLogic.streak(for: walk, entries: entries, now: now, calendar: calendar, since: arrival) == expected, "\(label)")
                    if done.isEmpty && !owed.contains(true) {
                        #expect(CareLogic.standing(walk, on: day, byDay: byDay, now: now, calendar: calendar, since: arrival) == .neutral, "\(label)")
                    }

                    // The numbers count what was done, and what was owed and went by.
                    let stats = CareLogic.weekStats(for: walk, entries: entries, days: [day], now: now, calendar: calendar, since: arrival)
                    let wentBy = slots.filter { !$0.isDone && ($0.state == .late || $0.state == .missed) && owed[$0.index] }.count
                    #expect(stats.slotsSoFar == done.count + wentBy, "\(label)")
                    #expect(stats.slotsOnTime <= stats.slotsSoFar, "\(label)")
                    #expect(CareLogic.onTimeRun(for: walk, entries: entries, now: now, calendar: calendar, since: arrival) <= done.count, "\(label)")

                    // An arrival stamped after now reads as an arrival now.
                    if arrivalMinute > nowMinute {
                        #expect(CareLogic.streak(for: walk, entries: entries, now: now, calendar: calendar, since: arrival)
                            == CareLogic.streak(for: walk, entries: entries, now: now, calendar: calendar, since: now), "\(label)")
                        #expect(stats == CareLogic.weekStats(for: walk, entries: entries, days: [day], now: now, calendar: calendar, since: now), "\(label)")
                    }
                }
            }
        }
    }

    @Test("A day that owed nothing is passed over, neither counting nor breaking the streak")
    func neutralDayInAStreak() {
        // The dog arrives at 9 pm on the 5th, after both walks' windows closed, and has
        // full days on the 6th and 7th.
        var walk = F.walk
        walk.anchorDay = F.key(5).rawValue
        let arrival = F.date(day: 5, 21)
        let entries = F.fullDays(6...7)
        let now = F.date(day: 7, 21)
        let byDay = CareLogic.byDay(entries, calendar: calendar)
        #expect(CareLogic.standing(walk, on: F.key(5), byDay: byDay, now: now, calendar: calendar, since: arrival) == .neutral)
        #expect(CareLogic.streak(for: walk, entries: entries, now: now, calendar: calendar, since: arrival) == 2, "the 6th and 7th; the 5th owed nothing")
        // A walk logged anyway on the arrival evening counts as done, and the day with it.
        let early = entries + [F.entry(9, day: 5, 21, 30, by: [F.james])]
        #expect(CareLogic.streak(for: walk, entries: early, now: now, calendar: calendar, since: arrival) == 3)
    }

    @Test("The report on the day a companion arrives doesn't depend on the hour it is read")
    func reportOnArrivalDay() throws {
        // The failing persistence test, pinned: the dog stamped as arriving at 9:30 pm,
        // read at 6:30 pm with the morning walk done: the evening is still owed.
        var walk = F.walk
        walk.anchorDay = F.key(7).rawValue
        let entries = [F.entry(1, day: 7, 8, by: [F.mia], minutes: 25)]
        let now = F.date(day: 7, 18, 30)
        #expect(CareLogic.streak(for: walk, entries: entries, now: now, calendar: calendar, since: F.date(day: 7, 21, 30)) == 0)
        #expect(CareLogic.streak(for: walk, entries: entries, now: now, calendar: calendar, since: F.date(day: 7, 5)) == 0)
    }
}
