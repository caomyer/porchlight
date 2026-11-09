import Foundation
import Testing
@testable import Porchlight

@Suite("Care logic")
struct CareLogicTests {
    typealias F = CareFixture
    let calendar = CareFixture.calendar

    // MARK: Windows and slots

    @Test("A log fills the window it falls in, else the nearest one")
    func windowIndex() {
        let windows = F.walk.windows
        #expect(CareLogic.windowIndex(forMinute: 7 * 60, in: windows) == 0)
        #expect(CareLogic.windowIndex(forMinute: 18 * 60, in: windows) == 1)
        #expect(CareLogic.windowIndex(forMinute: 5 * 60, in: windows) == 0)
        #expect(CareLogic.windowIndex(forMinute: 13 * 60, in: windows) == 0, "1pm is closer to the morning window")
        #expect(CareLogic.windowIndex(forMinute: 15 * 60, in: windows) == 1, "3pm is closer to the evening window")
        #expect(CareLogic.windowIndex(forMinute: 23 * 60, in: windows) == 1)
        #expect(CareLogic.windowIndex(forMinute: 13 * 60 + 30, in: windows) == 0, "ties go to the earlier window")
    }

    @Test("A second log for a filled window is an extra, not the next slot")
    func assignExtras() {
        let entries = [F.entry(1, 7), F.entry(2, 9, by: [F.mia])]
        let filled = CareLogic.assign(entries, to: F.walk.windows, calendar: calendar)
        #expect(filled[0]?.id == 1)
        #expect(filled[1] == nil)
    }

    @Test("Slot states follow the clock: upcoming, open, due, late, done")
    func slotStates() {
        let day = F.key(7)
        func states(at hour: Int, _ minute: Int = 0, entries: [CareEntry] = []) -> [CareSlot.State] {
            CareLogic.slots(for: F.walk, on: day, byDay: CareLogic.byDay(entries, calendar: calendar), now: F.date(hour, minute), calendar: calendar)
                .map(\.state)
        }
        #expect(states(at: 5) == [.upcoming, .upcoming])
        #expect(states(at: 6, 30) == [.open, .upcoming])
        #expect(states(at: 7, 0) == [.due, .upcoming], "nudged an hour after the window opens")
        #expect(states(at: 11) == [.late, .upcoming])
        #expect(states(at: 18, entries: [F.entry(1, 8, 12)]) == [.done(onTime: true), .due])
        #expect(states(at: 21, entries: [F.entry(1, 11)]) == [.done(onTime: false), .late])
    }

    @Test("Past days without logs are missed; future days are future")
    func pastAndFuture() {
        let now = F.date(12)
        let past = CareLogic.slots(for: F.walk, on: F.key(6), byDay: [:], now: now, calendar: calendar)
        let future = CareLogic.slots(for: F.walk, on: F.key(8), byDay: [:], now: now, calendar: calendar)
        #expect(past.map(\.state) == [.missed, .missed])
        #expect(future.map(\.state) == [.future, .future])
    }

    @Test("Every-N-days routines only have a slot on due days")
    func everyNDays() {
        let entries = [F.entry(1, day: 4, 9, routine: 11)]
        let byDay = CareLogic.byDay(entries, calendar: calendar)
        let now = F.date(day: 7, 12)
        #expect(CareLogic.isDue(F.water, on: F.key(5), byDay: byDay, calendar: calendar) == false)
        #expect(CareLogic.isDue(F.water, on: F.key(6), byDay: byDay, calendar: calendar) == false)
        #expect(CareLogic.isDue(F.water, on: F.key(7), byDay: byDay, calendar: calendar))
        #expect(CareLogic.slots(for: F.water, on: F.key(5), byDay: byDay, now: now, calendar: calendar).isEmpty)
        let today = CareLogic.slots(for: F.water, on: F.key(7), byDay: byDay, now: now, calendar: calendar)
        #expect(today.count == 1)
        #expect(today.first?.state == .open)
        let logged = CareLogic.slots(for: F.water, on: F.key(4), byDay: byDay, now: now, calendar: calendar)
        #expect(logged.first?.state == .done(onTime: true), "all-day windows are always on time")
        #expect(CareLogic.slots(for: F.water, on: F.key(9), byDay: byDay, now: now, calendar: calendar).isEmpty)
    }

    // MARK: Streak

