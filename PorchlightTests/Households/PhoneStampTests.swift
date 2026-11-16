import Foundation
import GRDB
import Testing
@testable import Porchlight

/// Every way the phone adds a row goes through the write layer's stamp, so the wall can
/// say "from Mia's phone" (docs/design/households.md, "Where a row came from").
@Suite("Phone writes say which device wrote them")
@MainActor
struct PhoneStampTests {
    @Test("Care from Today and the care sheet, Pitch in, Lists, Glow and a meal all carry this phone's device")
    func phonePathsStamp() throws {
        let db = try AppDatabase.inMemory(installId: "mias-phone")
        let household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: household.id)
        try db.rememberCurrentHousehold()
        let mia = try #require(try db.snapshot().people.last).id
        let calendar = household.calendar
        let today = DayKey(.now, calendar: calendar)
        var yoyo = CompanionDraft.new(species: .dog)
        yoyo.name = "Yo-Yo"
        let companionId = try db.saveCompanion(yoyo, householdId: household.id)
        _ = try db.saveChore(
            ChoreDraft(title: "Dishes", emoji: "🍽️", ownerId: mia, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 2),
            householdId: household.id
        )
        _ = try db.saveReward(RewardDraft(title: "Zoo", emoji: nil, targetStars: 1, ownerId: nil), householdId: household.id, today: today)
        _ = try db.ensureFoodJournal(householdId: household.id)

        let companions = CompanionStore(database: db)
        let home = HomeStore(database: db)
        home.ensureDefaultLists()
        let walk = try #require(companions.snapshot.routines(of: companionId).first { $0.kind == .walk })
        let draft = CareLogDraft(people: [mia], occurredAt: .now, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)

        // Today's one tap (by slot) and the care sheet's full log.
        let morning = calendar.date(byAdding: .hour, value: 8, to: today.startDate(in: calendar))!
        _ = companions.log(routineId: walk.id, slot: 0, on: today, draft, now: morning)
        _ = companions.log(routineId: walk.id, draft)
        // Pitch in, then Glow once the stars are there, Lists, and Food.
        let chore = try #require(try db.writer.read { try Chore.fetchOne($0) })
        _ = home.complete(chore, by: mia)
        let refreshed = HomeStore(database: db)
        let reward = try #require(refreshed.snapshot.rewards.first)
        #expect(refreshed.cashIn(reward) != nil)
        let list = try #require(try db.writer.read { try HomeList.fetchOne($0) })
        #expect(home.addItem("Basil", to: list, addedBy: mia))
        _ = try FoodStore(database: db).addMeal(MealDraft(
            day: today, slot: MealSlot.defaultNames[1], source: .home, title: "Pho", emoji: nil, eaterIds: [mia], eatenAt: .now, place: nil
        ))

        let stamp = db.thisDeviceId(in: household.id).description
        try db.writer.read { db in
            for table in SyncSchema.stampedTables {
                let stamps = try String?.fetchAll(db, sql: "SELECT deviceId FROM \"\(table)\"")
                #expect(!stamps.isEmpty, "\(table) has a row from the phone")
                #expect(stamps.allSatisfy { $0 == stamp }, "\(table): \(stamps)")
            }
        }
    }

    @Test("A walk logged from a reminder's action carries this phone's device too")
    func reminderActionStamps() async throws {
        let db = try AppDatabase.inMemory(installId: "mias-phone")
        let household = try db.createHousehold(name: "The Lake House", people: [PersonDraft(name: "Mia", color: .coral)])
        try db.markSetupCompleted(householdId: household.id)
        try db.rememberCurrentHousehold()
        let mia = try #require(try db.snapshot().people.first).id
        var yoyo = CompanionDraft.new(species: .dog)
        yoyo.name = "Yo-Yo"
        let companionId = try db.saveCompanion(yoyo, householdId: household.id)
        let walk = try #require(try await db.writer.read(CompanionSnapshot.fetch).routines(of: companionId).first { $0.kind == .walk })
        let suite = "porchlight.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        DeviceSettings.store(me: mia, in: household.id, defaults: defaults)

        let calendar = household.calendar
        let today = DayKey(.now, calendar: calendar)
        let evening = calendar.date(byAdding: .hour, value: 18, to: today.startDate(in: calendar))!
        let confirmation = await ReminderActions.logSlot(routine: walk.id, slot: 1, day: today, database: db, defaults: defaults, now: evening)
        #expect(confirmation?.title == "Logged: evening walk")
        let stamps = try await db.writer.read { try String?.fetchAll($0, sql: "SELECT deviceId FROM careLog") }
        #expect(stamps == [db.thisDeviceId(in: household.id).description])
    }
}
