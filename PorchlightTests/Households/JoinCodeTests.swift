import Foundation
import GRDB
import Testing
import UIKit
@testable import Porchlight

/// The join code as one private seat (docs/design/households.md, "The join code"): made for
/// one showing, taken by the first person who scans it, removed when put away untaken, and
/// never touching anyone already in. The share's public link stays closed.
@Suite("The join code")
@MainActor
struct JoinCodeTests {
    private let db: AppDatabase
    private let household: Household
    private let carol: Person

    private static let owner = HouseholdParticipant(id: "_james", name: "James", userName: "_james", role: .owner, status: .joined, isCurrentUser: true)
    private static let mia = HouseholdParticipant(id: "_mia", name: "Mia", userName: "_mia", role: .member, status: .joined, isCurrentUser: false)
    private static let invited = HouseholdParticipant(id: "rosa@example.com", name: "Rosa", userName: nil, role: .member, status: .invited, isCurrentUser: false)

    init() throws {
        db = try AppDatabase.inMemory(installId: "james-phone")
        household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Carol", color: .coral)]
        )
        carol = try db.snapshot().people[1]
    }

    private func fake() -> FakeHouseholdSharing {
        FakeHouseholdSharing(members: HouseholdMembers(participants: [Self.owner, Self.mia, Self.invited]), userName: "_james")
    }

    @Test("A seat is made for the showing, waits, and is taken by the first person who scans it")
    func seatClaimed() async throws {
        let fake = fake()
        let seat = try await fake.openSeat(household)
        #expect(try await fake.seatState(seat, in: household) == .waiting)
        fake.claim(seat, as: "_carol", name: "Carol")
        #expect(try await fake.seatState(seat, in: household) == .claimed(userName: "_carol"))
        // Putting the code away after it was taken keeps Carol.
        try await fake.closeSeat(seat, in: household)
        #expect(fake.members.participants.contains { $0.userName == "_carol" && $0.status == .joined })
        #expect(fake.members.participants.contains(Self.mia))
        #expect(fake.members.participants.contains(Self.invited))
    }

    @Test("A seat nobody took is removed when the code is put away, and nobody else is touched")
    func seatRemovedUnclaimed() async throws {
        let fake = fake()
        let seat = try await fake.openSeat(household)
        try await fake.closeSeat(seat, in: household)
        #expect(try await fake.seatState(seat, in: household) == .gone)
        #expect(fake.members.participants == [Self.owner, Self.mia, Self.invited])
        #expect(fake.calls == ["openSeat", "closeSeat"])
    }

    @Test("Each showing is its own seat")
    func oneSeatPerShowing() async throws {
        let fake = fake()
        let first = try await fake.openSeat(household)
        let second = try await fake.openSeat(household)
        #expect(first != second)
        fake.claim(first, as: "_carol", name: "Carol")
        try await fake.closeSeat(second, in: household)
        #expect(try await fake.seatState(first, in: household) == .claimed(userName: "_carol"))
        #expect(try await fake.seatState(second, in: household) == .gone)
    }

    @Test("Only the owner on iOS 18 shows a code; every other device says where to")
    func availability() {
        #expect(JoinCodeAvailability.decide(isOwner: true, supportsSeats: true, ownerName: "James") == .available)
        #expect(JoinCodeAvailability.decide(isOwner: true, supportsSeats: false, ownerName: "James")
            == .elsewhere("To show a join code, open Porchlight on James's iPhone: You, Invite someone, Show a code."))
        #expect(JoinCodeAvailability.decide(isOwner: false, supportsSeats: true, ownerName: "James")
            == .elsewhere("Only James can add people to the household. To show a join code, open Porchlight on James's iPhone: You, Invite someone, Show a code."))
    }

    @Test("A public link left open with nobody through it is closed at once")
    func safetyNetClosesEmptyLink() async throws {
        let fake = fake()
        fake.isLinkOpen = true
        let model = HouseholdSharingModel(service: fake, database: db)
        await model.refresh(household)
        #expect(fake.calls == ["closePublicLink"])
        #expect(model.linkJoiners.isEmpty)
        #expect(model.members.participants == [Self.owner, Self.mia, Self.invited])
    }

    @Test("A public link with someone through it stays until the owner chooses, naming who it removes")
    func safetyNetAsksFirst() async throws {
        var carolByLink = Self.mia
        carolByLink.id = "_carol"
        carolByLink.userName = "_carol"
        carolByLink.name = "Carol"
        carolByLink.joinedByLink = true
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [Self.owner, Self.mia, carolByLink]), userName: "_james")
        fake.isLinkOpen = true
        let model = HouseholdSharingModel(service: fake, database: db)
        await model.refresh(household)
        #expect(fake.calls.isEmpty, "nothing is closed by itself")
        #expect(model.linkJoiners.map(\.name) == ["Carol"])

        try await model.closePublicLink(household)
        #expect(fake.calls == ["closePublicLink"])
        #expect(model.linkJoiners.isEmpty)
        #expect(model.members.participants == [Self.owner, Self.mia], "only the link joiner goes")
    }

    @Test("A member's device never checks or closes the link")
    func membersLeaveTheLinkAlone() async throws {
        var me = Self.mia
        me.isCurrentUser = true
        var owner = Self.owner
        owner.isCurrentUser = false
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [owner, me]), userName: "_mia")
        fake.isLinkOpen = true
        let model = HouseholdSharingModel(service: fake, database: db)
        await model.refresh(household)
        #expect(fake.calls.isEmpty)
    }

    @Test("A phone whose iCloud user was removed shows as not joined on the owner's side")
    func removedPhoneIsNotJoined() throws {
        let install = try AppDatabase(db.writer, installId: "carol-phone")
        try install.saveThisDevice(ThisDevice(name: "Carol's iPhone", role: .personal, model: "iPhone", personId: carol.id, userName: "_carol"), in: household.id)
        let members = HouseholdMembers(participants: [Self.owner])
        let roster = FamilyRoster(snapshot: try db.snapshot(), members: members, thisDevice: db.thisDeviceId(in: household.id), thisUserName: "_james", onSharedScreen: true)
        let row = try #require(roster.rows.first { $0.person?.id == carol.id })
        #expect(row.state == .noPhone)
        #expect(row.detail == "Not joined: Carol's iPhone no longer has access")
        #expect(row.removable == nil)

        var carolIn = Self.mia
        carolIn.id = "_carol"
        carolIn.userName = "_carol"
        let joined = FamilyRoster(
            snapshot: try db.snapshot(), members: HouseholdMembers(participants: [Self.owner, carolIn]),
            thisDevice: db.thisDeviceId(in: household.id), thisUserName: "_james", onSharedScreen: true
        )
        #expect(joined.rows.first { $0.person?.id == carol.id }?.state == .joined)
    }
}

