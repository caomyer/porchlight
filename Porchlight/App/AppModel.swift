import Foundation
import Observation

/// Live app state for the UI. Mirrors the database and forwards edits to it.
@MainActor
@Observable
final class AppModel: StoredFirstObservable {
    /// What the database says now. Stored before observers are told, unlike a plain
    /// `@Observable` property: SwiftUI hears of a change in `willSet` and may redraw right
    /// there, and a screen redrawn then would read the old value and never hear the change
    /// itself, staying out of date (a chore still checked after Undo). The stores that mirror
    /// the database do the same.
    private(set) var snapshot: HouseholdSnapshot {
        get {
            access(keyPath: \.snapshot)
            return storedSnapshot
        }
        set {
            storedSnapshot = newValue
            withMutation(keyPath: \.snapshot) {}
        }
    }

    @ObservationIgnored private var storedSnapshot: HouseholdSnapshot = .empty
    @ObservationIgnored @StoredFirst var lastError: String? = nil

    let database: AppDatabase
    @ObservationIgnored private var observation: Task<Void, Never>?
    /// True while this device removes its household itself, so the household going is not
    /// taken for someone else removing it.
    @ObservationIgnored private var isRemovingHousehold = false

    init(database: AppDatabase) {
        self.database = database
        // Read synchronously once so the first frame already knows whether to
        // show onboarding, then keep listening for changes.
        if let first = try? database.snapshot() {
            snapshot = first
        }
        observe()
    }

    var household: Household? { snapshot.household }
    /// The people who live here now, for pickers and lists.
    var people: [Person] { snapshot.people }
    /// Everyone, removed people included, for showing who did something in the past.
    var everyone: [Person] { snapshot.everyone }
    /// Every device that has opened the household.
    var devices: [Device] { snapshot.devices }
    /// The household this device showed and no longer has (journey A6).
    var removedHousehold: RemovedHousehold? { snapshot.removed }
    /// Every set-up household on this device, oldest first (journey A5).
    var households: [HouseholdChoice] { snapshot.households }
    /// True when this device belongs to more than one household, so screens say which.
    var isInSeveralHouseholds: Bool { snapshot.households.count > 1 }
    /// "Join or start another" chose to start one: the phone shows setup until it exists.
    /// The new household arriving from the database clears it, so it is stored first.
    @ObservationIgnored @StoredFirst var isStartingAnotherHousehold = false

    /// Shows another household; every tab follows (journey A5).
    func switchHousehold(to id: Household.ID) {
        guard id != household?.id else { return }
        perform { try database.chooseHousehold(id) }
    }

    /// This device's row in the current household.
    var thisDeviceId: Device.ID? {
        household.map { database.thisDeviceId(in: $0.id) }
    }

    /// "from Mia's phone" for a row written on someone's own device; nil otherwise.
    func tag(for deviceId: Device.ID?) -> String? {
        snapshot.tag(for: deviceId)
    }

    private func observe() {
        observation = Task { [weak self, database] in
            do {
                for try await snapshot in database.householdUpdates() {
                    guard let self else { return }
                    self.snapshot = snapshot
                    if !isRemovingHousehold {
                        try? database.rememberCurrentHousehold()
                    }
                }
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    // MARK: This device

    /// Writes this device's row in the current household when something about it changed,
    /// and at most once a day otherwise.
    func saveThisDevice(_ device: ThisDevice) {
        guard let id = household?.id else { return }
        perform { try database.saveThisDevice(device, in: id) }
    }

    /// Removes the household from this device, on the owner's own choice (a different
    /// account, a restored copy): the household going is not shown as being removed.
    func removeHouseholdHere(_ removal: () async -> Void) async {
        isRemovingHousehold = true
        defer { isRemovingHousehold = false }
        _ = perform { try database.forgetCurrentHousehold() }
        await removal()
    }

    /// Acknowledges that the household left: the device shows another one, or the welcome.
    func forgetRemovedHousehold() {
        perform { try database.forgetCurrentHousehold() }
    }

    // MARK: Edits (validation errors are surfaced through `lastError`)

    /// Creates the household and its first people (`HouseholdSetup` calls this, on either
    /// device). Nil, with `lastError` set, when it can't.
    func createHousehold(name: String, people: [PersonDraft]) -> Household? {
        var created: Household?
        perform { created = try database.createHousehold(name: name, people: people) }
        return created
    }

    /// Ends setup, the same on the wall and the phone: the food diary exists (on, unless
    /// the wall's journals step turned it off), and the household is marked set up.
    func finishSetup() -> Bool {
        guard let id = household?.id else { return false }
        return perform {
            try database.ensureFoodJournal(householdId: id)
            try database.markSetupCompleted(householdId: id)
        }
    }

    /// The household's calendar (time zone, first weekday), or the device's before setup.
    var calendar: Calendar { household?.calendar ?? .current }

    func renameHousehold(to name: String) -> Bool {
        guard let id = household?.id else { return false }
        return perform { try database.renameHousehold(id: id, to: name) }
    }

    func addPerson(_ draft: PersonDraft) -> Bool {
        guard let id = household?.id else { return false }
        return perform { try database.addPerson(draft, to: id) }
    }

    func updatePerson(_ person: Person, name: String, color: PersonColor) -> Bool {
        perform { try database.updatePerson(id: person.id, name: name, color: color) }
    }

    /// Removes someone from the household; their history stays (see `archivePerson`).
    func removePerson(_ person: Person) -> Bool {
        perform { try database.archivePerson(id: person.id) }
    }

    func movePeople(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let householdId = household?.id else { return }
        var ids = people.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        _ = perform { try database.reorderPeople(householdId: householdId, ids: ids) }
    }

    @discardableResult
    private func perform(_ work: () throws -> Void) -> Bool {
        do {
            try work()
            lastError = nil
            return true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
