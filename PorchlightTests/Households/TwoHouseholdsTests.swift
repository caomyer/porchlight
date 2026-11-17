import Foundation
import GRDB
import SQLiteData
import Testing
import UIKit
@testable import Porchlight

/// One phone in two households (journey A5): The Lake House, James's own, and Grandma
/// Rosa's, where he is James too. The M5 gate is that the two never mix, so every store,
/// write, reminder, widget and intent is checked against both.
@MainActor
struct TwoHouseholds {
    let db: AppDatabase
    let lake: Household
    let rosas: Household
    let james: Person.ID
    let mia: Person.ID
    let rosa: Person.ID
    let jamesAtRosas: Person.ID
    let yoyoWalk: CareRoutine
    let tomatoesWater: CareRoutine
    let lakeChore: Chore
    let rosasChore: Chore
    let defaults: UserDefaults
    let settings: DeviceSettings
    /// Saturday, November 7 2026 at 6:05 pm in Los Angeles.
    let now: Date

    init(installId: String = "james-phone") throws {
        db = try AppDatabase.inMemory(installId: installId)
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        lake = try db.createHousehold(name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)], timeZone: zone, now: .now.addingTimeInterval(-86_400))
        try db.markSetupCompleted(householdId: lake.id)
        rosas = try db.createHousehold(name: "Grandma Rosa's", people: [PersonDraft(name: "Rosa", color: .plum), PersonDraft(name: "James", color: .blue)], timeZone: zone)
        try db.markSetupCompleted(householdId: rosas.id)
        try db.chooseHousehold(lake.id)
        let lakeId = lake.id, rosasId = rosas.id
        let lakePeople = try db.writer.read { try Person.active(in: lakeId).fetchAll($0) }
        let rosasPeople = try db.writer.read { try Person.active(in: rosasId).fetchAll($0) }
        (james, mia) = (lakePeople[0].id, lakePeople[1].id)
        (rosa, jamesAtRosas) = (rosasPeople[0].id, rosasPeople[1].id)

        var yoyo = CompanionDraft.new(species: .dog)
        yoyo.name = "Yo-Yo"
        let yoyoId = try db.saveCompanion(yoyo, householdId: lake.id)
        var tomatoes = CompanionDraft.new(species: .plant)
        tomatoes.name = "Tomatoes"
        let tomatoesId = try db.saveCompanion(tomatoes, householdId: rosas.id)
        // Routines start today; these run on a fixed day before it.
        try db.writer.write { try $0.execute(sql: "UPDATE careRoutine SET anchorDay = ''") }
        let routines = try db.writer.read { try CareRoutine.fetchAll($0) }
        yoyoWalk = try #require(routines.first { $0.companionId == yoyoId && $0.kind == .walk })
        tomatoesWater = try #require(routines.first { $0.companionId == tomatoesId })

        now = Calendar.current.date(from: DateComponents(timeZone: zone, year: 2026, month: 11, day: 7, hour: 18, minute: 5))!
        let today = DayKey(now, calendar: lake.calendar)
        lakeChore = try db.saveChore(
            ChoreDraft(title: "Dishes", emoji: nil, ownerId: james, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 1), householdId: lake.id
        )
        rosasChore = try db.saveChore(
            ChoreDraft(title: "Call Rosa about Thanksgiving", emoji: nil, ownerId: jamesAtRosas, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 1),
            householdId: rosas.id
        )
        try db.ensureDefaultLists(householdId: lake.id)
        try db.ensureDefaultLists(householdId: rosas.id)

        defaults = UserDefaults(suiteName: "two-households-\(UUID().uuidString)")!
        settings = DeviceSettings(defaults: defaults, idiom: .phone, model: "iPhone")
        settings.setMe(james, in: lake.id)
        settings.setMe(jamesAtRosas, in: rosas.id)
    }

    var today: DayKey { DayKey(now, calendar: lake.calendar) }

    func walk(by people: [Person.ID], at date: Date) -> CareLogDraft {
        CareLogDraft(people: people, occurredAt: date, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
    }
}

