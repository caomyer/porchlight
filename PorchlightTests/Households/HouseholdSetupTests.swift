import Foundation
import GRDB
import Testing
@testable import Porchlight

/// Starting a household (A1 on the wall, A2 on a phone) through the one shared model, so a
/// household made on a phone is the one a wall would have made; and leaving one (A6).
@Suite("Starting and leaving a household")
@MainActor
struct HouseholdSetupTests {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "porchlight.tests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// What a finished first run leaves in the database, in a comparable shape.
    private struct Made: Equatable {
        var name: String
        var people: [String]
        var colors: [PersonColor]
        var setUp: Bool
        var diaryOn: Bool?
        var diaryMeals: [String]?
    }

    private func made(_ db: AppDatabase) throws -> Made {
        try db.writer.read { db in
            let household = try #require(try Household.current(db))
            let people = try Person.active(in: household.id).fetchAll(db)
            let journal = try Journal.foodJournal(db, householdId: household.id)
            return Made(
                name: household.name, people: people.map(\.name), colors: people.map(\.color),
                setUp: household.setupCompleted, diaryOn: journal?.enabled, diaryMeals: journal?.slots
            )
        }
    }

    private func drafts(_ setup: HouseholdSetup) {
        setup.householdName = "  The Lake House "
        setup.people[0].name = "James"
        setup.addPerson()
        setup.people[1].name = "Mia"
        setup.addPerson()    // left blank, so skipped
        setup.addPerson()
        setup.people[3].name = "Ava"
    }

    @Test("Blank rows are skipped, each new row takes the next color, and the last row stays")
    func drafting() {
        let setup = HouseholdSetup()
        #expect(!setup.hasName && !setup.hasPeople)
        drafts(setup)
        #expect(setup.hasName && setup.hasPeople)
        #expect(setup.namedPeople.map(\.name) == ["James", "Mia", "Ava"])
        #expect(setup.people.map(\.color) == [.suggested(for: 0), .suggested(for: 1), .suggested(for: 2), .suggested(for: 3)])
        let single = HouseholdSetup()
        single.removePerson(at: 0)
        #expect(single.people.count == 1, "There is always someone to name")
    }

