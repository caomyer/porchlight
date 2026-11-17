import Foundation
import GRDB
import Testing
@testable import Porchlight

/// The summary the app writes for its widgets, and when it writes it
/// (docs/design/beyond-the-app.md, "The summary" and "When it is rewritten").
@Suite("Widget summary")
@MainActor
struct WidgetSummaryBuilderTests {
    private let db: AppDatabase
    private let household: Household
    private let james: Person.ID
    private let mia: Person.ID
    private let walk: CareRoutine
    /// Saturday, November 7 2026 at 6:05 pm: the evening walk is open.
    private let now: Date
    private var calendar: Calendar { household.calendar }
    private var today: DayKey { DayKey(now, calendar: calendar) }

    init() throws {
        db = try AppDatabase.inMemory()
        household = try db.createHousehold(
            name: "Home", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)],
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        let people = try db.snapshot().people
        james = people[0].id
        mia = people[1].id
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        let companionId = try db.saveCompanion(draft, householdId: household.id)
        walk = try #require(try db.writer.read(CompanionSnapshot.fetch).routines(of: companionId).first { $0.kind == .walk })
        now = household.calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 18, minute: 5))!
    }

    private func build(me: Person.ID?, role: DeviceRole = .personal) throws -> WidgetSummary {
        let (companions, home) = try db.writer.read { db in
            (try CompanionSnapshot.fetch(db), try HomeSnapshot.fetch(db, since: DayKey(now, calendar: calendar).adding(days: -7, calendar: calendar)))
        }
        return WidgetSummaryBuilder.make(companions: companions, home: home, me: me, role: role, now: now)
    }

    @Test("It holds today and tomorrow, with every slot's window and who did it")
    func contents() throws {
        let draft = CareLogDraft(people: [mia], occurredAt: now.addingTimeInterval(-25 * 60), durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        _ = try db.logCare(routineId: walk.id, draft, now: now)
        let summary = try build(me: james)
        #expect(summary.household == .init(name: "Home", timeZone: "America/Los_Angeles"))
        #expect(summary.me == .init(name: "James", color: PersonColor.blue.hex))
        #expect(summary.days == ["2026-11-07", "2026-11-08"])
        let yoyo = try #require(summary.companions.first)
        #expect(yoyo.name == "Yo-Yo")
        #expect(yoyo.face == Species.dog.emoji)
        let routine = try #require(yoyo.routines.first { $0.id == walk.id.description })
        #expect(routine.doneWord == "Walked")
        let evening = try #require(routine.slots.first { $0.day == "2026-11-07" && $0.index == 1 })
        #expect(evening.name == "evening walk")
        #expect(evening.doneBy == "Mia")
        #expect(evening.doneAt == now.addingTimeInterval(-25 * 60))
        #expect(routine.slots.contains { $0.day == "2026-11-08" && !$0.isDone })
        #expect(yoyo.lastCare == now.addingTimeInterval(-25 * 60))
    }

    @Test("My chores for today and tomorrow, my stars this week, and the groceries")
    func home() throws {
        let chore = try db.saveChore(
            ChoreDraft(title: "Dishes", emoji: "🍽️", ownerId: james, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 2),
            householdId: household.id
        )
        _ = try db.saveChore(
            ChoreDraft(title: "Mia's room", emoji: nil, ownerId: mia, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 1),
            householdId: household.id
        )
        _ = try db.completeChore(id: chore.id, day: today, personId: james, now: now)
        let list = try db.createList(title: "Groceries", kind: .grocery, householdId: household.id)
        for item in ["Oat milk", "Avocados", "Scallions", "Basil"] {
            _ = try db.addListItem(title: item, to: list.id, addedBy: james)
        }
        let summary = try build(me: james)
        #expect(summary.chores.map(\.title) == ["Dishes", "Dishes"])
        #expect(summary.chores.map(\.done) == [true, false])
        #expect(summary.glow?.myStarsThisWeek == 2)
        #expect(summary.groceries?.count == 4)
        #expect(summary.groceries?.firstItems == ["Oat milk", "Avocados", "Scallions"])
    }

    @Test("Without me, the household is named but nothing of anyone's")
    func noMe() throws {
        let summary = try build(me: nil)
        #expect(summary.household != nil)
        #expect(summary.me == nil)
        #expect(summary.companions.isEmpty)
        #expect(WidgetMoment.at(now, summary: summary).availability == .noMe)
    }

    @Test("Without a household, there is nothing but that")
    func noHousehold() throws {
        let summary = WidgetSummaryBuilder.make(companions: .empty, home: .empty, me: james, role: .personal, now: now)
        #expect(summary == WidgetSummary(writtenAt: now))
    }

    @Test("A shared screen writes only that it is one")
    func sharedScreen() throws {
        let summary = try build(me: james, role: .sharedScreen)
        #expect(summary == WidgetSummary(writtenAt: now, isSharedScreen: true))
    }

    // MARK: Writing

    @Test("A summary is written when it changed, or when the one on disk is an hour old")
    func whenToWrite() throws {
        let summary = try build(me: james)
        #expect(WidgetSummaryWrite.isNeeded(summary, over: nil))
        #expect(!WidgetSummaryWrite.isNeeded(summary.written(at: now.addingTimeInterval(59 * 60)), over: summary))
        #expect(WidgetSummaryWrite.isNeeded(summary.written(at: now.addingTimeInterval(60 * 60)), over: summary))
        var changed = summary
        changed.chores = []
        #expect(WidgetSummaryWrite.isNeeded(changed.written(at: now.addingTimeInterval(60)), over: summary))
        let marker = WidgetSummary(writtenAt: now, isSharedScreen: true)
        #expect(!WidgetSummaryWrite.isNeeded(marker.written(at: now.addingTimeInterval(30 * 24 * 3600)), over: marker))
    }

    @Test("The keeper writes once, writes nothing when nothing changed, and writes again after a log")
    func keeperWritesOnChange() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("widget-summary-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = UserDefaults(suiteName: "keeper-\(UUID().uuidString)")!
        let device = DeviceSettings(defaults: defaults, idiom: .phone, model: "iPhone")
        device.setMe(james, in: household.id)
        var writes: [WidgetSummary] = []
        var clock = now
        let keeper = WidgetSummaryKeeper(
            database: db, companions: CompanionStore(database: db), home: HomeStore(database: db), device: device,
            file: file, clock: { clock }, didWrite: { writes.append($0) }
        )
        #expect(await keeper.refresh())
        #expect(writes.count == 1)
        #expect(WidgetSummaryFile.read(from: file) == writes.last)

        clock = now.addingTimeInterval(120)
        #expect(await !keeper.refresh(), "nothing changed")
        #expect(writes.count == 1)

        let draft = CareLogDraft(people: [james], occurredAt: clock, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        _ = try db.logCare(routineId: walk.id, slot: 1, on: today, draft, now: clock)
        #expect(await keeper.refresh())
        #expect(writes.count == 2)
        #expect(writes.last?.companions.first?.routines.first?.slots.contains { $0.doneBy == "you" } == true)
    }

    @Test("On a shared screen the keeper marks the file once and then writes nothing")
    func keeperOnSharedScreen() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("widget-summary-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let device = DeviceSettings(defaults: UserDefaults(suiteName: "keeper-\(UUID().uuidString)")!, idiom: .pad, model: "iPad")
        var writes = 0
        var clock = now
        let keeper = WidgetSummaryKeeper(
            database: db, companions: CompanionStore(database: db), home: HomeStore(database: db), device: device,
            file: file, clock: { clock }, didWrite: { _ in writes += 1 }
        )
        #expect(await keeper.refresh())
        clock = now.addingTimeInterval(7 * 24 * 3600)
        let draft = CareLogDraft(people: [james], occurredAt: now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        _ = try db.logCare(routineId: walk.id, draft, now: now)
        #expect(await !keeper.refresh())
        #expect(writes == 1)
        #expect(WidgetSummaryFile.read(from: file)?.isSharedScreen == true)
    }
}