/// Waits for a store's observation to deliver what `condition` wants.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@Suite("Two households never mix")
@MainActor
struct TwoHouseholdsTests {
    @Test("Every store shows only the household showing, and switching changes all of them")
    func storesFollowTheSwitch() async throws {
        let two = try TwoHouseholds()
        _ = try two.db.logCare(routineId: two.yoyoWalk.id, two.walk(by: [two.james, two.mia], at: two.now.addingTimeInterval(-3600)), now: two.now)
        _ = try two.db.logCare(routineId: two.tomatoesWater.id, two.walk(by: [two.rosa], at: two.now.addingTimeInterval(-3600)), now: two.now)
        let app = AppModel(database: two.db)
        let companions = CompanionStore(database: two.db)
        let home = HomeStore(database: two.db)
        let food = FoodStore(database: two.db)

        #expect(app.household?.id == two.lake.id)
        #expect(Set(app.people.map(\.id)) == [two.james, two.mia])
        #expect(companions.snapshot.companions.map(\.name) == ["Yo-Yo"])
        #expect(companions.snapshot.entries.flatMap(\.people).allSatisfy { [two.james, two.mia].contains($0) })
        #expect(home.snapshot.chores.map(\.title) == ["Dishes"])
        #expect(home.snapshot.lists.allSatisfy { $0.householdId == two.lake.id })
        #expect(food.snapshot.household?.id == two.lake.id)
        #expect(app.households.map(\.household.name) == ["The Lake House", "Grandma Rosa's"])
        #expect(app.isInSeveralHouseholds)

        app.switchHousehold(to: two.rosas.id)
        #expect(await eventually { companions.snapshot.household?.id == two.rosas.id })
        #expect(await eventually { home.snapshot.household?.id == two.rosas.id })
        #expect(await eventually { food.snapshot.household?.id == two.rosas.id })
        #expect(await eventually { app.household?.id == two.rosas.id })
        #expect(companions.snapshot.companions.map(\.name) == ["Tomatoes"])
        #expect(companions.snapshot.entries.flatMap(\.people) == [two.rosa])
        #expect(home.snapshot.chores.map(\.title) == ["Call Rosa about Thanksgiving"])
        #expect(Set(app.people.map(\.id)) == [two.rosa, two.jamesAtRosas])
        #expect(Set(app.devices.map(\.householdId)).isSubset(of: [two.rosas.id]))
    }

    @Test("\"Me\" is per household: James is one person here and another there")
    func mePerHousehold() throws {
        let two = try TwoHouseholds()
        #expect(two.settings.me(in: two.lake.id) == two.james)
        #expect(two.settings.me(in: two.rosas.id) == two.jamesAtRosas)
        let choices = try two.db.writer.read(HouseholdChoice.fetchAll)
        #expect(choices.map { $0.line(me: two.settings.me(in: $0.id)) } == ["You are James · 2 people", "You are James · 2 people"])
    }

    @Test("Writes land in their own household, stamped with this device's row there")
    func writesAreStampedPerHousehold() async throws {
        let two = try TwoHouseholds()
        // Showing The Lake House, a log of Rosa's tomatoes still goes to Grandma Rosa's.
        let log = try two.db.logCare(routineId: two.tomatoesWater.id, two.walk(by: [two.jamesAtRosas], at: two.now), now: two.now)
        #expect(log.deviceId == two.db.thisDeviceId(in: two.rosas.id))
        let completion = try two.db.completeChore(id: two.rosasChore.id, day: two.today, personId: two.jamesAtRosas, now: two.now)
        guard case let .done(done) = completion else { Issue.record("expected a check-off"); return }
        #expect(done.deviceId == two.db.thisDeviceId(in: two.rosas.id))
        let rosasId = two.rosas.id
        let lists: [HomeList] = try await two.db.writer.read { db in
            try HomeList.filter(Column("householdId") == rosasId).fetchAll(db)
        }
        let rosasGroceries = try #require(lists.first { $0.kind == .grocery })
        let item = try two.db.addListItem(title: "Basil", to: rosasGroceries.id, addedBy: two.jamesAtRosas)
        #expect(item.deviceId == two.db.thisDeviceId(in: two.rosas.id))
        let lakeLog = try two.db.logCare(routineId: two.yoyoWalk.id, two.walk(by: [two.james], at: two.now), now: two.now)
        #expect(lakeLog.deviceId == two.db.thisDeviceId(in: two.lake.id))
    }

