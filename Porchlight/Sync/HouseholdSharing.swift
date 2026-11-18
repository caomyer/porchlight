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
    /// Whether this device can make a join code: a one-time private seat, which needs
    /// iOS 18 on the device that saves the share (docs/design/households.md, "The join code").
    var supportsJoinSeats: Bool { get }
    /// Adds one private, read-and-write seat to the share and returns its one-time link, for
    /// a code to scan. Whoever opens the link first takes the seat.
    func openSeat(_ household: Household) async throws -> JoinSeat
    /// Whether someone has taken the seat yet.
    func seatState(_ seat: JoinSeat, in household: Household) async throws -> SeatState
    /// Removes the seat if nobody took it. A taken seat, and everyone else, is never touched.
    func closeSeat(_ seat: JoinSeat, in household: Household) async throws
    /// Nil when the share's public link is closed, as Porchlight keeps it; otherwise who
    /// joined through it (possibly nobody), left from the earlier public join code.
    func publicLink(of household: Household) async throws -> [HouseholdParticipant]?
    /// Closes the public link, which removes everyone who joined through it; only called
    /// when nobody did, or when the owner chose it after being told who.
    func closePublicLink(_ household: Household) async throws
    /// Why this device can't join a household now, before anything is accepted: accepting
    /// takes a join code's one seat, so a device whose sync can't run must say so first.
    /// Waits for this launch's first look at the account. Nil when it can join.
    func joinBlocker() async -> String?
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

/// One private seat on the share, for a join code: the participant CloudKit made and the
/// one-time link that claims it.
struct JoinSeat: Equatable, Sendable {
    var id: String
    var url: URL
}

/// A seat's state, as the code's sheet follows it.
enum SeatState: Equatable, Sendable {
    /// Nobody has opened the link yet.
    case waiting
    /// Someone took it; their iCloud user, once known, names their person here.
    case claimed(userName: String?)
    /// The seat isn't on the share anymore.
    case gone
}

/// Why a device can't join a household now, from its sync status, in the words of the
/// iCloud states (`ICloudAccountProblem`). The invite or code is left as it was, so "Try
/// again" works once it is sorted.
enum JoinBlocker {
    static func reason(_ status: SyncStatus, device: String) -> String? {
        switch status {
        case .off(.switchedOff):
            "iCloud sync is off on this \(device). Turn on Sync with iCloud under You, then try again."
        case .off:
            "Joining needs iCloud sync, which can't run on this \(device) now."
        case .account(.signedOut):
            "iCloud is off for Porchlight. Sign in to iCloud, or turn it on for Porchlight, in Settings, then try again."
        case .account(.restricted):
            "iCloud isn't allowed on this \(device), so it can't join a household."
        case .account(.needsSignIn):
            "iCloud needs you to sign in again. Sign in to your Apple Account in Settings, then try again."
        case .needsDecision:
            "Sync is waiting for your choice under You. Choose, then try again."
        // Not knowing the account, offline or full: accepting may still work, and says so if not.
        case .account(.couldNotCheck), .upToDate, .notChecked, .syncing, .waiting, .iCloudFull, .notAccepted:
            nil
        }
    }
}

/// Where a join code can be shown (docs/design/households.md, "The join code").
enum JoinCodeAvailability: Equatable, Sendable {
    case available
    /// Not on this device: the one line that says where instead.
    case elsewhere(String)

    /// Only the household's owner can add people to its share, and a code is a seat only a
    /// device with iOS 18 can make.
    static func decide(isOwner: Bool, supportsSeats: Bool, ownerName: String?) -> JoinCodeAvailability {
        let owners = ownerName.map { "\($0.possessive) iPhone" } ?? "the owner's iPhone"
        let way = "To show a join code, open Porchlight on \(owners): You, Invite someone, Show a code."
        if isOwner { return supportsSeats ? .available : .elsewhere(way) }
        return .elsewhere("Only \(ownerName ?? "the household's owner") can add people to the household. \(way)")
    }
}
