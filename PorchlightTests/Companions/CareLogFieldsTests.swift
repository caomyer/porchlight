import Foundation
import Testing
@testable import Porchlight

/// The care form's rules, shared by the wall's log sheet and the phone's care sheet.
@Suite("Care log fields")
struct CareLogFieldsTests {
    private typealias F = CareFixture

    private func day(_ key: DayKey, history: [CareEntry] = [], routine: CareRoutine = F.walk) -> CareLogDay {
        CareLogDay(routine: routine, day: key, today: F.key(7), now: F.date(18, 0), calendar: F.calendar, history: history)
    }

    @Test("A new log starts with who was given, just now, as long as recent walks")
    func newLog() {
        let history = [F.entry(1, day: 6, 7, minutes: 28), F.entry(2, day: 6, 18, minutes: 32)]
        let fields = CareLogFields.new(people: [F.mia], for: day(F.key(7), history: history), catchUpSlot: nil)
        #expect(fields.people == [F.mia])
        #expect(fields.when == .justNow)
        #expect(fields.duration == 30)
    }

    @Test("Catching up starts at the slot's usual time on that day")
    func catchUp() {
        let history = [F.entry(1, day: 5, 7, 30), F.entry(2, day: 6, 7, 30)]
        let logDay = day(F.key(4), history: history)
        let fields = CareLogFields.new(people: [F.james], for: logDay, catchUpSlot: 0)
        #expect(fields.when == .at(F.date(day: 4, 7, 30)))
        #expect(logDay.suggestions.map(\.title) == ["Morning", "Evening"])
    }

    @Test("The draft keeps only what the routine tracks")
    func draftFields() {
        var fields = CareLogFields(people: [F.james])
        fields.when = .at(F.date(17, 30))
        fields.duration = 45
        let walk = fields.draft(for: day(F.key(7)))
        #expect(walk.durationMinutes == 45)
        #expect(walk.pee == true)
        #expect(walk.occurredAt == F.date(17, 30))
        let water = fields.draft(for: day(F.key(7), routine: F.water))
        #expect(water.durationMinutes == nil)
        #expect(water.pee == nil)
        #expect(water.vibe == nil)
    }
}
