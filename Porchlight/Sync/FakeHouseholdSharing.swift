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

    func endJoinCode(_ household: Household) async throws {
        calls.append("endJoinCode")
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
}
#endif
