import Foundation
import Observation

/// Live app state for the UI. Mirrors the database and forwards edits to it.
@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: HouseholdSnapshot = .empty
    var lastError: String?

    let database: AppDatabase
    @ObservationIgnored private var observation: Task<Void, Never>?

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
    var people: [Person] { snapshot.people }

    private func observe() {
        observation = Task { [weak self, database] in
            do {
                for try await snapshot in database.householdUpdates() {
                    self?.snapshot = snapshot
                }
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    // MARK: Edits (validation errors are surfaced through `lastError`)

    func createHousehold(name: String, people: [PersonDraft]) -> Bool {
        perform { try database.createHousehold(name: name, people: people) }
    }

    func renameHousehold(to name: String) -> Bool {
        guard let id = household?.id else { return false }
        return perform { try database.renameHousehold(id: id, to: name) }
    }

    func addPerson(_ draft: PersonDraft) -> Bool {
        guard let id = household?.id else { return false }
        return perform { try database.addPerson(draft, to: id) }
    }

    func updatePerson(_ person: Person, name: String, color: PersonColor) -> Bool {
        guard let id = person.id else { return false }
        return perform { try database.updatePerson(id: id, name: name, color: color) }
    }

    func deletePerson(_ person: Person) -> Bool {
        guard let id = person.id else { return false }
        return perform { try database.deletePerson(id: id) }
    }

    func movePeople(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let householdId = household?.id else { return }
        var ids = people.compactMap(\.id)
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
