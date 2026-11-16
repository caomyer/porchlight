import Foundation
import GRDB
import Testing
@testable import Porchlight

/// Device rows, where rows came from, and which household a device shows
/// (docs/design/households.md, "The model").
@Suite("Households: devices and the current household")
struct HouseholdDataTests {
    private let db: AppDatabase
    private let household: Household
    private let james: Person.ID
    private let mia: Person.ID

    init() throws {
        db = try AppDatabase.inMemory(installId: "install-a")
        household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        let people = try db.snapshot().people
        james = people[0].id
        mia = people[1].id
    }

    private func phone(_ person: Person.ID?, user: String? = "_mia", name: String = "Mia's iPhone") -> ThisDevice {
        ThisDevice(name: name, role: .personal, model: "iPhone", personId: person, userName: user)
    }

    private func devices() throws -> [Device] {
        try db.writer.read { try Device.order(Column("createdAt"), Column("id")).fetchAll($0) }
    }

    // MARK: Device rows

    @Test("An install has one row per household, however often it writes it")
    func oneRowPerInstall() throws {
        try db.saveThisDevice(phone(mia), in: household.id)
        try db.saveThisDevice(phone(mia), in: household.id)
        try db.saveThisDevice(phone(mia, name: "Mia's new name"), in: household.id)
        let rows = try devices()
        #expect(rows.count == 1)
        #expect(rows[0].id == Device.id(householdId: household.id, install: "install-a"))
        #expect(rows[0].name == "Mia's new name")
        #expect(rows[0].personId == mia && rows[0].userName == "_mia" && rows[0].model == "iPhone")
    }

    @Test("Another install, or another household, is another row")
    func otherInstallsAndHouseholds() throws {
        try db.saveThisDevice(phone(mia), in: household.id)
        let other = try AppDatabase(db.writer, installId: "install-b")
        try other.saveThisDevice(phone(james, user: "_james", name: "James's iPhone"), in: household.id)
        let second = try db.createHousehold(name: "Grandma Rosa's", people: [PersonDraft(name: "Rosa", color: .sage)])
        try db.saveThisDevice(phone(nil), in: second.id)
        #expect(try devices().count == 3)
        #expect(Set(try devices().map(\.id)).count == 3)
    }

    @Test("A role, person or account change updates the row; a shared screen credits nobody")
    func updatedOnChange() throws {
        try db.saveThisDevice(phone(mia), in: household.id)
        try db.saveThisDevice(ThisDevice(name: "Hallway iPad", role: .sharedScreen, model: "iPad", personId: mia, userName: nil), in: household.id)
        let row = try #require(try devices().first)
        #expect(row.role == .sharedScreen && row.personId == nil && row.owner == nil)
        #expect(row.userName == "_mia", "an account that can't be read offline keeps the known one")
    }

