import CloudKit
import Foundation
import SQLiteData

/// Sharing the household with other iCloud users (docs/design/households.md, "Sharing").
///
/// The live implementation goes through the sync engine and CloudKit; real sharing needs
/// two Apple IDs on signed builds, so tests, previews and screenshots use the fake.
@MainActor
protocol HouseholdSharing: AnyObject {
    /// Why inviting can't work right now, in plain words; nil when it can.
    var unavailableReason: String? { get }
    /// The iCloud user's record name on this device, to match devices to participants.
    func currentUserName() async -> String?
    /// The household's share: its owner, and who joined or is invited.
    func participants(of household: Household) async throws -> HouseholdMembers
    /// What the system's share sheet needs to invite someone.
    func invite(_ household: Household) async throws -> HouseholdInvite
    /// The share's link for a code to scan, after letting anyone with the link join.
    func joinCode(_ household: Household) async throws -> URL
    /// Stops anyone with the link joining, when the code is put away.
    func endJoinCode(_ household: Household) async throws
    /// Accepts an invite that opened the app; the household syncs in.
    func accept(_ invitation: HouseholdInvitation) async throws
    /// Removes someone from the share, for the owner. Their history stays.
    func remove(_ participant: HouseholdParticipant, from household: Household) async throws
    /// Leaves someone else's household, for a member (journey A6): this iCloud user is off
    /// its share, and the household goes from their devices. What they logged stays with the
    /// household for everyone else. The owner can't leave; their household is theirs.
    func leave(_ household: Household) async throws
}

/// Someone who can see the household through its share.
struct HouseholdParticipant: Identifiable, Hashable, Sendable {
    enum Role: Sendable { case owner, member }
    enum Status: Sendable { case invited, joined }

    var id: String
    /// Their name as iCloud knows it, when it does ("Mia"); a link invite has none until
    /// it is accepted.
    var name: String?
    /// Their iCloud user record name, once known, which their devices' rows carry.
    var userName: String?
    var role: Role
    var status: Status
    var isCurrentUser: Bool
}

/// Everyone on the household's share.
struct HouseholdMembers: Equatable, Sendable {
    var participants: [HouseholdParticipant]

    static let none = HouseholdMembers(participants: [])

    var owner: HouseholdParticipant? { participants.first { $0.role == .owner } }

    /// Whether this device's iCloud user owns the household. A household nobody has been
    /// invited to has no share yet, and is the creator's own.
    var isOwner: Bool { owner?.isCurrentUser ?? true }

    /// Invited people who haven't joined yet.
    var invited: [HouseholdParticipant] { participants.filter { $0.status == .invited } }

    /// The participant behind a device, matched by iCloud user.
    func participant(userName: String?) -> HouseholdParticipant? {
        guard let userName else { return nil }
        return participants.first { $0.userName == userName }
    }
}

/// An invite that opened the app, before it is accepted (journey A4, "Join?").
struct HouseholdInvitation: Identifiable, @unchecked Sendable {
    let id = UUID()
    /// The household's id, from the share's root record, when it says.
    var householdId: Household.ID?
    var householdName: String
    /// Whose iCloud holds it, who also sent the invite.
    var ownerName: String?
    /// This iCloud user already owns or joined it, so there is nothing to accept.
    var isAlreadyIn: Bool
    /// The system's share metadata; nil for the fake's invitations.
    var metadata: CKShare.Metadata?

    init(householdId: Household.ID?, householdName: String, ownerName: String?, isAlreadyIn: Bool = false, metadata: CKShare.Metadata? = nil) {
        self.householdId = householdId
        self.householdName = householdName
        self.ownerName = ownerName
        self.isAlreadyIn = isAlreadyIn
        self.metadata = metadata
    }

    /// Reads what the preview shows from the share's metadata, before anything is accepted.
    /// SQLiteData names records "id:table", so the root record names the household.
    init(metadata: CKShare.Metadata) {
        let rootName = (metadata.hierarchicalRootRecordID ?? metadata.share.recordID).recordName
        let householdId = rootName.split(separator: ":").first.flatMap { Household.ID(String($0)) }
        self.init(
            householdId: householdId,
            householdName: metadata.share[CKShare.SystemFieldKey.title] as? String ?? "a household",
            ownerName: metadata.ownerIdentity.nameComponents.flatMap(HouseholdParticipant.shortName),
            isAlreadyIn: metadata.participantRole == .owner || metadata.participantStatus == .accepted,
            metadata: metadata
        )
    }
}

/// What the invite sheet presents.
enum HouseholdInvite: Identifiable {
    /// The system's own sharing sheet, over the household's share.
    case cloud(SharedRecord, SyncEngine)
    /// The fake's stand-in, for tests and screenshots.
    case standIn(householdName: String)

    var id: String {
        switch self {
        case let .cloud(record, _): record.id.recordName
        case let .standIn(name): name
        }
    }
}

extension HouseholdParticipant {
    /// "Mia" from "Mia Cao".
    static func shortName(_ components: PersonNameComponents) -> String? {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        let name = formatter.string(from: components)
        return name.isEmpty ? nil : name
    }
}

/// How the QR code behaves when it is put away (docs/design/households.md, experiment S2).
enum JoinCodePolicy {
    /// Whether someone who joined through the link keeps access once link-joining is turned
    /// off. Assumed yes until two devices prove it; if not, the code stays joinable after the
    /// screen closes, and the screen says so.
    static let joinersKeepAccess = true
}
