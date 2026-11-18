import Foundation
import GRDB
import Observation

/// Joining a household from an invite (journey A4): "Join?", then accepting, then "Which
/// one is you?" unless this iCloud user is already known there, then the household
/// coming in. Nothing is half joined: until the household is here, the preview stays.
@MainActor
@Observable
final class JoinFlow: StoredFirstObservable {
    enum Step: Equatable {
        case preview
        case joining
        case who(Household.ID)
        case bringingIn(Household.ID)
    }

    let invitation: HouseholdInvitation
    @ObservationIgnored @StoredFirst private(set) var step: Step = .preview
    /// Why the last try didn't join, in plain words, with "Try again".
    @ObservationIgnored @StoredFirst private(set) var failure: String? = nil

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let sharing: any HouseholdSharing
    @ObservationIgnored private let device: DeviceSettings
    @ObservationIgnored private let arrivalTimeout: Duration

    init(
        invitation: HouseholdInvitation, database: AppDatabase, sharing: any HouseholdSharing,
        device: DeviceSettings, arrivalTimeout: Duration = .seconds(60)
    ) {
        self.invitation = invitation
        self.database = database
        self.sharing = sharing
        self.device = device
        self.arrivalTimeout = arrivalTimeout
    }

    /// "Join": accepts the invite and waits for the household to arrive. A device that
    /// already belongs to it, or this iCloud user's earlier device, skips "Which one is you?".
    func join() async {
        guard step == .preview else { return }
        step = .joining
        failure = nil
        do {
            if !invitation.isAlreadyIn {
                // Accepting takes a join code's one seat: never when the household couldn't come in.
                if let blocker = await sharing.joinBlocker() {
                    fail(blocker)
                    return
                }
                try await sharing.accept(invitation)
            }
            guard let id = try await arrivedHousehold() else {
                fail("\(invitation.householdName) hasn't arrived yet. Check that this \(device.model) is online, then try again.")
                return
            }
            try database.chooseHousehold(id)
            try database.rememberOwner(invitation.ownerName, of: id)
            if device.role == .sharedScreen || hasMe(in: id) {
                step = .bringingIn(id)
            } else if let known = try await knownPerson(in: id) {
                device.setMe(known, in: id)
                step = .bringingIn(id)
            } else {
                step = .who(id)
            }
        } catch {
            fail("Couldn't join yet. Check that this \(device.model) is online, then try again.")
        }
    }

    /// "Continue as Mia".
    func pick(_ personId: Person.ID) {
        guard case let .who(id) = step else { return }
        device.setMe(personId, in: id)
        step = .bringingIn(id)
    }

    /// "I'm new here": adds a person and continues as them.
    func addMe(_ draft: PersonDraft) throws {
        guard case let .who(id) = step else { return }
        let person = try database.addPerson(draft, to: id)
        pick(person.id)
    }

    private func fail(_ message: String) {
        failure = message
        step = .preview
    }

    private func hasMe(in householdId: Household.ID) -> Bool {
        guard let me = device.me(in: householdId) else { return false }
        return (try? database.writer.read { db in
            try Person.active(in: householdId).filter(Column("id") == me).fetchCount(db) > 0
        }) ?? false
    }

    /// The household, once it is in the database: the one the invite names, or (for an
    /// invite that doesn't say) the newest.
    private func arrivedHousehold() async throws -> Household.ID? {
        let writer = database.writer
        let named = invitation.householdId
        let timeout = arrivalTimeout
        return try await withThrowingTaskGroup(of: Household.ID?.self) { group in
            group.addTask {
                let arrivals = ValueObservation.tracking { db -> Household.ID? in
                    if let named { return try Household.exists(db, id: named) ? named : nil }
                    return try Household.order(Column("createdAt").desc).fetchOne(db)?.id
                }
                for try await id in arrivals.values(in: writer) where id != nil { return id }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// This iCloud user's person, when one of their devices is already in the household.
    private func knownPerson(in householdId: Household.ID) async throws -> Person.ID? {
        guard let me = await sharing.currentUserName() else { return nil }
        return try await database.writer.read { db in
            let devices = try Device
                .filter(Column("householdId") == householdId && Column("userName") == me)
                .order(Column("seenAt").desc)
                .fetchAll(db)
            let active = Set(try Person.active(in: householdId).fetchAll(db).map(\.id))
            return devices.lazy.compactMap(\.owner).first { active.contains($0) }
        }
    }
}