    @Test("Seen moves at most once a day, so an unchanged device writes nothing more")
    func seenOncePerDay() throws {
        let calendar = household.calendar
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 8))!
        try db.saveThisDevice(phone(mia), in: household.id, now: morning)
        try db.saveThisDevice(phone(mia), in: household.id, now: morning.addingTimeInterval(3600))
        #expect(try devices()[0].seenAt == morning)
        let tomorrow = morning.addingTimeInterval(24 * 3600)
        try db.saveThisDevice(phone(mia), in: household.id, now: tomorrow)
        #expect(try devices()[0].seenAt == tomorrow)
        #expect(try devices()[0].createdAt == morning)
    }

    @Test("Removing someone takes their devices, never their person")
    func removeDevices() throws {
        try db.saveThisDevice(phone(mia), in: household.id)
        try db.removeDevices(ofUser: "_mia", in: household.id)
        #expect(try devices().isEmpty)
        #expect(try db.snapshot().people.map(\.id) == [james, mia])
    }

    @Test("A role written by a newer version reads as a shared screen")
    func unknownRole() throws {
        try db.saveThisDevice(phone(mia), in: household.id)
        try db.writer.write { try $0.execute(sql: "UPDATE device SET role = 'kiosk'") }
        #expect(try devices()[0].role == .sharedScreen)
    }

    // MARK: Where a row came from

    @Test("Every write path stamps this device's row on what it adds")
    func everyWritePathStamps() throws {
        try db.rememberCurrentHousehold()
        let stamp = db.thisDeviceId(in: household.id)
        var yoyo = CompanionDraft.new(species: .dog)
        yoyo.name = "Yo-Yo"
        let companionId = try db.saveCompanion(yoyo, householdId: household.id)
        let walk = try #require(try db.writer.read(CompanionSnapshot.fetch).routines(of: companionId).first { $0.kind == .walk })
        let calendar = household.calendar
        let today = DayKey(.now, calendar: calendar)
        // Fixed times, so the morning log never fills the evening slot whatever the hour.
        let morning = calendar.date(byAdding: .hour, value: 8, to: today.startDate(in: calendar))!
        let evening = calendar.date(byAdding: .hour, value: 18, to: today.startDate(in: calendar))!
        let draft = CareLogDraft(people: [james], occurredAt: morning, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        let log = try db.logCare(routineId: walk.id, draft, now: morning)
        var evenings = draft
        evenings.occurredAt = evening
        let slotted = try db.logCare(routineId: walk.id, slot: 1, on: today, evenings, now: evening)

        let chore = try db.saveChore(
            ChoreDraft(title: "Dishes", emoji: "🍽️", ownerId: james, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 1),
            householdId: household.id
        )
        let anyone = try db.saveChore(
            ChoreDraft(title: "Vacuum", emoji: "🧹", ownerId: nil, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 1),
            householdId: household.id
        )
        let shared = try db.saveChore(
            ChoreDraft(title: "Sheets", emoji: nil, ownerId: nil, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 1),
            householdId: household.id
        )
        try db.toggleChore(id: chore.id, day: today, personId: nil)
        _ = try db.completeChore(id: anyone.id, day: today, personId: mia)
        try db.creditChore(id: shared.id, day: today, personId: mia)
        let reward = try db.saveReward(RewardDraft(title: "Zoo", emoji: nil, targetStars: 5, ownerId: nil), householdId: household.id, today: today)
        let cashIn = try db.cashInReward(id: reward.id, stars: 5, day: today)
        let list = try db.createList(title: "Groceries", kind: .grocery, householdId: household.id)
        let item = try db.addListItem(title: "Basil", to: list.id, addedBy: james)
        let journal = try db.ensureFoodJournal(householdId: household.id)
        let meal = try db.addMeal(
            MealDraft(day: today, slot: MealSlot.defaultNames[1], source: .home, title: "Pho", emoji: nil, eaterIds: [mia], eatenAt: .now, place: nil),
            journalId: journal.id
        )

        let stamped = try db.writer.read { db in
            try SyncSchema.stampedTables.flatMap { table in
                try String.fetchAll(db, sql: "SELECT ifnull(deviceId, 'none') FROM \"\(table)\"")
            }
        }
        // Two walks, three chores, a cash-in, an item and a meal.
        #expect(stamped.count == 8)
        #expect(Set(stamped) == [stamp.description])
        if case let .logged(slottedLog) = slotted { #expect(slottedLog.deviceId == stamp) } else { Issue.record("The open slot should log") }
        #expect(log.deviceId == stamp && cashIn.deviceId == stamp && item.deviceId == stamp && meal.deviceId == stamp)
    }

    @Test("The tag shows only for someone's own device")
    func tags() throws {
        try db.saveThisDevice(phone(mia), in: household.id)
        let wall = try AppDatabase(db.writer, installId: "wall")
        try wall.saveThisDevice(ThisDevice(name: "Hallway iPad", role: .sharedScreen, model: "iPad", personId: nil, userName: "_james"), in: household.id)
        let personalIPad = try AppDatabase(db.writer, installId: "ipad")
        try personalIPad.saveThisDevice(ThisDevice(name: "James's iPad", role: .personal, model: "iPad", personId: james, userName: "_james"), in: household.id)
        let snapshot = try db.snapshot()
        #expect(snapshot.tag(for: db.thisDeviceId(in: household.id)) == "from Mia's phone")
        #expect(snapshot.tag(for: personalIPad.thisDeviceId(in: household.id)) == "from James's iPad")
        #expect(snapshot.tag(for: wall.thisDeviceId(in: household.id)) == nil)
        #expect(snapshot.tag(for: nil) == nil, "rows from before devices show no tag")
        #expect(snapshot.tag(for: .new()) == nil, "a device that hasn't arrived yet shows no tag")
    }

    @Test("The newest change from another device is what the sync line names")
    func lastChange() throws {
        let other = try AppDatabase(db.writer, installId: "mias-phone")
        let list = try db.createList(title: "Groceries", kind: .grocery, householdId: household.id)
        _ = try db.addListItem(title: "Basil", to: list.id, addedBy: james, now: .now.addingTimeInterval(-60))
        #expect(try db.writer.read { try LastChange.fetch($0, excluding: db.thisDeviceId(in: household.id)) } == nil)
        let at = Date.now.addingTimeInterval(-120)
        _ = try other.addListItem(title: "Limes", to: list.id, addedBy: mia, now: at)
        let change = try db.writer.read { try LastChange.fetch($0, excluding: db.thisDeviceId(in: household.id)) }
        #expect(change?.deviceId == other.thisDeviceId(in: household.id))
        #expect(abs((change?.at ?? .distantPast).timeIntervalSince(at)) < 0.01)
    }

    // MARK: The current household

    @Test("The first household becomes current and stays current when others arrive")
    func firstBecomesCurrent() throws {
        try db.rememberCurrentHousehold()
        let later = try db.createHousehold(name: "Grandma Rosa's", people: [PersonDraft(name: "Rosa", color: .sage)], now: .now.addingTimeInterval(-3600))
        try db.rememberCurrentHousehold()
        #expect(try db.snapshot().household?.id == household.id, "an older household arriving doesn't take over")
        try db.chooseHousehold(later.id)
        #expect(try db.snapshot().household?.id == later.id, "the newest accepted invite becomes current")
    }

    @Test("The current household survives a relaunch")
    func survivesRelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("households-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var chosen: Household.ID?
        do {
            let disk = try AppDatabase.openOnDisk(folder: folder)
            _ = try disk.createHousehold(name: "Older", people: [PersonDraft(name: "A", color: .blue)], now: .now.addingTimeInterval(-3600))
            let newer = try disk.createHousehold(name: "Newer", people: [PersonDraft(name: "B", color: .blue)])
            try disk.chooseHousehold(newer.id)
            chosen = newer.id
            try disk.writer.close()
        }
        let relaunched = try AppDatabase.openOnDisk(folder: folder)
        #expect(try relaunched.snapshot().household?.id == chosen)
        try relaunched.writer.close()
    }

    @Test("A household that leaves shows as removed until seen, then the next one is current")
    func removedThenFallsBack() throws {
        let rosas = try db.createHousehold(name: "Grandma Rosa's", people: [PersonDraft(name: "Rosa", color: .sage)])
        try db.chooseHousehold(rosas.id)
        try db.rememberOwner("Rosa", of: rosas.id)
        // The owner stops sharing: sync deletes the household on this device.
        _ = try db.writer.write { try Household.deleteOne($0, id: rosas.id) }
        try db.rememberCurrentHousehold()
        let snapshot = try db.snapshot()
        #expect(snapshot.removed == RemovedHousehold(id: rosas.id, name: "Grandma Rosa's", ownerName: "Rosa"))
        #expect(snapshot.household?.id == household.id, "the other household is still there to fall back to")
        try db.forgetCurrentHousehold()
        try db.rememberCurrentHousehold()
        #expect(try db.snapshot().removed == nil)
        #expect(try db.snapshot().household?.id == household.id)
    }

    @Test("A household this device removes itself is never shown as removed")
    func removedHere() throws {
        try db.rememberCurrentHousehold()
        try db.forgetCurrentHousehold()
        _ = try db.writer.write { try Household.deleteAll($0) }
        try db.rememberCurrentHousehold()
        #expect(try db.snapshot().removed == nil)
        #expect(try db.snapshot().household == nil)
    }
}
