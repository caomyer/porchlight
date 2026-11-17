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
    /// Who joined through the link and is still in: they lose access when the code is
    /// turned off (docs/design/households.md, "The join code").
    func linkJoiners(of household: Household) async throws -> [HouseholdParticipant]
    /// Stops anyone with the link joining. CloudKit then removes everyone who joined through
    /// it, so it is only called when nobody did, or when the owner chose to after being told who.
    func endJoinCode(_ household: Household) async throws
    /// Accepts an invite that opened the app; the household syncs in.
    func accept(_ invitation: HouseholdInvitation) async throws
    /// Removes someone from the share, for the owner. Their history stays.
    func remove(_ participant: HouseholdParticipant, from household: Household) async throws
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
    /// Joined through the code's link (a public participant): turning the code off removes them.
    var joinedByLink = false
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

/// How the QR code behaves when it is put away (docs/design/households.md, "The join code").
///
/// Experiment S2 answered it on two devices, as Apple's documentation says: setting the
/// share's `publicPermission` back to none removes everyone who joined through the link. So
/// putting the code away only closes the link when nobody joined through it; otherwise the
/// code stays on, the sheet says who it keeps in, and turning it off is the owner's choice,
/// made knowing who will lose access.
enum JoinCodePolicy {
    /// What putting the code away does, given who joined through it.
    enum Closing: Equatable {
        /// Nobody joined through it: the link closes.
        case closeLink
        /// These people joined through it and keep access only while it stays on.
        case keepOpen([String])
    }

    static func closing(linkJoiners: [HouseholdParticipant]) -> Closing {
        linkJoiners.isEmpty ? .closeLink : .keepOpen(linkJoiners.map { $0.name ?? "Someone with the code" })
    }

    /// "Carol joined with this code…", or nil when nobody did.
    static func keptOpenText(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let who = ListFormatter.localizedString(byJoining: names)
        let they = names.count == 1 ? "They keep" : "They keep"
        return "\(who) joined with this code. \(they) access only while the code stays on, so it stays on after you close this."
    }

    /// The question before turning the code off: who it removes.
    static func turnOffQuestion(_ names: [String]) -> String {
        let who = ListFormatter.localizedString(byJoining: names)
        return "Turning the code off removes \(who) from the household. You can invite \(names.count == 1 ? "them" : "them") again by name with Invite someone."
    }
}
