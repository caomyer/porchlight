import Foundation
import Testing
@testable import Porchlight

/// The photo frame's two rules: photos come shuffled without repeats, and the porch view's sky
/// follows the time of day.
struct PhotoFrameTests {
    /// A seeded generator, so a shuffle is the same every run.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    @Test func everyPhotoShowsOnceBeforeAnyRepeats() {
        var deck = ShuffleDeck<Int>()
        var generator = Seeded(state: 7)
        let items = Array(0..<6)
        for _ in 0..<20 {
            let round = (0..<6).compactMap { _ in deck.next(from: items, using: &generator) }
            #expect(Set(round) == Set(items), "Each round deals every photo once")
        }
    }

    @Test func nothingShowsTwiceInARow() {
        var deck = ShuffleDeck<Int>()
        var generator = Seeded(state: 3)
        var previous: Int?
        for _ in 0..<300 {
            let item = deck.next(from: [1, 2, 3], using: &generator)
            #expect(item != previous)
            previous = item
        }
    }

    @Test func photosAddedOrRemovedMidRound() {
        var deck = ShuffleDeck<String>()
        var generator = Seeded(state: 11)
        let first = deck.next(from: ["a", "b", "c"], using: &generator)!
        // Mid-round, "c" is removed and "d" is added.
        let updated = ["a", "b", "d"]
        let restOfRound = Set(["a", "b", "c"]).subtracting([first, "c"])
        let dealt = restOfRound.map { _ in deck.next(from: updated, using: &generator)! }
        #expect(Set(dealt) == restOfRound, "The round finishes without the removed photo, before the new one")
        let nextRound = updated.map { _ in deck.next(from: updated, using: &generator)! }
        #expect(Set(nextRound) == Set(updated), "The added photo joins the next round")
        #expect(deck.next(from: [], using: &generator) == nil, "No photos, nothing to show")
    }

    @Test func aSinglePhotoKeepsShowing() {
        var deck = ShuffleDeck<String>()
        #expect(deck.next(from: ["only"]) == "only")
        #expect(deck.next(from: ["only"]) == "only")
    }

    @Test func theSkyFollowsTheDay() {
        #expect(PorchSky.at(minuteOfDay: 4 * 60 + 59) == .evening)
        #expect(PorchSky.at(minuteOfDay: 5 * 60) == .morning)
        #expect(PorchSky.at(minuteOfDay: 10 * 60 + 59) == .morning)
        #expect(PorchSky.at(minuteOfDay: 11 * 60) == .day)
        #expect(PorchSky.at(minuteOfDay: 16 * 60) == .dusk)
        #expect(PorchSky.at(minuteOfDay: 19 * 60) == .evening)
        #expect(PorchSky.at(minuteOfDay: 23 * 60 + 59) == .evening)
        #expect(PorchSky.at(minuteOfDay: 0) == .evening)
    }

    @Test func theSkyUsesTheHouseholdsClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 13:30 UTC is 5:30 AM in Los Angeles in November.
        let date = ISO8601DateFormatter().date(from: "2026-11-12T13:30:00Z")!
        #expect(PorchSky.at(date, calendar: calendar) == .morning)
    }
}
