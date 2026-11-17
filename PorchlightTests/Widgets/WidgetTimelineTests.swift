import Foundation
import Testing
@testable import Porchlight

/// What a widget shows at each moment, and when its timeline needs an entry, from the
/// summary alone (docs/design/beyond-the-app.md, "Timelines" and "Stale, missing, nobody").
@Suite("Widget timelines")
struct WidgetTimelineTests {
    private let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Saturday, November 7 2026 at the given time in the household's time zone.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// The sample summary, written at 6:05 pm: the evening walk is open, the morning one done.
    private var summary: WidgetSummary { WidgetPreviewData.summary(at: at(18, 5), timeZone: timeZone) }

    // MARK: Moments

    @Test("An open window, nobody logged: the log button for that slot")
    func openSlot() throws {
        let moment = WidgetMoment.at(at(18, 5), summary: summary)
        #expect(moment.availability == .ready)
        let yoyo = try #require(moment.companion("yoyo"))
        guard case let .open(routineId, slot, day, name, _, doneWord, start, end) = yoyo.care else {
            Issue.record("expected the evening walk open, got \(yoyo.care)")
            return
        }
        #expect(routineId == "walk")
        #expect(slot == 1)
        #expect(day == "2026-11-07")
        #expect(name == "evening walk")
        #expect(doneWord == "Walked")
        #expect((start, end) == (17 * 60, 20 * 60))
    }

    @Test("Between windows: the last one done, by whom and when")
    func lastDone() throws {
        let moment = WidgetMoment.at(at(12), summary: summary)
        let yoyo = try #require(moment.companion("yoyo"))
        #expect(yoyo.care == .done(name: "morning walk", by: "Mia", at: at(7, 40)))
        #expect(yoyo.minutesSinceCare == 4 * 60 + 20)
    }

    @Test("Before anything opens: what opens next")
    func nextSlot() throws {
        // Written at 4:50 am, before anyone did anything today.
        var early = WidgetPreviewData.summary(at: at(4, 50), timeZone: timeZone)
        for c in early.companions.indices {
            for r in early.companions[c].routines.indices {
                for s in early.companions[c].routines[r].slots.indices {
                    early.companions[c].routines[r].slots[s].doneBy = nil
                    early.companions[c].routines[r].slots[s].doneAt = nil
                }
            }
        }
        let moment = WidgetMoment.at(at(5), summary: early)
        #expect(moment.companion("yoyo")?.care == .next(name: "morning walk", start: 6 * 60))
        // Yesterday's log is in the summary's last-care time, not a log from later today.
        #expect(WidgetMoment.at(at(5), summary: summary).companion("yoyo")?.minutesSinceCare == nil)
    }

    @Test("A window that ended without a log no longer offers the button")
    func windowEnded() throws {
        let moment = WidgetMoment.at(at(20, 30), summary: summary)
        if case .open = moment.companion("yoyo")?.care { Issue.record("the evening walk closed at 8 pm") }
    }

    @Test("Without a setting the first companion shows, and an unknown one falls back to it")
    func companionChoice() {
        let moment = WidgetMoment.at(at(12), summary: summary)
        #expect(moment.companion(nil)?.id == "yoyo")
        #expect(moment.companion("miso")?.id == "miso")
        #expect(moment.companion("gone")?.id == "yoyo")
    }

    @Test("Chores are today's, with the stars done today")
    func chores() {
        let moment = WidgetMoment.at(at(18, 5), summary: summary)
        #expect(moment.chores.map(\.id) == ["faucet", "recycling"])
        #expect(moment.choresLeft == 1)
        #expect(moment.starsToday == 1)
        let tomorrow = WidgetMoment.at(at(9, day: 8), summary: summary)
        #expect(tomorrow.chores.map(\.id) == ["plants"])
    }

    // MARK: Stale, missing, nobody

    @Test("No summary, a shared screen's, no household, no me: each says what to do")
    func unavailable() {
        #expect(WidgetMoment.at(at(12), summary: nil).availability == .missing)
        #expect(WidgetMoment.at(at(12), summary: WidgetSummary(writtenAt: at(12), isSharedScreen: true)).availability == .sharedScreen)
        #expect(WidgetMoment.at(at(12), summary: WidgetSummary(writtenAt: at(12))).availability == .noHousehold)
        var nobody = summary
        nobody.me = nil
        #expect(WidgetMoment.at(at(12), summary: nobody).availability == .noMe)
        for availability in [WidgetMoment.Availability.missing, .sharedScreen, .noHousehold, .noMe, .beyondSummary] {
            #expect(WidgetNotice.text(availability) != nil)
        }
        #expect(WidgetNotice.text(.noMe) == "Open Porchlight and say who you are.")
    }

