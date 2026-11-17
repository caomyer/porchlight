import Foundation
import Observation

/// The household's share as the screens show it: who is on it, and the actions on it.
/// Wraps a `HouseholdSharing`, live or fake, and keeps the last members it read, so a
/// screen shows them at once and offline.
@MainActor
@Observable
final class HouseholdSharingModel {
    @ObservationIgnored let service: any HouseholdSharing
    @ObservationIgnored private let database: AppDatabase

    private(set) var members: HouseholdMembers = .none
    /// People who joined through the share's old public link, which is still open: the
    /// owner is shown who they are and chooses (docs/design/households.md, "The join code").
    private(set) var linkJoiners: [HouseholdParticipant] = []
    /// This device's iCloud user record name, once read.
    private(set) var userName: String?

    init(service: any HouseholdSharing, database: AppDatabase) {
        self.service = service
        self.database = database
    }

    var unavailableReason: String? { service.unavailableReason }

    /// Reads the share again. Keeps what it had when iCloud can't be reached.
    func refresh(_ household: Household?) async {
        guard let household else { return }
        userName = await service.currentUserName() ?? userName
        guard let members = try? await service.participants(of: household) else { return }
        self.members = members
        if members.isOwner { await checkPublicLink(household) }
        // Remembered so a removed device can still say who removed it.
        if !members.isOwner, let owner = members.owner?.name {
            try? database.rememberOwner(owner, of: household.id)
        }
    }

    /// Porchlight keeps the share's public link closed. One left open from the earlier
    /// join code is closed at once when nobody joined through it; otherwise the owner sees
    /// who did, and nothing is closed until they choose.
    func checkPublicLink(_ household: Household) async {
        guard let joiners = try? await service.publicLink(of: household) else {
            if !linkJoiners.isEmpty { linkJoiners = [] }
            return
        }
        if joiners.isEmpty {
            try? await service.closePublicLink(household)
            SyncLog.shared.write("share: public link found open with nobody through it; closed")
            if !linkJoiners.isEmpty { linkJoiners = [] }
        } else {
            SyncLog.shared.write("share: public link found open, \(joiners.count) joined through it; asking the owner")
            if joiners != linkJoiners { linkJoiners = joiners }
        }
    }

    /// The owner chose: the link closes, which removes the people who joined through it.
    func closePublicLink(_ household: Household) async throws {
        try await service.closePublicLink(household)
        linkJoiners = []
        await refresh(household)
    }

    /// The owner's name as the household says it: their person, through the iCloud user
    /// their devices carry, else iCloud's name for them.
    func ownerName(people: [Person], devices: [Device]) -> String? {
        guard let owner = members.owner else { return nil }
        // Their own devices only: a shared screen signed in to their iCloud belongs to nobody.
        if let personId = devices.lazy.filter({ $0.userName != nil && $0.userName == owner.userName }).compactMap(\.owner).first,
           let person = people.person(personId) {
            return person.name
        }
        return owner.name
    }

    /// Removes someone's devices from the household: off the share, then their device rows.
    /// Their person stays, with their color and history (journey A6).
    func remove(_ participant: HouseholdParticipant, from household: Household) async throws {
        try await service.remove(participant, from: household)
        if let userName = participant.userName {
            try database.removeDevices(ofUser: userName, in: household.id)
        }
        members.participants.removeAll { $0.id == participant.id }
    }

    /// Leaves someone else's household (journey A6): off its share, then the household goes
    /// from this device. Everything this person logged stays with the household. `app`
    /// forgets the household first, so its going isn't shown as someone removing it.
    func leave(_ household: Household, app: AppModel) async throws {
        var failure: (any Error)?
        await app.removeHouseholdHere {
            do {
                try await service.leave(household)
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        members = .none
    }
}