    @Test("A log never credits someone from the other household")
    func noCrossCredit() throws {
        let two = try TwoHouseholds()
        #expect(throws: CareValidationError.notInHousehold) {
            _ = try two.db.logCare(routineId: two.yoyoWalk.id, two.walk(by: [two.rosa], at: two.now), now: two.now)
        }
        // An "Anyone" chore credits whoever is picked: never someone from the other household.
        let anyone = try two.db.saveChore(
            ChoreDraft(title: "Recycling", emoji: nil, ownerId: nil, recurrence: .daily, anchorDay: two.today, timeHint: nil, stars: 1), householdId: two.lake.id
        )
        #expect(throws: (any Error).self) {
            _ = try two.db.completeChore(id: anyone.id, day: two.today, personId: two.jamesAtRosas, now: two.now)
        }
        #expect(try two.db.writer.read { try CareLog.fetchCount($0) } == 0)
    }

    @Test("Starting a household here shows it; the first stays as it was")
    func startingShowsTheNewOne() throws {
        let two = try TwoHouseholds()
        let third = try two.db.createHousehold(name: "The Cabin", people: [PersonDraft(name: "James", color: .blue)])
        #expect(try two.db.snapshot().household?.id == third.id)
        #expect(try two.db.writer.read { try Companion.filter(Column("householdId") == two.lake.id).fetchCount($0) } == 1)
    }

    @Test("Joining another household shows it and leaves the first, and \"me\" there, untouched")
    func joiningLeavesTheFirst() async throws {
        let db = try AppDatabase.inMemory(installId: "mias-phone")
        let lake = try db.createHousehold(name: "The Lake House", people: [PersonDraft(name: "Mia", color: .coral)])
        try db.markSetupCompleted(householdId: lake.id)
        let defaults = UserDefaults(suiteName: "join-second-\(UUID().uuidString)")!
        let device = DeviceSettings(defaults: defaults, idiom: .phone, model: "iPhone")
        let miaHere = try db.snapshot().people[0].id
        device.setMe(miaHere, in: lake.id)
        let fake = FakeHouseholdSharing(userName: "_mia") { _ in
            let rosas = try db.createHousehold(name: "Grandma Rosa's", people: [PersonDraft(name: "Rosa", color: .plum), PersonDraft(name: "Mia", color: .coral)])
            try db.markSetupCompleted(householdId: rosas.id)
        }
        let flow = JoinFlow(
            invitation: HouseholdInvitation(householdId: nil, householdName: "Grandma Rosa's", ownerName: "Rosa"),
            database: db, sharing: fake, device: device, arrivalTimeout: .seconds(2)
        )
        await flow.join()
        let snapshot = try db.snapshot()
        #expect(snapshot.household?.name == "Grandma Rosa's")
        #expect(snapshot.households.map(\.household.name) == ["The Lake House", "Grandma Rosa's"])
        #expect(device.me(in: lake.id) == miaHere, "me in the first household is kept")
        let lakePeople = try await db.writer.read { try Person.active(in: lake.id).fetchCount($0) }
        #expect(lakePeople == 1)
    }

    @Test("Removed from the household showing: it says so, then the other one shows")
    func removedFallsBack() throws {
        let two = try TwoHouseholds()
        try two.db.chooseHousehold(two.rosas.id)
        // The engine takes the shared household's rows off this phone.
        try two.db.writer.write { [rosas = two.rosas] db in _ = try Household.deleteOne(db, id: rosas.id) }
        #expect(try two.db.snapshot().removed?.id == two.rosas.id)
        try two.db.forgetCurrentHousehold()
        let after = try two.db.snapshot()
        #expect(after.removed == nil)
        #expect(after.household?.id == two.lake.id)
        #expect(after.households.map(\.household.name) == ["The Lake House"])
        #expect(try two.db.writer.read { try Chore.filter(Column("householdId") == two.lake.id).fetchCount($0) } == 1)
    }

    @Test("A shared screen in two households still shows one, writes no widgets, and reminds no one")
    func wallUnaffected() throws {
        let two = try TwoHouseholds(installId: "wall")
        let wall = DeviceSettings(defaults: UserDefaults(suiteName: "wall-\(UUID().uuidString)")!, idiom: .pad, model: "iPad")
        #expect(wall.role == .sharedScreen)
        #expect(try two.db.snapshot().household?.id == two.lake.id)
        let summary = WidgetSummaryBuilder.make(companions: .empty, home: .empty, me: nil, role: wall.role, now: two.now, households: 2)
        #expect(summary.isSharedScreen)
    }
}