/// The member's side: removed, then joining again with nothing left over in the way.
@Suite("Joining again after being removed")
@MainActor
struct RejoinTests {
    @Test("A removed phone shows it was removed, starts over, and joins again")
    func rejoins() async throws {
        let db = try AppDatabase.inMemory(installId: "carols-phone")
        let suite = "porchlight.rejoin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = DeviceSettings(defaults: defaults, idiom: .phone, model: "iPhone")
        var householdId: Household.ID?
        let fake = FakeHouseholdSharing(userName: "_carol") { _ in
            let household = try db.createHousehold(
                name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Carol", color: .coral)]
            )
            try db.markSetupCompleted(householdId: household.id)
            householdId = household.id
        }
        let invitation = HouseholdInvitation(householdId: nil, householdName: "The Lake House", ownerName: "James")

        let first = JoinFlow(invitation: invitation, database: db, sharing: fake, device: device, arrivalTimeout: .seconds(2))
        await first.join()
        let id = try #require(householdId)
        let carol = try #require(try db.snapshot().people.first { $0.name == "Carol" })
        first.pick(carol.id)
        try db.saveThisDevice(ThisDevice(name: "Carol's iPhone", role: .personal, model: "iPhone", personId: carol.id, userName: "_carol"), in: id)

        // Removed: the engine takes the household's rows off this phone.
        try await db.writer.write { db in _ = try Household.deleteAll(db) }
        #expect(try db.snapshot().removed?.id == id)

        // "OK" on the removed screen, then an invite or a code again.
        try db.forgetCurrentHousehold()
        #expect(try db.snapshot().removed == nil)
        let again = JoinFlow(invitation: invitation, database: db, sharing: fake, device: device, arrivalTimeout: .seconds(2))
        await again.join()
        let back = try #require(try db.snapshot().household)
        #expect(fake.calls == ["accept", "accept"])
        #expect(again.failure == nil)
        #expect(again.step == .who(back.id) || again.step == .bringingIn(back.id))
        #expect(try db.snapshot().removed == nil)
    }
}
