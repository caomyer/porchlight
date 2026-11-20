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

    @Test("Fixing a log opens on its own day, with the log as it stands")
    func fixingALog() {
        let entry = F.entry(5, day: 5, 7, 40, by: [F.james, F.mia], minutes: 30, pee: true, poo: false, vibe: .squirrel)
        let logDay = CareLogDay.forSheet(
            routine: F.walk, editing: entry, catchUpDay: F.key(4), today: F.key(7), now: F.date(18, 0), calendar: F.calendar, history: [entry]
        )
        #expect(logDay.day == F.key(5), "the log's day, before a missed slot's or today")
        #expect(!logDay.isToday)
        let fields = CareLogFields(editing: entry, people: entry.people)
        #expect(fields.people == [F.james, F.mia])
        #expect(fields.when == .at(F.date(day: 5, 7, 40)))
        #expect(fields.duration == 30 && fields.pee && !fields.poo && fields.vibe == .squirrel)
        #expect(fields.draft(for: logDay).occurredAt == F.date(day: 5, 7, 40), "saving untouched keeps its time")

        let catchUp = CareLogDay.forSheet(routine: F.walk, editing: nil, catchUpDay: F.key(4), today: F.key(7), now: F.date(18, 0), calendar: F.calendar, history: [])
        #expect(catchUp.day == F.key(4))
        let new = CareLogDay.forSheet(routine: F.walk, editing: nil, catchUpDay: nil, today: F.key(7), now: F.date(18, 0), calendar: F.calendar, history: [])
        #expect(new.day == F.key(7))
    }

    @Test("A saved length that isn't a choice still shows, picked, and stays to go back to")
    func savedLength() {
        var fields = CareLogFields(editing: F.entry(5, 7, 40, minutes: 12), people: [F.james])
        #expect(fields.durationChoices == [10, 12, 20, 30, 45, 60])
        #expect(fields.duration == 12)
        fields.duration = 20
        #expect(fields.durationChoices.contains(12), "picking another length keeps the saved one on offer")
        #expect(CareLogFields(editing: F.entry(6, 7, 40, minutes: 30), people: [F.james]).durationChoices == CareLogFields.durations)
        #expect(CareLogFields(people: [F.james]).durationChoices == CareLogFields.durations, "a new log offers the usual lengths")
        #expect(CareLogFields.durationTitle(60) == "1 hr+")
        #expect(CareLogFields.durationTitle(90) == "90 min", "a long saved walk says its length, not a second \"1 hr+\"")
        #expect(CareLogFields.durationTitle(12) == "12 min")
    }

    @Test("The wall and the phone say the same when fixing a log")
    func fixingWords() {
        #expect(CareLogWording.editTitle(CareWords(F.walk, species: .dog)) == "Edit walk")
        #expect(CareLogWording.confirmRemove(CareWords(F.walk, species: .dog)) == "Remove walk")
        #expect(CareLogWording.saveChanges == "Save changes")
        #expect(CareLogWording.remove == "Remove" && CareLogWording.keep == "Keep it")
        #expect(CareLogWording.editSubtitle == "Fix who, when or how it went")
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
