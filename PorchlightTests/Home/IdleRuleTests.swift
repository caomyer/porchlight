import Foundation
import Testing
@testable import Porchlight

/// When the wall goes to Ambient, with every time handed in: a touch starts the wait again,
/// Ambient comes once the wait is over, and never while Settings is open, Ambient is already
/// showing, or the wall is set never to. The UI test that used to check this by touching
/// the wall every few seconds of real time failed when a hosted Mac stalled for 50 seconds
/// between two touches (run 44905599973); nothing here waits.
@Suite("When the wall goes idle")
struct IdleRuleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func after(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test("Ambient comes once the minutes are up since the last touch, and not a second before", arguments: [1, 5, 10, 30])
    func afterTheMinutes(minutes: Int) {
        let rule = IdleRule(minutes: minutes)
        let wait = Double(minutes) * 60
        #expect(rule.timeout == wait)
        #expect(!rule.isIdle(lastTouch: start, now: after(wait - 1), showingAmbient: false, inSettings: false))
        #expect(rule.isIdle(lastTouch: start, now: after(wait), showingAmbient: false, inSettings: false))
        #expect(rule.isIdle(lastTouch: start, now: after(wait * 3), showingAmbient: false, inSettings: false))
    }

    @Test("Touches keep the wall awake however long they go on, and Ambient comes a wait after the last one")
    func touchesKeepItAwake() {
        let rule = IdleRule(minutes: 1)
        var lastTouch = start
        // A touch every twenty seconds for an hour, asked four times a minute, as the wall asks.
        for second in stride(from: 0.0, through: 3600, by: rule.checkEvery) {
            if second.truncatingRemainder(dividingBy: 20) == 0 { lastTouch = after(second) }
            #expect(!rule.isIdle(lastTouch: lastTouch, now: after(second), showingAmbient: false, inSettings: false), "awake at \(second)s")
        }
        #expect(!rule.isIdle(lastTouch: lastTouch, now: lastTouch.addingTimeInterval(59), showingAmbient: false, inSettings: false))
        #expect(rule.isIdle(lastTouch: lastTouch, now: lastTouch.addingTimeInterval(60), showingAmbient: false, inSettings: false))
    }

    @Test("Never while Settings is open or Ambient is already showing, and never when set to never")
    func neverThen() {
        let rule = IdleRule(minutes: 1)
        let late = after(3600)
        #expect(!rule.isIdle(lastTouch: start, now: late, showingAmbient: false, inSettings: true))
        #expect(!rule.isIdle(lastTouch: start, now: late, showingAmbient: true, inSettings: false))
        let never = IdleRule(minutes: 0)
        #expect(never.timeout == nil)
        #expect(!never.isIdle(lastTouch: start, now: late, showingAmbient: false, inSettings: false))
    }

    @Test("A shorter minute, as the UI test and screenshots use, shortens the wait and the checks alike")
    func shorterMinutes() {
        let rule = IdleRule(minutes: 1, secondsPerMinute: 3)
        #expect(rule.timeout == 3 && rule.checkEvery == 0.75)
        #expect(!rule.isIdle(lastTouch: start, now: after(2.9), showingAmbient: false, inSettings: false))
        #expect(rule.isIdle(lastTouch: start, now: after(3), showingAmbient: false, inSettings: false))
        #expect(IdleRule(minutes: 10).checkEvery == 15, "four checks a minute on the wall")
    }
}