    @Test("Past the summary's last day the widget asks to open the app")
    func beyondSummary() {
        #expect(WidgetMoment.at(at(23, 59, day: 8), summary: summary).availability == .ready)
        #expect(WidgetMoment.at(at(0, 1, day: 9), summary: summary).availability == .beyondSummary)
    }

    @Test("A summary more than six hours old still shows, with when it is from")
    func stale() {
        #expect(WidgetMoment.at(at(23, 59), summary: summary).asOf == nil)
        #expect(WidgetMoment.at(at(0, 6, day: 8), summary: summary).asOf == at(18, 5))
    }

    @Test("A summary from an unknown version is not read")
    func unknownVersion() throws {
        var newer = summary
        newer.version = WidgetSummary.currentVersion + 1
        #expect(WidgetSummaryFile.decode(try WidgetSummaryFile.encode(newer)) == nil)
        #expect(WidgetSummaryFile.decode(try WidgetSummaryFile.encode(summary)) == summary)
        #expect(WidgetSummaryFile.decode(Data("not json".utf8)) == nil)
    }

    @Test("The summary stays small: a few kilobytes, never a photo")
    func small() throws {
        #expect(try WidgetSummaryFile.encode(summary).count < 8 * 1024)
    }

    // MARK: Planning

    @Test("Entries at now, at every window's start and end, at midnight and every hour")
    func plansEntries() {
        let now = at(18, 5)
        let dates = WidgetTimeline.dates(for: summary, from: now)
        #expect(dates.first == now)
        #expect(dates == dates.sorted())
        #expect(dates.contains(at(20)), "the evening walk's window ends")
        #expect(dates.contains(at(19)), "dinner ends, and the hour turns")
        #expect(dates.contains(at(0, day: 8)), "midnight")
        #expect(dates.contains(at(6, day: 8)), "tomorrow's morning walk opens")
        #expect(dates.contains(at(0, 5, day: 8).addingTimeInterval(1)), "the summary turns stale")
        #expect(!dates.contains(at(17)), "nothing in the past")
        #expect(dates.count <= WidgetTimeline.maxEntries)
    }

    @Test("Without a summary the widget still refreshes every hour")
    func plansWithoutSummary() {
        let dates = WidgetTimeline.dates(for: nil, from: at(18, 5))
        #expect(dates.count == 25)
        #expect(dates[1] == at(19))
    }

    @Test("Each entry is right on its own: at 8 pm the walk's button is gone")
    func entriesAreSelfContained() throws {
        let dates = WidgetTimeline.dates(for: summary, from: at(18, 5))
        let moments = dates.map { WidgetMoment.at($0, summary: summary) }
        let eight = try #require(moments.first { $0.date == at(20) })
        if case .open = eight.companion("yoyo")?.care { Issue.record("closed at 8 pm") }
        let six = try #require(moments.first { $0.date == at(6, day: 8) })
        guard case let .open(_, slot, day, _, _, _, _, _)? = six.companion("yoyo")?.care else {
            Issue.record("tomorrow's morning walk opens at 6")
            return
        }
        #expect(slot == 0)
        #expect(day == "2026-11-08")
    }

    // MARK: Words

    @Test("Widgets use the app's time words")
    func words() {
        #expect(WidgetWords.window(17 * 60, 20 * 60, twelveHour: true) == "5 to 8pm")
        #expect(WidgetWords.window(8 * 60 + 30, 13 * 60, twelveHour: true) == "8:30am to 1pm")
        #expect(WidgetWords.window(0, 1440, twelveHour: true) == "Any time today")
        #expect(WidgetWords.window(17 * 60, 20 * 60, twelveHour: false) == "17 to 20")
        #expect(WidgetWords.time(0, twelveHour: true) == "12am")
        #expect(WidgetWords.clock(at(17, 40), timeZone: timeZone, twelveHour: true) == "5:40pm")
        #expect(WidgetWords.since(45) == "45m")
        #expect(WidgetWords.since(9 * 60 + 10) == "9h")
        #expect(WidgetWords.since(3 * 24 * 60) == "3d")
    }
}