    @Test("Streak counts complete days; an unfinished today doesn't break it")
    func streak() {
        let history = F.fullDays(1...6)
        let morning = F.date(day: 7, 8)
        #expect(CareLogic.streak(for: F.walk, entries: history, now: morning, calendar: calendar) == 6)
        let today = history + [F.entry(1, 7), F.entry(2, 18)]
        #expect(CareLogic.streak(for: F.walk, entries: today, now: F.date(19), calendar: calendar) == 7)
    }

    @Test("A missed slot ends the streak, and no history means no streak")
    func streakBreaks() {
        var history = F.fullDays(1...6)
        history.removeAll { $0.id == 1007 }  // Nov 4, evening
        #expect(CareLogic.streak(for: F.walk, entries: history, now: F.date(8), calendar: calendar) == 2)
        #expect(CareLogic.streak(for: F.walk, entries: [], now: F.date(8), calendar: calendar) == 0)
    }

    @Test("Every-N-days streaks count the days in between as kept")
    func streakEveryNDays() {
        let entries = [1, 4].map { F.entry(Int64($0), day: $0, 9, routine: 11) }
        // Nov 1 and Nov 4 watered; Nov 7 is due and not done yet, so it doesn't count.
        #expect(CareLogic.streak(for: F.water, entries: entries, now: F.date(day: 7, 8), calendar: calendar) == 6)
    }

    // MARK: Weekly stats

    @Test("Weekly stats count walks, on-time slots, duration and business")
    func weekStats() {
        let days = calendar.weekDays(containing: F.date(12)).map { DayKey($0, calendar: calendar) }
        let entries = [
            F.entry(1, day: 1, 7, minutes: 20, pee: true, poo: true),
            F.entry(2, day: 1, 21, minutes: 40, pee: true),  // late evening walk
            F.entry(3, day: 2, 8, minutes: 30, poo: false),
            F.entry(4, day: 7, 8, minutes: 25, pee: true, poo: true),
            F.entry(5, day: 31 - 31, 8, minutes: 99),  // Oct 31: previous week
        ]
        let stats = CareLogic.weekStats(for: F.walk, entries: entries, days: days, now: F.date(day: 7, 12), calendar: calendar)
        #expect(stats.count == 4)
        #expect(stats.averageMinutes == 29)
        #expect(stats.pee == 3)
        #expect(stats.poo == 2)
        #expect(stats.stars == 8)
        // Nov 1-6 = 12 slots, plus today's morning (done). Today's evening is still upcoming.
        #expect(stats.slotsSoFar == 13)
        #expect(stats.slotsOnTime == 3)
    }

    // MARK: Leaderboard

