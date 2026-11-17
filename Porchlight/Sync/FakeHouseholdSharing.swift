#if DEBUG
import Foundation

/// Sharing without iCloud, for unit tests, UI tests and screenshots: it keeps a list of
/// participants, records every call, and makes an accepted household appear through
/// `onAccept`, as the engine's first fetch would.
@MainActor
final class FakeHouseholdSharing: HouseholdSharing {
    var members: HouseholdMembers
    var unavailableReason: String?
    var userName: String?
    /// How many times accepting fails, as offline, before it works.
    var acceptFailures = 0
    /// Puts the accepted household in the database.
    var onAccept: (HouseholdInvitation) throws -> Void
    /// Takes a household that was left out of the database, as the engine does when the
    /// shared zone goes.
    var onLeave: (Household) throws -> Void = { _ in }
    /// How many times leaving fails, as offline, before it works.
    var leaveFailures = 0
    var joinCodeURL = URL(string: "https://www.icloud.com/share/0PorchlightSampleHousehold#The_Lake_House")!
    /// Every call, in order: "invite", "joinCode", "endJoinCode", "accept", "remove <id>".
    private(set) var calls: [String] = []

    init(members: HouseholdMembers = .none, userName: String? = nil, onAccept: @escaping (HouseholdInvitation) throws -> Void = { _ in }) {
        self.members = members
        self.userName = userName
        self.onAccept = onAccept
    }

    struct Offline: LocalizedError {
        var errorDescription: String? { "The Internet connection appears to be offline." }
    }

    func currentUserName() async -> String? { userName }

    func participants(of household: Household) async throws -> HouseholdMembers { members }

    func invite(_ household: Household) async throws -> HouseholdInvite {
        calls.append("invite")
        return .standIn(householdName: household.name)
    }

    func joinCode(_ household: Household) async throws -> URL {
        calls.append("joinCode")
        return joinCodeURL
    }

    func linkJoiners(of household: Household) async throws -> [HouseholdParticipant] {
        members.participants.filter { $0.joinedByLink && $0.status == .joined }
    }

    /// As CloudKit does: closing the link removes everyone who joined through it.
    func endJoinCode(_ household: Household) async throws {
        calls.append("endJoinCode")
        members.participants.removeAll { $0.joinedByLink }
    }

    func accept(_ invitation: HouseholdInvitation) async throws {
        calls.append("accept")
        if acceptFailures > 0 {
            acceptFailures -= 1
            throw Offline()
        }
        try onAccept(invitation)
    }

    func remove(_ participant: HouseholdParticipant, from household: Household) async throws {
        calls.append("remove \(participant.id)")
        members.participants.removeAll { $0.id == participant.id }
    }

    func leave(_ household: Household) async throws {
        calls.append("leave")
        if leaveFailures > 0 {
            leaveFailures -= 1
            throw Offline()
        }
        guard !members.isOwner else { throw NotShared() }
        members.participants.removeAll { $0.isCurrentUser }
        try onLeave(household)
    }

    struct NotShared: LocalizedError {
        var errorDescription: String? { "This household is yours, so there is nothing to leave." }
    }
}
#endif
