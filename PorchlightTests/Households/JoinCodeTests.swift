import Foundation
import GRDB
import Testing
import UIKit
@testable import Porchlight

/// The join code after experiment S2 (docs/design/households.md, "The join code"): closing
/// the link removes everyone who joined through it, so putting the code away never closes
/// it while someone is in through it, turning it off says who it removes first, and someone
/// removed can join again cleanly.
@Suite("The join code")
@MainActor
struct JoinCodeTests {
    private let db: AppDatabase
    private let household: Household
    private let carol: Person

    private static let owner = HouseholdParticipant(id: "_james", name: "James", userName: "_james", role: .owner, status: .joined, isCurrentUser: true)
    private static let carolByLink = HouseholdParticipant(
        id: "_carol", name: "Carol", userName: "_carol", role: .member, status: .joined, isCurrentUser: false, joinedByLink: true
    )

    init() throws {
        db = try AppDatabase.inMemory(installId: "wall")
        household = try db.createHousehold(
            name: "The Lake House", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Carol", color: .coral)]
        )
        carol = try db.snapshot().people[1]
    }

    @Test("Put away with nobody joined through it: the link closes")
    func closesWhenNobodyJoined() async throws {
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [Self.owner]), userName: "_james")
        _ = try await fake.joinCode(household)
        let closing = await JoinCodePolicy.putAway(fake, household: household)
        #expect(closing == .closeLink)
        #expect(fake.calls == ["joinCode", "endJoinCode"])
    }

    @Test("Put away after someone joined with it: the link stays open and nobody is removed")
    func staysOpenForJoiners() async throws {
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [Self.owner, Self.carolByLink]), userName: "_james")
        _ = try await fake.joinCode(household)
        let closing = await JoinCodePolicy.putAway(fake, household: household)
        #expect(closing == .keepOpen(["Carol"]))
        #expect(fake.calls == ["joinCode"], "the link is never closed under Carol")
        #expect(fake.members.participants.contains(Self.carolByLink))
    }

    @Test("Someone invited by name isn't a link joiner and never keeps the link open")
    func privateMembersDontCount() async throws {
        var mia = Self.carolByLink
        mia.id = "_mia"
        mia.userName = "_mia"
        mia.joinedByLink = false
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [Self.owner, mia]), userName: "_james")
        #expect(await JoinCodePolicy.putAway(fake, household: household) == .closeLink)
    }

    @Test("The sheet says who keeps access through the code, and turning it off says who it removes")
    func words() {
        #expect(JoinCodePolicy.keptOpenText([]) == nil)
        #expect(JoinCodePolicy.keptOpenText(["Carol"])?.hasPrefix("Carol joined with this code.") == true)
        #expect(JoinCodePolicy.turnOffQuestion(["Carol", "Ava"]).hasPrefix("Turning the code off removes Carol and Ava from the household."))
    }

    @Test("Turning the code off removes the link joiners, as CloudKit does")
    func turningOffRemoves() async throws {
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [Self.owner, Self.carolByLink]), userName: "_james")
        try await fake.endJoinCode(household)
        #expect(fake.members.participants == [Self.owner])
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

        // While she is in, the same phone is joined.
        let joined = FamilyRoster(
            snapshot: try db.snapshot(), members: HouseholdMembers(participants: [Self.owner, Self.carolByLink]),
            thisDevice: db.thisDeviceId(in: household.id), thisUserName: "_james", onSharedScreen: true
        )
        #expect(joined.rows.first { $0.person?.id == carol.id }?.state == .joined)
    }
}

/// The member's side: removed, then joining again with nothing left over in the way.
@Suite("Joining again after being removed")
@MainActor
struct RejoinTests {
    @Test("A removed phone shows it was removed, starts over, and joins again as the same person")
    func rejoins() async throws {
        let db = try AppDatabase.inMemory(installId: "carols-phone")
        let suite = "porchlight.rejoin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = DeviceSettings(defaults: defaults, idiom: .phone, model: "iPhone")
        var householdId: Household.ID?
        let fake = FakeHouseholdSharing(userName: "_carol") { _ in
            // The household as the engine brings it in: the same household both times.
            if let id = householdId, try db.writer.read({ try Household.exists($0, id: id) }) { return }
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
        let removed = try #require(try db.snapshot().removed)
        #expect(removed.id == id)

        // "OK" on the removed screen, then the code again. The household comes back with the
        // same id, as it does from iCloud.
        try db.forgetCurrentHousehold()
        #expect(try db.snapshot().removed == nil)
        let again = JoinFlow(invitation: invitation, database: db, sharing: fake, device: device, arrivalTimeout: .seconds(2))
        householdId = nil
        await again.join()
        let back = try #require(try db.snapshot().household)
        #expect(fake.calls == ["accept", "accept"])
        #expect(again.failure == nil)
        // The new household is a new id here (the fake makes a new one); the phone asks who
        // she is again rather than reusing a person from the household that went.
        #expect(again.step == .who(back.id) || again.step == .bringingIn(back.id))
        #expect(try db.snapshot().removed == nil)
    }
}