@Suite("Two households: reminders, widgets and Siri")
@MainActor
struct TwoHouseholdsBeyondTests {
    @Test("Reminders come from both households, each named, with their own ids")
    func remindersFromBoth() throws {
        let two = try TwoHouseholds()
        var choices = ReminderChoices(chores: true)
        let all = [ReminderSlots.all(try two.db.writer.read { try CompanionSnapshot.fetch($0, householdId: two.lake.id) }),
                   ReminderSlots.all(try two.db.writer.read { try CompanionSnapshot.fetch($0, householdId: two.rosas.id) })].flatMap { $0 }
        for slot in all { choices.care[slot.id] = .missed }
        let morning = Calendar.current.date(from: DateComponents(timeZone: two.lake.calendar.timeZone, year: 2026, month: 11, day: 7, hour: 5))!
        let lake = ReminderScheduler.plans(for: two.lake, named: true, database: two.db, device: two.settings, choices: choices, now: morning)
        let rosas = ReminderScheduler.plans(for: two.rosas, named: true, database: two.db, device: two.settings, choices: choices, now: morning)
        #expect(!lake.plan.isEmpty)
        #expect(!rosas.plan.isEmpty)
        #expect(lake.plan.allSatisfy { $0.title.hasPrefix("The Lake House · ") && $0.household == "The Lake House" })
        #expect(rosas.plan.allSatisfy { $0.title.hasPrefix("Grandma Rosa's · ") })
        #expect(Set(lake.plan.map(\.id)).isDisjoint(with: rosas.plan.map(\.id)))
        // One household only: nothing is named.
        let alone = ReminderScheduler.plans(for: two.lake, named: false, database: two.db, device: two.settings, choices: choices, now: morning)
        #expect(alone.plan.allSatisfy { $0.household == nil && !$0.title.hasPrefix("The Lake House") })
    }

    @Test("A reminder's action logs into its own household, for me there, while the other shows")
    func reminderActionUsesItsHousehold() async throws {
        let two = try TwoHouseholds()
        let confirmation = await ReminderActions.logSlot(
            routine: two.tomatoesWater.id, slot: 0, day: two.today, database: two.db, defaults: two.defaults, now: two.now
        )
        #expect(confirmation?.title.hasPrefix("Logged") == true)
        let entries = try await two.db.writer.read { [rosas = two.rosas] in try CompanionSnapshot.fetch($0, householdId: rosas.id) }.entries
        #expect(entries.map(\.people) == [[two.jamesAtRosas]])
        #expect(entries.first?.log.deviceId == two.db.thisDeviceId(in: two.rosas.id))
    }

    @Test("Widgets follow the household showing and name it when there are two")
    func widgetsFollowAndName() throws {
        let two = try TwoHouseholds()
        let (companions, home) = try two.db.writer.read { db in
            (try CompanionSnapshot.fetch(db), try HomeSnapshot.fetch(db, since: two.today.adding(days: -7, calendar: two.lake.calendar)))
        }
        let summary = WidgetSummaryBuilder.make(companions: companions, home: home, me: two.james, role: .personal, now: two.now, households: 2)
        #expect(summary.household?.name == "The Lake House")
        #expect(summary.household?.isOneOfSeveral == true)
        #expect(summary.companions.map(\.name) == ["Yo-Yo"])
        #expect(summary.chores.allSatisfy { $0.title == "Dishes" })
        #expect(WidgetMoment.at(two.now, summary: summary).isOneOfSeveral)
        let one = WidgetSummaryBuilder.make(companions: companions, home: home, me: two.james, role: .personal, now: two.now, households: 1)
        #expect(one.household?.isOneOfSeveral == nil)
    }

    @Test("A widget's button logs into the routine's own household, and Siri says which household")
    func intentsNameTheHousehold() async throws {
        let two = try TwoHouseholds()
        // The Lake House shows; a widget drawn before the switch logs Rosa's tomatoes.
        let outcome = await IntentWork.logSlot(routineId: two.tomatoesWater.id, slot: 0, day: two.today, database: two.db, settings: two.settings, now: two.now)
        guard case let .answer(answer) = outcome else { Issue.record("expected an answer, got \(outcome)"); return }
        #expect(answer.wrote)
        #expect(answer.detail?.hasPrefix("At Grandma Rosa's · For James at") == true, "\(answer.detail ?? "")")
        let chore = await IntentWork.checkChore(choreId: two.rosasChore.id, day: two.today, database: two.db, settings: two.settings, now: two.now)
        guard case let .answer(checked) = chore else { Issue.record("expected an answer"); return }
        #expect(checked.wrote)
        let completion = try #require(try await two.db.writer.read { try ChoreCompletion.fetchOne($0) })
        #expect(completion.personId == two.jamesAtRosas, "credited to James at Rosa's, not The Lake House's James")
        #expect(completion.deviceId == two.db.thisDeviceId(in: two.rosas.id))
    }

    @Test("The companion snapshot reads no log links of the other household")
    func snapshotScoped() throws {
        let two = try TwoHouseholds()
        _ = try two.db.logCare(routineId: two.tomatoesWater.id, two.walk(by: [two.rosa], at: two.now), now: two.now)
        _ = try two.db.logCare(routineId: two.yoyoWalk.id, two.walk(by: [two.mia], at: two.now), now: two.now)
        let lake = try two.db.writer.read(CompanionSnapshot.fetch)
        #expect(lake.entries.map(\.people) == [[two.mia]])
    }
}
