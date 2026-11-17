#if DEBUG
import Foundation
import GRDB

/// The fake sharing for screenshots and UI tests, chosen by launch arguments. Only on
/// sample data (`-sampleHousehold` or `-resetData`), which never syncs:
///
///   -debugSharing invited   this device is James's, the owner; Mia is invited and Ava has no phone
///   -debugSharing joined    the same, but Mia has joined from her iPhone
///   -debugSharing member    this device is Mia's; James owns the household from his iPhone
///   -debugJoin preview      with -resetData, an invite to The Lake House opened the app
///   -debugJoin failing      the same, but the first try at joining fails as if offline
///   -debugJoin known        the same, and this iCloud user already has a phone in the household
enum DebugSharing {
    /// James's and Mia's iCloud users in the sample household.
    static let james = "_james"
    static let mia = "_mia"

    @MainActor
    static func fake(_ arguments: [String], database: AppDatabase) -> FakeHouseholdSharing? {
        guard AppFiles.isSandboxed else { return nil }
        let defaults = UserDefaults.standard
        if let state = defaults.string(forKey: "debugSharing") {
            return sharing(state, database: database)
        }
        if let join = defaults.string(forKey: "debugJoin") {
            return joining(join, database: database)
        }
        return nil
    }

    @MainActor
    private static func sharing(_ state: String, database: AppDatabase) -> FakeHouseholdSharing {
        let isMember = state == "member"
        let miaJoined = state == "joined" || isMember
        // As a member, this device is Mia's phone, and writes its own row.
        try? seedFamily(database, miaHasPhone: state == "joined")
        var participants = [
            HouseholdParticipant(id: james, name: "James", userName: james, role: .owner, status: .joined, isCurrentUser: !isMember),
        ]
        participants.append(miaJoined
            ? HouseholdParticipant(id: mia, name: "Mia", userName: mia, role: .member, status: .joined, isCurrentUser: isMember)
            : HouseholdParticipant(id: "mia@example.com", name: "Mia", userName: nil, role: .member, status: .invited, isCurrentUser: false))
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: participants), userName: isMember ? mia : james)
        // Leaving takes the household off this device, as the engine does when its shared zone goes.
        fake.onLeave = { household in
            try database.writer.write { db in _ = try Household.deleteOne(db, id: household.id) }
        }
        return fake
    }

    @MainActor
    private static func joining(_ variant: String, database: AppDatabase) -> FakeHouseholdSharing {
        let fake = FakeHouseholdSharing(userName: mia) { _ in
            let household = try DebugLaunch.seedSampleHousehold(database)
            let people = try database.snapshot().people
            try database.writer.write { db in
                try phone(of: "James", user: james, people: people, in: household.id).save(db)
                if variant == "known" {
                    try phone(of: "Mia", user: mia, people: people, in: household.id).save(db)
                }
            }
        }
        fake.members = HouseholdMembers(participants: [
            HouseholdParticipant(id: james, name: "James", userName: james, role: .owner, status: .joined, isCurrentUser: false),
        ])
        if variant == "failing" { fake.acceptFailures = 1 }
        ShareInbox.shared.invitation = HouseholdInvitation(householdId: nil, householdName: "The Lake House", ownerName: "James")
        return fake
    }

    /// Ava, who has no phone, and the phones of whoever joined.
    private static func seedFamily(_ database: AppDatabase, miaHasPhone: Bool) throws {
        guard let household = try database.snapshot().household else { return }
        try database.addPerson(PersonDraft(name: "Ava", color: .ochre), to: household.id)
        let people = try database.snapshot().people
        try database.writer.write { db in
            try phone(of: "James", user: james, people: people, in: household.id).save(db)
            if miaHasPhone {
                try phone(of: "Mia", user: mia, people: people, in: household.id).save(db)
            }
        }
    }

    private static func phone(of name: String, user: String, people: [Person], in householdId: Household.ID) -> Device {
        let now = Date.now
        return Device(
            id: Device.id(householdId: householdId, install: "debug-\(user)"), householdId: householdId,
            name: "\(name)'s iPhone", role: .personal, model: "iPhone",
            personId: people.first { $0.name == name }?.id, userName: user, createdAt: now, seenAt: now
        )
    }
}
#endif
