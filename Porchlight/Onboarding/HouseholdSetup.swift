import Foundation
import Observation

/// Starting a household, the one way both first runs do it: the wall's setup (A1) and the
/// phone's (A2) edit the same drafts and create the household through the same calls, so a
/// household started on a phone is exactly the household a wall would have made, and a
/// wall added later (same Apple ID, or joining) finds nothing unusual.
///
/// What the household is made of is created here and in `AppModel.finishSetup`; the steps
/// in between (companions, calendars, the food diary's switch) save through their own stores
/// as they are edited, on either device.
@MainActor
@Observable
final class HouseholdSetup {
    var householdName = ""
    /// Everyone who lives here, in order. On someone's own device the first is its owner.
    var people: [PersonDraft]

    init(householdName: String = "", people: [PersonDraft] = [PersonDraft(name: "", color: .suggested(for: 0))]) {
        self.householdName = householdName
        self.people = people
    }

    /// The household has a name to save.
    var hasName: Bool { !householdName.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The people with names; blank rows are simply skipped.
    var namedPeople: [PersonDraft] {
        people.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var hasPeople: Bool { !namedPeople.isEmpty }

    /// Adds an empty row with the next color, and returns its index.
    @discardableResult
    func addPerson() -> Int {
        people.append(PersonDraft(name: "", color: .suggested(for: people.count)))
        return people.count - 1
    }

    func removePerson(at index: Int) {
        guard people.indices.contains(index), people.count > 1 else { return }
        people.remove(at: index)
    }

    /// Creates the household with its named people. On a personal device, `owner` is the
    /// index (among the named people) of the person this device belongs to; it becomes "me"
    /// here, and the device keeps its personal role. Errors land in `app.lastError`.
    @discardableResult
    func create(app: AppModel, device: DeviceSettings, owner: Int? = nil) -> Household? {
        guard let household = app.createHousehold(name: householdName, people: namedPeople) else { return nil }
        if let owner, let people = try? app.database.writer.read({ try Person.active(in: household.id).fetchAll($0) }), people.indices.contains(owner) {
            device.setRole(.personal)
            device.setMe(people[owner].id, in: household.id)
        }
        return household
    }
}
