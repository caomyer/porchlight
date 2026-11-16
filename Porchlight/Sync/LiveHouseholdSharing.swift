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

    var unavailableReason: String? {
        guard let engine = sync.engine else {
            return "Inviting needs iCloud, and this build can't use it."
        }
        switch sync.status {
        case .noAccount: return "Sign in to iCloud in the Settings app to invite people."
        case .off(.switchedOff): return "Turn on iCloud sync below to invite people."
        case .needsDecision: return "Choose what to do about iCloud sync below first."
        default: return engine.isRunning ? nil : "Inviting works once iCloud sync is running."
        }
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
        guard let url = shared.share.url else { throw SharingFailure.noLink }
        return url
    }

    func endJoinCode(_ household: Household) async throws {
        _ = try await share(household) { $0.publicPermission = .none }
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
        // The engine caches the share with the household's metadata; fetching refreshes it.
        try? await sync.engine?.fetchChanges()
    }

    // MARK: Private

    private enum SharingFailure: LocalizedError {
        case noEngine, noHousehold, noLink

        var errorDescription: String? {
            switch self {
            case .noEngine: "iCloud sync isn't running on this device."
            case .noHousehold: "The household hasn't reached iCloud yet. Try again in a minute."
            case .noLink: "iCloud didn't make a link for the household. Try again in a minute."
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
                    isCurrentUser: isCurrentUser
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