    @Test("Leaderboard counts solo logs per person and joint logs as Together")
    func leaderboard() {
        let entries = [
            F.entry(1, 7, by: [F.mia]), F.entry(2, 8, by: [F.mia]), F.entry(3, 9, by: [F.james]),
            F.entry(4, 10, by: [F.james, F.mia]),
        ]
        let board = CareLogic.leaderboard(entries, people: [F.james, F.mia])
        #expect(board == [
            .init(carer: .person(F.mia), count: 2),
            .init(carer: .person(F.james), count: 1),
            .init(carer: .together, count: 1),
        ])
        let tie = CareLogic.leaderboard([F.entry(1, 7, by: [F.mia]), F.entry(2, 8, by: [F.james])], people: [F.james, F.mia])
        #expect(tie.map(\.carer) == [.person(F.james), .person(F.mia)], "ties keep household order")
        #expect(CareLogic.leaderboard([], people: [F.james]).isEmpty)
    }

    // MARK: Milestones

    @Test("On-time run counts back from the latest finished slot")
    func onTimeRun() {
        var entries = F.fullDays(1...6)
        entries.append(F.entry(1, 8))
        #expect(CareLogic.onTimeRun(for: F.walk, entries: entries, now: F.date(12), calendar: calendar) == 13)
        entries.append(F.entry(2, day: 0, 12))  // Oct 31 midday: a late morning walk ends the run there
        #expect(CareLogic.onTimeRun(for: F.walk, entries: entries, now: F.date(12), calendar: calendar) == 13)
        let late = entries + [F.entry(3, 21)]
        #expect(CareLogic.onTimeRun(for: F.walk, entries: late, now: F.date(22), calendar: calendar) == 0)
    }

    @Test("Next milestone steps up through the list, then by the last step")
    func nextMilestone() {
        #expect(CareLogic.nextMilestone(after: 0, in: CareLogic.runMilestones) == 10)
        #expect(CareLogic.nextMilestone(after: 93, in: CareLogic.runMilestones) == 100)
        #expect(CareLogic.nextMilestone(after: 100, in: CareLogic.runMilestones) == 250)
        #expect(CareLogic.nextMilestone(after: 1000, in: CareLogic.runMilestones) == 2000)
        #expect(CareLogic.nextMilestone(after: 2400, in: CareLogic.runMilestones) == 3000)
    }

    // MARK: Mood

    @Test("Mood peaks right after care and decays with time relative to the cadence")
    func mood() throws {
        let now = F.date(12)
        let interval = CareLogic.interval(for: F.walk)
        #expect(interval == 12 * 3600)
        #expect(CareLogic.mood(lastCare: nil, interval: interval, now: now) == nil)
        let fresh = try #require(CareLogic.mood(lastCare: now, interval: interval, now: now))
        let hourAgo = try #require(CareLogic.mood(lastCare: now.addingTimeInterval(-3600), interval: interval, now: now))
        let halfDay = try #require(CareLogic.mood(lastCare: now.addingTimeInterval(-12 * 3600), interval: interval, now: now))
        let longAgo = try #require(CareLogic.mood(lastCare: now.addingTimeInterval(-48 * 3600), interval: interval, now: now))
        #expect(fresh == 1)
        #expect(fresh > hourAgo && hourAgo > halfDay && halfDay > longAgo)
        #expect(hourAgo > 0.7)
        #expect(longAgo > 0 && longAgo < 0.1)
        // A plant watered every 3 days is still fine after a day.
        let plant = try #require(CareLogic.mood(lastCare: now.addingTimeInterval(-24 * 3600), interval: CareLogic.interval(for: F.water), now: now))
        #expect(plant > 0.5)
    }

    @Test("Mood labels are per species, low to high")
    func moodLabels() {
        #expect(CompanionPresets.mood(for: .dog, level: 0).label == "Staring at door")
        #expect(CompanionPresets.mood(for: .dog, level: 1).label == "Zoomies")
        #expect(CompanionPresets.mood(for: .plant, level: 0.05).label == "Thirsty")
        #expect(CompanionPresets.mood(for: .plant, level: 0.99).label == "Thriving")
        for species in Species.allCases {
            #expect(CompanionPresets.moods(for: species).count == 5)
        }
        #expect(FaceExpression(mood: 0.1) == .sleepy)
        #expect(FaceExpression(mood: 0.8) == .happy)
        #expect(FaceExpression(mood: nil) == .happy)
    }

    // MARK: Expected time

    @Test("Typical time is the median of recent logs in that slot, else a third into the window")
    func typicalMinute() {
        let windows = F.walk.windows
        let history = [F.entry(1, day: 4, 18, 10), F.entry(2, day: 5, 18, 40), F.entry(3, day: 6, 19, 5), F.entry(4, day: 6, 7)]
        #expect(CareLogic.typicalMinute(slot: 1, windows: windows, history: history, calendar: calendar) == 18 * 60 + 45)
        #expect(CareLogic.typicalMinute(slot: 0, windows: windows, history: [], calendar: calendar) == 7 * 60 + 15)
        #expect(CareLogic.typicalMinute(slot: 0, windows: [.anyTime], history: [], calendar: calendar) == nil)
        #expect(CareLogic.typicalMinute(slot: 5, windows: windows, history: history, calendar: calendar) == nil)
    }

    // MARK: Text

    @Test("Window ranges read like the wall")
    func rangeText() {
        #expect(CareTime.range(6 * 60, 10 * 60, twelveHour: true) == "6-10am")
        #expect(CareTime.range(17 * 60, 20 * 60, twelveHour: true) == "5-8pm")
        #expect(CareTime.range(11 * 60, 13 * 60, twelveHour: true) == "11am-1pm")
        #expect(CareTime.range(18 * 60 + 30, 24 * 60, twelveHour: true) == "6:30pm-midnight")
        #expect(CareTime.range(17 * 60, 20 * 60, twelveHour: false) == "17-20")
        #expect(CareTime.hour(18 * 60 + 2, twelveHour: true) == "6:02pm")
        #expect(CareWindow.anyTime.rangeText == "Any time")
        #expect(CareText.shortLabels(F.walk.windows) == ["AM", "PM"])
        #expect(CareText.shortLabels(CompanionPresets.windows(count: 3)) == ["Mor", "Mid", "Eve"])
    }
}
