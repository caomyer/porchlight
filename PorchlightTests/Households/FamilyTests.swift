import Foundation
import GRDB
import Testing
@testable import Porchlight

/// Family & devices with the fake sharing (journeys A3, D2, A6): every state a person can
/// be in, and inviting and removing calling through.
@Suite("Family & devices")
@MainActor
struct FamilyTests {
    private let db: AppDatabase
    private let household: Household
    private let james: Person
    private let mia: Person
    private let ava: Person

    init() throws {
        db = try AppDatabase.inMemory(installId: "wall")
        household = try db.createHousehold(
            name: "The Lake House",
            people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral), PersonDraft(name: "Ava", color: .ochre)]
        )
        let people = try db.snapshot().people
        (james, mia, ava) = (people[0], people[1], people[2])
        try db.saveThisDevice(ThisDevice(name: "Hallway iPad", role: .sharedScreen, model: "iPad", personId: nil, userName: "_james"), in: household.id)
    }

    private func phone(_ person: Person, user: String) throws {
        let install = try AppDatabase(db.writer, installId: "\(user)-phone")
        try install.saveThisDevice(ThisDevice(name: "\(person.name)'s iPhone", role: .personal, model: "iPhone", personId: person.id, userName: user), in: household.id)
    }

    private static let owner = HouseholdParticipant(id: "_james", name: "James", userName: "_james", role: .owner, status: .joined, isCurrentUser: true)

    private func roster(_ members: HouseholdMembers, onSharedScreen: Bool = true) throws -> FamilyRoster {
        FamilyRoster(
            snapshot: try db.snapshot(), members: members, thisDevice: db.thisDeviceId(in: household.id),
            thisUserName: "_james", onSharedScreen: onSharedScreen
        )
    }

    @Test("Owner, invited, no phone and an invite that names nobody each show as such")
    func everyState() throws {
        try phone(james, user: "_james")
        let members = HouseholdMembers(participants: [
            Self.owner,
            HouseholdParticipant(id: "mia@example.com", name: "Mia Cao", userName: nil, role: .member, status: .invited, isCurrentUser: false),
            HouseholdParticipant(id: "rosa@example.com", name: "Rosa", userName: nil, role: .member, status: .invited, isCurrentUser: false),
        ])
        let roster = try roster(members)
        let rows = Dictionary(uniqueKeysWithValues: roster.rows.map { ($0.title, $0) })
        #expect(rows["James"]?.state == .joined && rows["James"]?.isOwner == true)
        #expect(rows["James"]?.detail == "Owner · James's iPhone · used today")
        #expect(rows["Mia"]?.state == .invited && rows["Mia"]?.detail == "Invited, hasn't joined yet")
        #expect(rows["Ava"]?.state == .noPhone && rows["Ava"]?.detail == "Pitches in on this screen")
        #expect(rows["Rosa"]?.person == nil && rows["Rosa"]?.state == .invited)
        #expect(roster.rows.allSatisfy { $0.removable == nil }, "nobody but the owner joined, and the owner can't remove themselves")
        #expect(roster.summary == "3 people · 1 with the app")
        #expect(roster.sharedScreens.isEmpty, "this iPad is listed on its own")
        #expect(try self.roster(members, onSharedScreen: false).rows.first { $0.title == "Ava" }?.detail == "No phone yet")
    }

    @Test("The owner can remove someone who joined; a member can't")
    func removable() throws {
        try phone(james, user: "_james")
        try phone(mia, user: "_mia")
        let miaJoined = HouseholdParticipant(id: "_mia", name: "Mia", userName: "_mia", role: .member, status: .joined, isCurrentUser: false)
        let asOwner = try roster(HouseholdMembers(participants: [Self.owner, miaJoined]))
        #expect(asOwner.rows.first { $0.title == "Mia" }?.removable == miaJoined)

        var ownerElsewhere = Self.owner
        ownerElsewhere.isCurrentUser = false
        var me = miaJoined
        me.isCurrentUser = true
        let asMember = try roster(HouseholdMembers(participants: [ownerElsewhere, me]))
        #expect(asMember.rows.allSatisfy { $0.removable == nil })
    }

    @Test("Before anyone is invited, the household is this account's own")
    func noShareYet() throws {
        try phone(james, user: "_james")
        let roster = try roster(.none)
        #expect(HouseholdMembers.none.isOwner)
        #expect(roster.rows.first { $0.title == "James" }?.isOwner == true)
    }

    @Test("Other shared screens are listed; people's own devices aren't")
    func sharedScreens() throws {
        let kitchen = try AppDatabase(db.writer, installId: "kitchen")
        try kitchen.saveThisDevice(ThisDevice(name: "Kitchen iPad", role: .sharedScreen, model: "iPad", personId: nil, userName: "_james"), in: household.id)
        try phone(mia, user: "_mia")
        #expect(try roster(.none).sharedScreens.map(\.name) == ["Kitchen iPad"])
    }

    @Test("Inviting and the join code call through; removing takes the share and the devices, never the person")
    func callsThrough() async throws {
        try phone(mia, user: "_mia")
        let miaJoined = HouseholdParticipant(id: "_mia", name: "Mia", userName: "_mia", role: .member, status: .joined, isCurrentUser: false)
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [Self.owner, miaJoined]), userName: "_james")
        let model = HouseholdSharingModel(service: fake, database: db)
        await model.refresh(household)
        #expect(model.members.participants.count == 2)

        _ = try await fake.invite(household)
        _ = try await fake.joinCode(household)
        try await fake.endJoinCode(household)
        try await model.remove(miaJoined, from: household)
        #expect(fake.calls == ["invite", "joinCode", "endJoinCode", "remove _mia"])
        #expect(model.members.participants == [Self.owner])
        let snapshot = try db.snapshot()
        #expect(snapshot.devices(of: mia.id).isEmpty)
        #expect(snapshot.people.contains { $0.id == mia.id })
    }

    @Test("The owner's name is their person's, through the iCloud user their devices carry")
    func ownerName() async throws {
        try phone(james, user: "_james")
        var owner = Self.owner
        owner.name = "Jim"
        owner.isCurrentUser = false
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [owner]), userName: "_mia")
        let model = HouseholdSharingModel(service: fake, database: db)
        await model.refresh(household)
        let snapshot = try db.snapshot()
        #expect(model.ownerName(people: snapshot.everyone, devices: snapshot.devices) == "James")
        let kept = try await db.writer.read { [household] in try DeviceState.value(DeviceState.ownerKey(household.id), $0) }
        #expect(kept == "Jim", "kept for the removed screen")
    }
}
