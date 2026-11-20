import Foundation
import GRDB
import Testing
@testable import Porchlight

/// A log made for a slot shows that slot done, whatever time of day it was written
/// (a widget's or reminder's "log it now", a tap on a late slot, catching up). Matching by
/// time alone put a breakfast logged after 1 pm in dinner's slot, which left breakfast
/// "not logged" on Today, the widgets and the wall.
@Suite("Care: a log made for a slot fills that slot")
struct CareSlotMatchingTests {
    let db: AppDatabase
    let calendar: Calendar
    let routines: [CareRoutine]
    let james: Person.ID
    let day: DayKey

    init() throws {
        db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)], timeZone: TimeZone(identifier: "UTC")!)
        calendar = household.calendar
        james = try db.snapshot().people[0].id
        var dog = CompanionDraft.new(species: .dog)
        dog.name = "Yo-Yo"
        var cat = CompanionDraft.new(species: .cat)
        cat.name = "Miso"
        let dogId = try db.saveCompanion(dog, householdId: household.id)
        let catId = try db.saveCompanion(cat, householdId: household.id)
        let snapshot = try db.writer.read(CompanionSnapshot.fetch)
        // The dog's walks (6-10 am, 5-8 pm) and the cat's meals (6-9 am, 5-7 pm).
        routines = [
            try #require(snapshot.routines(of: dogId).first { $0.kind == .walk }),
            try #require(snapshot.routines(of: catId).first { $0.kind == .feed }),
        ]
        day = DayKey(rawValue: "2026-11-20")
    }

    private func at(_ hour: Int, _ minute: Int = 30) -> Date {
        CareLogic.date(day, minute: hour * 60 + minute, calendar: calendar)
    }

    private func slots(_ routine: CareRoutine, now: Date) throws -> [CareSlot] {
        let snapshot = try db.writer.read(CompanionSnapshot.fetch)
        let byDay = CareLogic.byDay(snapshot.entries(of: routine.id), calendar: calendar)
        return CareLogic.slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar)
    }

    @Test("Every slot, logged now at any hour of the day, shows done", arguments: 0..<24)
    func everyHour(hour: Int) throws {
        for routine in routines {
            for slot in routine.effectiveWindows.indices {
                try db.writer.write { db in _ = try CareLog.deleteAll(db) }
                let now = at(hour)
                let draft = CareLogDraft(people: [james], occurredAt: now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
                guard case .logged = try db.logCare(routineId: routine.id, slot: slot, on: day, draft, now: now) else {
                    Issue.record("\(routine.kind) slot \(slot) at \(hour):30 wasn't logged"); continue
                }
                let shown = try slots(routine, now: now)
                #expect(shown[slot].entry != nil, "\(routine.kind) slot \(slot) logged at \(hour):30 shows done")
                #expect(shown.filter { $0.entry != nil }.count == 1, "and no other slot")
            }
        }
    }

    @Test("A late breakfast logged after 1 pm stays breakfast, and dinner is still asked for")
    func lateBreakfast() throws {
        let feed = routines[1]
        let now = at(13, 19)
        let draft = CareLogDraft(people: [james], occurredAt: now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        _ = try db.logCare(routineId: feed.id, slot: 0, on: day, draft, now: now)
        let shown = try slots(feed, now: at(17, 30))
        #expect(shown[0].entry != nil)
        #expect(shown[1].entry == nil && shown[1].state == .open)
        // Logging dinner once it's open fills dinner, not a second breakfast.
        let dinner = CareLogDraft(people: [james], occurredAt: at(17, 30), durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        guard case .logged = try db.logCare(routineId: feed.id, slot: 1, on: day, dinner, now: at(17, 30)) else {
            Issue.record("dinner was taken by the late breakfast"); return
        }
        #expect(try slots(feed, now: at(17, 31)).allSatisfy { $0.entry != nil })
    }

    @Test("A log meant for a slot stays that slot's unless its time lies in another slot's window")
    func slotRule() {
        let windows = routines[0].effectiveWindows  // 6-10 am, 5-8 pm
        #expect(CareLogic.slot(forMinute: 19 * 60 + 15, intended: 0, in: windows) == 1, "7:15 pm is inside the evening's window")
        #expect(CareLogic.slot(forMinute: 13 * 60 + 45, intended: 0, in: windows) == 0, "between the windows: still the morning's")
        #expect(CareLogic.slot(forMinute: 21 * 60, intended: 0, in: windows) == 0, "after every window: still the morning's")
        #expect(CareLogic.slot(forMinute: 7 * 60, intended: 1, in: windows) == 0)
        #expect(CareLogic.slot(forMinute: 13 * 60 + 45, intended: nil, in: windows) == 1, "with nothing meant, the nearest window")
        #expect(CareLogic.slot(forMinute: 13 * 60, intended: 5, in: windows) == 0, "a slot the routine no longer has")
    }

    @Test("A log placed by its time (the care sheet, an older build) still fills the nearest slot")
    func placedByTime() throws {
        let walk = routines[0]
        let log = try db.logCare(routineId: walk.id, CareLogDraft(people: [james], occurredAt: at(18), durationMinutes: 20, pee: nil, poo: nil, vibe: nil, note: nil), now: at(19))
        #expect(log.slot == nil)
        #expect(try slots(walk, now: at(19))[1].entry?.id == log.id)
    }

    @Test("A fix keeps the slot a log was made for, unless its new time lies in another slot's window")
    func fixing() throws {
        let walk = routines[0]
        let now = at(14)
        let draft = CareLogDraft(people: [james], occurredAt: now, durationMinutes: 20, pee: nil, poo: nil, vibe: nil, note: nil)
        guard case let .logged(log) = try db.logCare(routineId: walk.id, slot: 0, on: day, draft, now: now) else { Issue.record("not logged"); return }
        #expect(log.slot == 0)
        var longer = draft
        longer.durationMinutes = 45
        #expect(try db.updateCareLog(id: log.id, longer, now: at(15)).slot == 0)
        var later = longer
        later.occurredAt = at(14, 45)
        #expect(try db.updateCareLog(id: log.id, later, now: at(15)).slot == 0, "still between the windows: still the morning's")
        #expect(try slots(walk, now: at(15))[0].entry?.id == log.id)
        var evening = draft
        evening.occurredAt = at(17, 45)
        #expect(try db.updateCareLog(id: log.id, evening, now: at(18)).slot == nil)
        #expect(try slots(walk, now: at(18))[1].entry?.id == log.id)
    }
}
