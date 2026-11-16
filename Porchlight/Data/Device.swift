import Foundation
import GRDB

/// One install that has opened the household: "James's iPhone", "Hallway iPad".
///
/// Each device writes only its own row (and the owner may delete one when removing
/// someone), so the household can see who has the app and where a row came from
/// (docs/design/households.md, "The `device` table").
struct Device: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<Device>

    /// Derived from the household and the install (`Device.id(householdId:install:)`), so an
    /// install has exactly one row per household however often it writes it.
    var id: ID
    var householdId: Household.ID
    var name: String
    var role: DeviceRole
    /// The kind of device, "iPhone" or "iPad": only words ("from Mia's phone").
    var model: String?
    /// Whose device it is, on a personal device. A plain id.
    var personId: Person.ID?
    /// The iCloud user's record name, to match the device to a participant of the share.
    var userName: String?
    var createdAt: Date
    /// The last time it was used, written at most once a day.
    var seenAt: Date

    static func id(householdId: Household.ID, install: String) -> ID {
        .derived(householdId.description, install)
    }

    /// The person it belongs to, when it is someone's own device.
    var owner: Person.ID? { role == .personal ? personId : nil }

    /// "phone" or "iPad", for "from Mia's phone".
    var kindWord: String {
        model == "iPhone" ? "phone" : (model ?? "device")
    }
}

/// This install's own random id, made once and kept on the device. With a household's id
/// it names the device's row in that household.
enum DeviceInstall {
    static let key = "device.installId"

    static func id(defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: key) { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: key)
        return id
    }
}

extension DeviceRole: Codable, DatabaseValueConvertible {
    /// A role written by a newer version that this one doesn't know reads as a shared
    /// screen, which never credits anyone by mistake.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DeviceRole(rawValue: raw) ?? .sharedScreen
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var databaseValue: DatabaseValue { rawValue.databaseValue }

    static func fromDatabaseValue(_ dbValue: DatabaseValue) -> DeviceRole? {
        String.fromDatabaseValue(dbValue).map { DeviceRole(rawValue: $0) ?? .sharedScreen }
    }
}

/// What this device remembers about itself in its own database, never synced: which
/// household it shows, and the token that tells whether the database was replaced.
///
/// It is a table rather than UserDefaults so "which household?" is answered inside the
/// same transaction as every other read, and observations update when it changes.
enum DeviceState {
    enum Key: String {
        case currentHouseholdId
        /// The current household's name, kept so a household that leaves can still be named.
        case currentHouseholdName
        /// Changes on every launch; compared with UserDefaults (`DatabaseIdentity`).
        case databaseToken
    }

    /// Who owns a household this device joined, so it can say who removed it.
    static func ownerKey(_ householdId: Household.ID) -> String { "owner.\(householdId)" }

    static func value(_ key: String, _ db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM deviceState WHERE key = ?", arguments: [key])
    }

    static func value(_ key: Key, _ db: Database) throws -> String? {
        try value(key.rawValue, db)
    }

    static func set(_ key: String, _ value: String?, _ db: Database) throws {
        if let value {
            try db.execute(sql: "INSERT OR REPLACE INTO deviceState (key, value) VALUES (?, ?)", arguments: [key, value])
        } else {
            try db.execute(sql: "DELETE FROM deviceState WHERE key = ?", arguments: [key])
        }
    }

    static func set(_ key: Key, _ value: String?, _ db: Database) throws {
        try set(key.rawValue, value, db)
    }
}
