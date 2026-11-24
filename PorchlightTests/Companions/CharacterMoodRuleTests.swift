import Foundation
import Testing
@testable import Porchlight

/// How a companion is doing, as its character shows it (docs/design/companion-characters.md,
/// "Moods follow the day"): one pure rule, and its order when two moods apply.
@Suite("A character's mood follows the day")
struct CharacterMoodRuleTests {
    typealias Owed = CharacterMoodRule.Owed

    private static let morning = CareWindow.hours("Morning", 6, 10)
    private static let evening = CareWindow.hours("Evening", 17, 20)
    private static let dinner = CareWindow.hours("Dinner", 17, 19)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func minute(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    /// The mood at `minute` of the day, with the last log `ago` seconds back.
    private func mood(_ owed: [Owed], at minute: Int, logged ago: TimeInterval? = nil) -> CharacterMood {
        CharacterMoodRule.mood(owed: owed, lastLogged: ago.map { Self.now.addingTimeInterval(-$0) }, now: Self.now, minute: minute)
    }

    @Test("Before a slot opens, in the day, a companion is doing fine")
    func fine() {
        let walks = [Owed(window: Self.morning, isDone: true, nudgeAfterMinutes: 60), Owed(window: Self.evening, isDone: false, nudgeAfterMinutes: 60)]
        #expect(mood(walks, at: Self.minute(13)) == .fine, "morning done, evening not open yet")
        #expect(mood([], at: Self.minute(13)) == .fine, "nothing owed today")
        #expect(mood([Owed(window: Self.evening, isDone: false, nudgeAfterMinutes: nil)], at: Self.minute(16, 59)) == .fine)
    }

    @Test("A slot that is open now, or late, is waiting")
    func waiting() {
        let evening = [Owed(window: Self.evening, isDone: false, nudgeAfterMinutes: 60)]
        #expect(mood(evening, at: Self.minute(17)) == .waiting, "the window just opened")
        #expect(mood(evening, at: Self.minute(18, 30)) == .waiting, "past its nudge")
        #expect(mood(evening, at: Self.minute(20, 30)) == .waiting, "after the window closed, still owed")
        #expect(mood([Owed(window: Self.morning, isDone: false, nudgeAfterMinutes: 60)], at: Self.minute(15)) == .waiting, "a morning never logged waits all day")
    }

    @Test("Something logged within the last hour is the zoomies, and then it wears off")
    func zoomies() {
        let walks = [Owed(window: Self.morning, isDone: true, nudgeAfterMinutes: 60), Owed(window: Self.evening, isDone: false, nudgeAfterMinutes: 60)]
        #expect(mood(walks, at: Self.minute(9), logged: 60) == .zoomies)
        #expect(mood(walks, at: Self.minute(9), logged: 59 * 60) == .zoomies)
        #expect(mood(walks, at: Self.minute(11), logged: 61 * 60) == .fine, "an hour on")
        #expect(mood(walks, at: Self.minute(9), logged: -120) == .fine, "a log set in the future is not just now")
    }

    @Test("Everything owed today done, or night, is asleep")
    func asleep() {
        let done = [Owed(window: Self.morning, isDone: true, nudgeAfterMinutes: 60), Owed(window: Self.evening, isDone: true, nudgeAfterMinutes: 60)]
        #expect(mood(done, at: Self.minute(20, 30), logged: 2 * 3600) == .asleep, "all done, in the evening")
        #expect(mood([Owed(window: .anyTime, isDone: true, nudgeAfterMinutes: nil)], at: Self.minute(11), logged: 3 * 3600) == .asleep, "one slot a day, done")
        let upcoming = [Owed(window: Self.morning, isDone: false, nudgeAfterMinutes: 60)]
        #expect(mood(upcoming, at: Self.minute(21)) == .waiting, "9 PM with the morning's still owed: see the order")
        #expect(mood([], at: Self.minute(21)) == .asleep, "9 PM")
        #expect(mood([], at: Self.minute(20, 59)) == .fine)
        #expect(mood(upcoming, at: Self.minute(2)) == .asleep, "2 AM, before the morning opens")
        #expect(mood(upcoming, at: Self.minute(5, 59)) == .asleep)
        #expect(mood([Owed(window: Self.evening, isDone: false, nudgeAfterMinutes: 60)], at: Self.minute(6)) == .fine, "6 AM: up")
    }

    @Test("When two apply: overdue care first, then the zoomies, then an open slot, then sleep")
    func order() {
        let lateDinner = Owed(window: Self.dinner, isDone: false, nudgeAfterMinutes: nil)
        let walked = Owed(window: Self.evening, isDone: true, nudgeAfterMinutes: 60)
        // A walk just logged while dinner has merely opened: the thanks shows, for its hour.
        #expect(mood([walked, lateDinner], at: Self.minute(17, 40), logged: 300) == .zoomies)
        // The same walk, but dinner's window has closed: owed care is never hidden.
        #expect(mood([walked, lateDinner], at: Self.minute(19, 10), logged: 300) == .waiting)
        // Nor when an open slot is past its nudge.
        let nudgedWalk = Owed(window: Self.evening, isDone: false, nudgeAfterMinutes: 60)
        #expect(mood([nudgedWalk], at: Self.minute(18, 5), logged: 300) == .waiting)
        #expect(mood([nudgedWalk], at: Self.minute(17, 30), logged: 300) == .zoomies, "open, not yet nudged")
        // 9 PM with a slot still owed: it waits up.
        #expect(mood([Owed(window: Self.evening, isDone: false, nudgeAfterMinutes: 60)], at: Self.minute(21, 30)) == .waiting)
        // 9 PM, everything done ten minutes ago: still the zoomies, then asleep.
        #expect(mood([walked], at: Self.minute(21, 30), logged: 600) == .zoomies)
        #expect(mood([walked], at: Self.minute(22, 45), logged: 75 * 60) == .asleep)
    }

    @Test("An all-day slot waits from midnight but is only overdue past its nudge")
    func allDay() {
        let water = Owed(window: .anyTime, isDone: false, nudgeAfterMinutes: nil)
        #expect(mood([water], at: Self.minute(10)) == .waiting)
        #expect(mood([water], at: Self.minute(10), logged: 300) == .zoomies, "never late, so a log's thanks shows over it")
        #expect(Owed(window: .anyTime, isDone: false, nudgeAfterMinutes: 600).standing(at: Self.minute(11)).overdue)
        #expect(!Owed(window: Self.evening, isDone: true, nudgeAfterMinutes: 60).standing(at: Self.minute(23)).waits, "done is never waiting")
    }

    // MARK: From a report

    /// A dog with the usual routines (walks 6 to 10 and 5 to 8 with a nudge an hour in; meals
    /// 6 to 9 and 5 to 7), added eleven days ago, with `logs` today as (routine, hour, minute).
    private func report(atMinute minute: Int, logs: [(kind: CareKind, hour: Int, minute: Int)] = []) throws -> CompanionReport {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        let person = try #require(try db.snapshot().people.first).id
        let calendar = try #require(try db.snapshot().household).calendar
        let today = DayKey(CompanionClock.now(), calendar: calendar)
        let now = CareLogic.date(today, minute: minute, calendar: calendar)
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        for index in draft.routines.indices { draft.routines[index].startDay = today.adding(days: -10, calendar: calendar) }
        let id = try db.saveCompanion(draft, householdId: household.id, now: now.addingTimeInterval(-11 * 24 * 3600))
        let routines = try db.writer.read(CompanionSnapshot.fetch).routines(of: id)
        for log in logs {
            let routine = try #require(routines.first { $0.kind == log.kind })
            let at = CareLogic.date(today, minute: log.hour * 60 + log.minute, calendar: calendar)
            try db.logCare(routineId: routine.id, CareLogDraft(people: [person], occurredAt: at), now: at)
        }
        return try #require(CompanionReport.make(snapshot: try db.writer.read(CompanionSnapshot.fetch), companionId: id, now: now))
    }

    @Test("A report's mood reads its own slots, logs and household time")
    func fromAReport() throws {
        #expect(try report(atMinute: Self.minute(5)).characterMood == .asleep, "5 AM")
        #expect(try report(atMinute: Self.minute(7)).characterMood == .waiting, "walk and breakfast open")
        let morningDone: [(kind: CareKind, hour: Int, minute: Int)] = [(.walk, 7, 0), (.feed, 7, 10)]
        #expect(try report(atMinute: Self.minute(7, 30), logs: morningDone).characterMood == .zoomies, "just logged")
        #expect(try report(atMinute: Self.minute(13), logs: morningDone).characterMood == .fine, "morning done, evening not open")
        #expect(try report(atMinute: Self.minute(18, 30), logs: morningDone).characterMood == .waiting, "evening owed, past the walk's nudge")
        let allDone = morningDone + [(.walk, 17, 30), (.feed, 17, 40)]
        #expect(try report(atMinute: Self.minute(19, 30), logs: allDone).characterMood == .asleep, "everything done, over an hour ago")
        #expect(try report(atMinute: Self.minute(21, 15), logs: morningDone).characterMood == .waiting, "9 PM, the evening still owed")
    }

    @Test("Asked about another day than the report's, only the hour and the last log speak")
    func anotherDay() throws {
        let report = try report(atMinute: Self.minute(18, 30))
        #expect(report.characterMood == .waiting)
        let nextNight = report.now.addingTimeInterval(8 * 3600)
        #expect(CharacterMoodRule.mood(for: report, now: nextNight) == .asleep, "2:30 AM the next day: yesterday's slots say nothing")
    }

    @Test("A companion added after a window closed never waits for that slot")
    func notOwed() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        let calendar = try #require(try db.snapshot().household).calendar
        let today = DayKey(CompanionClock.now(), calendar: calendar)
        let arrived = CareLogic.date(today, minute: Self.minute(12), calendar: calendar)
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Pip"
        let id = try db.saveCompanion(draft, householdId: household.id, now: arrived)
        let report = try #require(CompanionReport.make(snapshot: try db.writer.read(CompanionSnapshot.fetch), companionId: id, now: arrived.addingTimeInterval(3600)))
        #expect(report.characterMood == .fine, "the morning's walk and breakfast closed before it arrived; the evening hasn't opened")
    }
}
