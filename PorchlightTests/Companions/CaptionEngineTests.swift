import Foundation
import Testing
@testable import Porchlight

@Suite("Caption engine")
struct CaptionEngineTests {
    typealias F = CareFixture
    let names: [Int64: String] = [CareFixture.james: "James", CareFixture.mia: "Mia", CareFixture.ava: "Ava"]

    private func week(_ count: Int = 14) -> [CareEntry] {
        (0..<count).map { index in
            F.entry(Int64(index + 1), day: 1 + index / 2, index % 2 == 0 ? 7 : 18, by: [index % 3 == 0 ? F.mia : F.james], minutes: 15 + index * 3)
        }
    }

    @Test("Captions are deterministic and never repeat a template back to back", arguments: [CompanionTone.wholesome, .cheeky, .dramatic])
    func noRepeats(tone: CompanionTone) {
        let entries = week()
        let first = CaptionEngine.captions(for: entries, tone: tone, name: "Yo-Yo", routine: F.walk, names: names, calendar: F.calendar)
        let second = CaptionEngine.captions(for: entries.shuffled(), tone: tone, name: "Yo-Yo", routine: F.walk, names: names, calendar: F.calendar)
        #expect(first == second)
        #expect(first.count == entries.count)
        let texts = entries.map { first[$0.id]! }
        for (a, b) in zip(texts, texts.dropFirst()) {
            #expect(a != b)
        }
        #expect(Set(texts).count > 3, "a week of captions should have variety")
    }

    @Test("Same-vibe logs in a row still get different captions")
    func vibeStreak() {
        let entries = (0..<6).map { F.entry(Int64($0 + 1), day: 1 + $0, 7, vibe: .squirrel) }
        let captions = CaptionEngine.captions(for: entries, tone: .cheeky, name: "Yo-Yo", routine: F.walk, names: names, calendar: F.calendar)
        let texts = entries.map { captions[$0.id]! }
        for (a, b) in zip(texts, texts.dropFirst()) {
            #expect(a != b)
        }
    }

    @Test("Off means no captions")
    func off() {
        #expect(CaptionEngine.captions(for: week(), tone: .off, name: "Yo-Yo", routine: F.walk, names: names, calendar: F.calendar).isEmpty)
    }

    @Test("Captions use names and counts, and only mention walking for walks")
    func content() {
        let context = CaptionEngine.Context(
            name: "Yo-Yo", kind: .walk, noun: "walk", who: "James", together: false, nthThisWeek: 6, minutes: 18, vibe: .smooth
        )
        let pace = CaptionEngine.templates(for: .cheeky).first { $0.key == "c.pace" }!
        #expect(pace.make(context) == "James' 6th walk this week. Yo-Yo has notes about the pace.")

        let plant = CareRoutine(
            id: 1, companionId: 1, kind: .water, title: "Water", emoji: "💧", everyDays: 3, windows: [.anyTime],
            trackedFields: [], stars: 1, nudgeAfterMinutes: nil, sortOrder: 0
        )
        let entries = (0..<20).map { F.entry(Int64($0 + 1), day: 1 + $0 % 7, 9 + $0 / 7, routine: 1) }
        for tone in [CompanionTone.wholesome, .cheeky, .dramatic] {
            let captions = CaptionEngine.captions(for: entries, tone: tone, name: "Fern", routine: plant, names: names, calendar: F.calendar)
            for text in captions.values {
                #expect(!text.contains("walk"), "\(text)")
                #expect(!text.contains("pace"), "\(text)")
                #expect(!text.contains("came home"), "\(text)")
            }
        }
    }

    @Test("Counting is per walker per household week")
    func nthThisWeek() {
        // James walks Sun, Mon, Tue of one week, then Sun of the next; Mia once in between.
        let entries = [F.entry(1, day: 1, 7), F.entry(2, day: 2, 7), F.entry(5, day: 2, 18, by: [F.mia]), F.entry(3, day: 3, 7), F.entry(4, day: 8, 7)]
        let counts = CaptionEngine.weeklyCounts(entries.reversed(), calendar: F.calendar)
        #expect(counts == [1: 1, 2: 2, 5: 1, 3: 3, 4: 1])
    }

    @Test("Who text, ordinals and possessives")
    func helpers() {
        #expect(CaptionEngine.whoText([F.james], names: names) == "James")
        #expect(CaptionEngine.whoText([F.james, F.mia], names: names) == "James & Mia")
        #expect(CaptionEngine.whoText([F.james, F.mia, F.ava], names: names) == "James, Mia & Ava")
        #expect(CaptionEngine.whoText([], names: names) == "Someone")
        #expect(CaptionEngine.ordinal(1) == "1st")
        #expect(CaptionEngine.ordinal(2) == "2nd")
        #expect(CaptionEngine.ordinal(3) == "3rd")
        #expect(CaptionEngine.ordinal(11) == "11th")
        #expect(CaptionEngine.ordinal(22) == "22nd")
        #expect(CaptionEngine.ordinal(113) == "113th")
    }

    @Test("Wording adapts to the routine kind")
    func kindWording() {
        #expect(CareKind.walk.sentence(who: "Mia", name: "Yo-Yo", title: "Walk") == "Mia walked Yo-Yo")
        #expect(CareKind.walk.question(name: "Yo-Yo", title: "Walk") == "Who walked Yo-Yo?")
        #expect(CareKind.water.buttonTitle(name: "Fern", title: "Water") == "I watered Fern")
        #expect(CareKind.custom.question(name: "Rex", title: "Brush teeth") == "Who did brush teeth?")
        #expect(CompanionPresets.welcome(name: "Yo-Yo", routines: CompanionPresets.routines(for: .dog))
            == "Yo-Yo has joined the household and expects two walks a day. Zero excuses.")
        #expect(CompanionPresets.welcome(name: "Fern", routines: CompanionPresets.routines(for: .plant))
            == "Fern has joined the household and expects a watering every 3 days. Zero excuses.")
    }
}
