import CloudKit
import Foundation
import SQLiteData

/// Sharing through the sync engine and CloudKit. The household row is the share's root, so
/// sharing it shares everything that hangs off it.
///
/// Only real devices with two Apple IDs can prove this (the M2 device checklist): SQLiteData's
/// stand-in for iCloud is internal to its package, and simulator builds are unsigned.
@MainActor
final class LiveHouseholdSharing: HouseholdSharing {
    private let sync: SyncController
    private let database: AppDatabase

    init(sync: SyncController, database: AppDatabase) {
        self.sync = sync
        self.database = database
    }

    /// Only touched once the engine exists: a build without the iCloud entitlement has no
    /// engine, and creating a `CKContainer` there traps.
    private var container: CKContainer { CKContainer(identifier: SyncController.containerIdentifier) }

    /// Sync's own states are told by `HouseholdHome`; this is what is left when sync is on
    /// but the engine hasn't started yet.
    var unavailableReason: String? {
        guard let engine = sync.engine else { return "Inviting needs iCloud, and this build can't use it." }
        return engine.isRunning ? nil : "Inviting works once iCloud sync is running."
    }

    func currentUserName() async -> String? {
        guard sync.engine != nil else { return nil }
        return try? await container.userRecordID().recordName
    }

    func participants(of household: Household) async throws -> HouseholdMembers {
        guard let share = try await latestShare(of: household) else { return .none }
        let me = await currentUserName()
        return HouseholdMembers(share: share, currentUserName: me)
    }

    func invite(_ household: Household) async throws -> HouseholdInvite {
        guard let engine = sync.engine else { throw SharingFailure.noEngine }
        return .cloud(try await share(household) { _ in }, engine)
    }

    func joinCode(_ household: Household) async throws -> URL {
        let shared = try await share(household) { $0.publicPermission = .readWrite }
        Self.log("join code on", shared.share)
        guard let url = shared.share.url else { throw SharingFailure.noLink }
        return url
    }

    func linkJoiners(of household: Household) async throws -> [HouseholdParticipant] {
        guard let share = try await latestShare(of: household) else { return [] }
        let me = await currentUserName()
        return HouseholdMembers(share: share, currentUserName: me).participants
            .filter { $0.joinedByLink && $0.status == .joined && !$0.isCurrentUser }
    }

    func endJoinCode(_ household: Household) async throws {
        let shared = try await share(household) { $0.publicPermission = .none }
        Self.log("join code off", shared.share)
    }

    /// The share's state for the sync log: its link and how many participants of each
    /// role and status, never who.
    static func log(_ event: String, _ share: CKShare) {
        let link = share.publicPermission == .none ? "closed" : "open"
        var counts: [String: Int] = [:]
        for participant in share.participants {
            let role = switch participant.role {
            case .owner: "owner"
            case .privateUser: "private"
            case .publicUser: "link"
            default: "other"
            }
            let status = switch participant.acceptanceStatus {
            case .accepted: "joined"
            case .pending: "pending"
            case .removed: "removed"
            default: "unknown"
            }
            counts["\(role) \(status)", default: 0] += 1
        }
        let summary = counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        SyncLog.shared.write("share: \(event); link \(link); participants \(summary)")
    }

    func accept(_ invitation: HouseholdInvitation) async throws {
        guard let engine = sync.engine, let metadata = invitation.metadata else { throw SharingFailure.noEngine }
        try await engine.acceptShare(metadata: metadata)
    }

    func remove(_ participant: HouseholdParticipant, from household: Household) async throws {
        guard let share = try await latestShare(of: household),
              let found = share.participants.first(where: { $0.matches(participant) }) else { return }
        share.removeParticipant(found)
        let (results, _) = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        for result in results.values { _ = try result.get() }
        Self.log("participant removed", share)
        // The engine caches the share with the household's metadata; fetching refreshes it.
        try? await sync.engine?.fetchChanges()
    }