    @Test("A household started on a phone is the household the wall's first run makes")
    func sameHouseholdEitherWay() async throws {
        let (wallDefaults, wallSuite) = try defaults()
        let (phoneDefaults, phoneSuite) = try defaults()
        defer {
            wallDefaults.removePersistentDomain(forName: wallSuite)
            phoneDefaults.removePersistentDomain(forName: phoneSuite)
        }

        // The wall: a shared screen, nobody is "me".
        let wallDB = try AppDatabase.inMemory(installId: "wall")
        let wall = AppModel(database: wallDB)
        let wallDevice = DeviceSettings(defaults: wallDefaults, idiom: .pad, model: "iPad")
        let wallSetup = HouseholdSetup()
        drafts(wallSetup)
        let wallHousehold = try #require(wallSetup.create(app: wall, device: wallDevice))
        #expect(wallDevice.me(in: wallHousehold.id) == nil)
        #expect(wallDevice.role == .sharedScreen)

        // The phone: personal, and its first person is "me".
        let phoneDB = try AppDatabase.inMemory(installId: "phone")
        let phone = AppModel(database: phoneDB)
        let phoneDevice = DeviceSettings(defaults: phoneDefaults, idiom: .phone, model: "iPhone")
        let phoneSetup = HouseholdSetup()
        drafts(phoneSetup)
        let phoneHousehold = try #require(phoneSetup.create(app: phone, device: phoneDevice, owner: 0))
        let james = try #require(try await phoneDB.writer.read { try Person.active(in: phoneHousehold.id).fetchOne($0) })
        #expect(phoneDevice.me(in: phoneHousehold.id) == james.id)
        #expect(phoneDevice.role == .personal)

        // Both finish through `AppModel.finishSetup`, once each model has seen its household.
        try await waitForHousehold(wall)
        try await waitForHousehold(phone)
        #expect(phone.finishSetup())
        #expect(wall.finishSetup())

        let fromWall = try made(wallDB)
        let fromPhone = try made(phoneDB)
        #expect(fromPhone == fromWall)
        #expect(fromPhone == Made(
            name: "The Lake House", people: ["James", "Mia", "Ava"],
            colors: [.suggested(for: 0), .suggested(for: 1), .suggested(for: 3)],
            setUp: true, diaryOn: true, diaryMeals: MealSlot.defaultNames
        ))
    }

    @Test("Finishing keeps a food diary the wall's step turned off")
    func finishingKeepsTheDiaryOff() async throws {
        let db = try AppDatabase.inMemory()
        let app = AppModel(database: db)
        let setup = HouseholdSetup(householdName: "Home", people: [PersonDraft(name: "James", color: .blue)])
        let household = try #require(setup.create(app: app, device: DeviceSettings(defaults: try defaults().0)))
        let journal = try db.ensureFoodJournal(householdId: household.id, enabled: false)
        try await waitForHousehold(app)
        #expect(app.finishSetup())
        #expect(try await db.writer.read { try Journal.fetchOne($0, id: journal.id) }?.enabled == false)
    }

    @Test("A household that can't be made says why, and nothing is created")
    func invalid() throws {
        let db = try AppDatabase.inMemory()
        let app = AppModel(database: db)
        let setup = HouseholdSetup(householdName: "   ", people: [PersonDraft(name: "James", color: .blue)])
        #expect(setup.create(app: app, device: DeviceSettings(defaults: try defaults().0), owner: 0) == nil)
        #expect(app.lastError != nil)
        #expect(try db.writer.read { try Household.fetchCount($0) } == 0)
    }

    // MARK: Leaving (A6)

    @Test("A member leaves: off the share, the household goes from this device, and it isn't shown as removed")
    func memberLeaves() async throws {
        let db = try AppDatabase.inMemory(installId: "mias-phone")
        let household = try db.createHousehold(name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)])
        try db.markSetupCompleted(householdId: household.id)
        try db.rememberCurrentHousehold()
        let app = AppModel(database: db)
        let james = HouseholdParticipant(id: "_james", name: "James", userName: "_james", role: .owner, status: .joined, isCurrentUser: false)
        let mia = HouseholdParticipant(id: "_mia", name: "Mia", userName: "_mia", role: .member, status: .joined, isCurrentUser: true)
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [james, mia]), userName: "_mia")
        fake.onLeave = { left in
            try db.writer.write { db in _ = try Household.deleteOne(db, id: left.id) }
        }
        let sharing = HouseholdSharingModel(service: fake, database: db)
        await sharing.refresh(household)
        #expect(!sharing.members.isOwner)

        // Offline first: nothing changes, and it says so.
        fake.leaveFailures = 1
        await #expect(throws: (any Error).self) { try await sharing.leave(household, app: app) }
        #expect(try await db.writer.read { try Household.exists($0, id: household.id) })

        try await sharing.leave(household, app: app)
        #expect(fake.calls == ["leave", "leave"])
        #expect(try await db.writer.read { try Household.exists($0, id: household.id) } == false)
        #expect(sharing.members == .none)
        #expect(try db.snapshot().removed == nil, "Leaving isn't someone removing you")
    }

    @Test("The owner can't leave their own household")
    func ownerCantLeave() async throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        let app = AppModel(database: db)
        let fake = FakeHouseholdSharing(userName: "_james")
        let sharing = HouseholdSharingModel(service: fake, database: db)
        await #expect(throws: (any Error).self) { try await sharing.leave(household, app: app) }
        #expect(try await db.writer.read { try Household.exists($0, id: household.id) })
    }

    /// Waits for the model's observation to deliver the household it just created.
    private func waitForHousehold(_ app: AppModel) async throws {
        let deadline = Date.now.addingTimeInterval(5)
        while app.household == nil && Date.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(app.household != nil)
    }
}

/// What the household takes up, summed from its rows (E4).
@Suite("Household storage")
struct HouseholdStorageTests {
    @Test("Photos, Pencil pages and yours come from the rows; nothing is made up")
    func sums() throws {
        let db = try AppDatabase.inMemory(installId: "mias-phone")
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "Mia", color: .coral)])
        try db.rememberCurrentHousehold()
        let journal = try db.ensureFoodJournal(householdId: household.id)
        let mia = try #require(try db.snapshot().people.first).id
        let empty = try db.storage(of: household.id, mine: [])
        #expect(empty.photos == 0 && empty.pages == 0 && empty.mine == 0 && empty.lastMonth == 0)
        #expect(StorageWords.size(0) == "nothing yet")

        let photo = NewMealPhoto(id: .new(), image: Data(count: 50_000), thumbnail: Data(count: 4_000), crop: nil)
        let meal = MealDraft(day: DayKey(.now, calendar: household.calendar), slot: "Lunch", eaterIds: [mia], eatenAt: .now)
        try db.addMeal(meal, journalId: journal.id, photos: [photo])
        try db.writer.write { db in
            try JournalPage(journalId: journal.id, day: DayKey(.now, calendar: household.calendar), drawing: Data(count: 7_000), updatedAt: .now).insert(db)
        }

        let thisPhone = db.thisDeviceId(in: household.id)
        let storage = try db.storage(of: household.id, mine: [thisPhone])
        #expect(storage.photos == 54_000)
        #expect(storage.pages == 7_000)
        #expect(storage.mine == 54_000, "Added from this phone")
        #expect(storage.lastMonth == 54_000)
        #expect(storage.other > 0, "The rest of what the database holds")
        #expect(try db.storage(of: household.id, mine: [.derived("someone-else")]).mine == 0)
        let old = try db.storage(of: household.id, mine: [], now: .now.addingTimeInterval(60 * 24 * 60 * 60))
        #expect(old.lastMonth == 0, "Nothing added in the 30 days before then")
        #expect(StorageWords.breakdown(storage).hasPrefix(StorageWords.size(storage.total) + " · Photos"))
    }
}
