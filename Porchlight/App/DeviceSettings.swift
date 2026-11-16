import Foundation
import Observation
import UIKit

/// How this device is used. It decides whether logging asks who did it.
enum DeviceRole: String, CaseIterable, Sendable {
    /// On a wall or a counter: anyone can tap, so it asks who did something.
    case sharedScreen
    /// Someone's own device: it credits its owner and never asks.
    case personal

    /// The role a device starts with: shared on an iPad, personal on a phone.
    /// This is the only place in the app that looks at what kind of device it is;
    /// everything else reads the role.
    static func standard(for idiom: UIUserInterfaceIdiom) -> DeviceRole {
        idiom == .pad ? .sharedScreen : .personal
    }
}

/// Settings that belong to this device, never to the household: its role, its name, and
/// which person it belongs to in each household ("me"). Kept in `UserDefaults`; this
/// device's row in the household mirrors them so others can see them (`ThisDeviceRow`).
@MainActor
@Observable
final class DeviceSettings {
    static let roleKey = "device.role"
    static let nameKey = "device.name"
    static let mePrefix = "device.me."

    private(set) var role: DeviceRole
    /// The name someone gave this device; nil until they do.
    private(set) var customName: String?
    /// "iPhone" or "iPad": only words, never behavior.
    let model: String
    /// "Me" per household id, mirrored from the defaults so views update when it changes.
    private var me: [Household.ID: Person.ID]

    @ObservationIgnored private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
        model: String = UIDevice.current.model
    ) {
        self.defaults = defaults
        self.model = model
        role = defaults.string(forKey: Self.roleKey).flatMap(DeviceRole.init(rawValue:)) ?? .standard(for: idiom)
        customName = defaults.string(forKey: Self.nameKey)
        me = Self.storedMe(in: defaults)
    }

    func setRole(_ role: DeviceRole) {
        self.role = role
        defaults.set(role.rawValue, forKey: Self.roleKey)
    }

    /// This device's name: the one it was given, else "Mia's iPhone" on someone's own
    /// device and "Shared iPad" on a shared screen. iOS no longer tells apps the name the
    /// owner gave the device, so the app makes its own.
    func name(me person: Person?) -> String {
        if let customName { return customName }
        if role == .personal, let person { return "\(person.name)'s \(model)" }
        return "Shared \(model)"
    }

    /// Names the device; a blank name goes back to the one the app makes.
    func setName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        customName = trimmed.isEmpty ? nil : String(trimmed.prefix(Names.limit))
        defaults.set(customName, forKey: Self.nameKey)
    }

    /// Who this device belongs to in a household, if it has been said.
    func me(in householdId: Household.ID) -> Person.ID? {
        me[householdId]
    }

    /// Says who this device belongs to in a household; nil forgets it.
    func setMe(_ personId: Person.ID?, in householdId: Household.ID) {
        me[householdId] = personId
        Self.store(me: personId, in: householdId, defaults: defaults)
    }

    // MARK: Storage

    /// Writes "me" without a live settings object, for debug launches that run first.
    static func store(me personId: Person.ID?, in householdId: Household.ID, defaults: UserDefaults = .standard) {
        let key = mePrefix + householdId.description
        if let personId {
            defaults.set(personId.description, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Forgets who this device belongs to in every household (sample and reset launches
    /// replace the household, so the old answers point at nothing).
    static func forgetMe(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(mePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Forgets this device's name and role, for sample and reset launches.
    static func forgetNameAndRole(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: roleKey)
    }

    private static func storedMe(in defaults: UserDefaults) -> [Household.ID: Person.ID] {
        var result: [Household.ID: Person.ID] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(mePrefix) {
            guard let text = value as? String,
                  let household = Household.ID(String(key.dropFirst(mePrefix.count))),
                  let person = Person.ID(text) else { continue }
            result[household] = person
        }
        return result
    }
}