    func leave(_ household: Household) async throws {
        guard sync.engine != nil else { throw SharingFailure.noEngine }
        guard let share = try await latestShare(of: household),
              share.recordID.zoneID.ownerName != CKCurrentUserDefaultName else { throw SharingFailure.notShared }
        // A participant leaves by deleting the share from their own shared database; the
        // owner's household, and everyone else's access to it, are untouched.
        let (_, results) = try await container.sharedCloudDatabase.modifyRecords(saving: [], deleting: [share.recordID])
        for result in results.values { try result.get() }
        // The engine then sees the shared zone go, and removes the household from this device.
        try? await sync.engine?.fetchChanges()
    }

    // MARK: Private

    private enum SharingFailure: LocalizedError {
        case noEngine, noHousehold, noLink, notShared

        var errorDescription: String? {
            switch self {
            case .noEngine: "iCloud sync isn't running on this device."
            case .noHousehold: "The household hasn't reached iCloud yet. Try again in a minute."
            case .noLink: "iCloud didn't make a link for the household. Try again in a minute."
            case .notShared: "This household is yours, so there is nothing to leave."
            }
        }
    }

    /// Creates the household's share, or saves the existing one, after `configure`. Every
    /// participant may read and write.
    private func share(_ household: Household, configure: @escaping @Sendable (CKShare) -> Void) async throws -> SharedRecord {
        guard let engine = sync.engine else { throw SharingFailure.noEngine }
        guard let root = try await database.writer.read({ db in
            try SyncMirror.Household.find(household.id.uuid).fetchOne(db)
        }) else { throw SharingFailure.noHousehold }
        let name = household.name
        return try await engine.share(record: root) { share in
            share[CKShare.SystemFieldKey.title] = name
            configure(share)
        }
    }

    /// The share as iCloud has it now, or as the engine last cached it when offline.
    private func latestShare(of household: Household) async throws -> CKShare? {
        guard sync.engine != nil else { return nil }
        let cached = try await database.writer.read { db -> CKShare? in
            guard let root = try SyncMirror.Household.find(household.id.uuid).fetchOne(db) else { return nil }
            return try SyncMetadata.find(root.syncMetadataID).select(\.share).fetchOne(db) ?? nil
        }
        guard let cached else { return nil }
        let isMine = cached.recordID.zoneID.ownerName == CKCurrentUserDefaultName
        let cloud = isMine ? container.privateCloudDatabase : container.sharedCloudDatabase
        return (try? await cloud.record(for: cached.recordID) as? CKShare) ?? cached
    }
}

extension HouseholdMembers {
    init(share: CKShare, currentUserName: String?) {
        let current = share.currentUserParticipant
        participants = share.participants
            .filter { $0.acceptanceStatus != .removed }
            .map { participant in
                let isCurrentUser = current.map { $0 == participant } ?? false
                // A share names its owner "__defaultOwner__" on the owner's own devices.
                let recordName = participant.userIdentity.userRecordID?.recordName
                let userName = isCurrentUser ? (currentUserName ?? recordName) : recordName
                let lookup = participant.userIdentity.lookupInfo
                return HouseholdParticipant(
                    id: userName ?? lookup?.emailAddress ?? lookup?.phoneNumber ?? UUID().uuidString,
                    name: participant.userIdentity.nameComponents.flatMap(HouseholdParticipant.shortName)
                        ?? lookup?.emailAddress ?? lookup?.phoneNumber,
                    userName: userName,
                    role: participant.role == .owner ? .owner : .member,
                    status: participant.acceptanceStatus == .accepted ? .joined : .invited,
                    isCurrentUser: isCurrentUser,
                    joinedByLink: participant.role == .publicUser
                )
            }
            .sorted { ($0.role == .owner ? 0 : 1) < ($1.role == .owner ? 0 : 1) }
    }
}

private extension CKShare.Participant {
    func matches(_ participant: HouseholdParticipant) -> Bool {
        if let userName = participant.userName, userIdentity.userRecordID?.recordName == userName { return true }
        let lookup = userIdentity.lookupInfo
        return participant.userName == nil
            && (lookup?.emailAddress == participant.id || lookup?.phoneNumber == participant.id)
    }
}
