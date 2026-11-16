import Foundation
import GRDB

/// What this device says about itself in its row.
struct ThisDevice: Hashable, Sendable {
    var name: String
    var role: DeviceRole
    var model: String
    var personId: Person.ID?
    /// The iCloud user's record name, once sync has read it.
    var userName: String?
}

extension AppDatabase {
    // MARK: This device

    /// This device's row in a household.
    func thisDeviceId(in householdId: Household.ID) -> Device.ID {
        Device.id(householdId: householdId, install: installId)
    }

    /// The device every row written now is stamped with: this device's row in the current
    /// household. Every write path that adds a stamped row calls it once, inside its own
    /// transaction (docs/design/households.md, "Where a row came from").
    func stamp(_ db: Database) throws -> Device.ID? {
        try Household.current(db).map { thisDeviceId(in: $0.id) }
    }

    /// Writes this device's row in a household: when it opens the household, and whenever
    /// its name, role, person or account changes. `seenAt` moves at most once a day, so an
    /// unchanged device writes (and uploads) nothing more than that.
    func saveThisDevice(_ device: ThisDevice, in householdId: Household.ID, now: Date = .now) throws {
        try writer.write { db in
            guard let household = try Household.fetchOne(db, id: householdId) else { return }
            let id = thisDeviceId(in: householdId)
            let existing = try Device.fetchOne(db, id: id)
            var row = existing ?? Device(
                id: id, householdId: householdId, name: device.name, role: device.role,
                createdAt: now, seenAt: now
            )
            row.name = device.name
            row.role = device.role
            row.model = device.model
            row.personId = device.role == .personal ? device.personId : nil
            // Offline the account can't be read; keep what was known.
            row.userName = device.userName ?? row.userName
            let calendar = household.calendar
            if !calendar.isDate(row.seenAt, inSameDayAs: now) { row.seenAt = now }
            guard row != existing else { return }
            try row.save(db)
        }
    }

    /// Removes the devices of one iCloud user from a household, when the owner removes them
    /// from the share. Their person and history stay.
    func removeDevices(ofUser userName: String, in householdId: Household.ID) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM device WHERE householdId = ? AND userName = ?",
                arguments: [householdId, userName]
            )
        }
    }

    // MARK: The current household

    /// Remembers which household this device shows, and its name, so a household that
    /// later leaves can still be named. The first household a device has becomes current;
    /// a chosen one that left stays chosen until the person has seen that it left.
    func rememberCurrentHousehold() throws {
        try writer.write { db in
            let chosen = try DeviceState.value(.currentHouseholdId, db).flatMap(Household.ID.init)
            if let chosen, try !Household.exists(db, id: chosen) { return }
            guard let household = try Household.current(db) else { return }
            if chosen != household.id {
                try DeviceState.set(.currentHouseholdId, household.id.description, db)
            }
            if try DeviceState.value(.currentHouseholdName, db) != household.name {
                try DeviceState.set(.currentHouseholdName, household.name, db)
            }
        }
    }

    /// Shows this household from now on: the newest accepted invite becomes current.
    func chooseHousehold(_ id: Household.ID) throws {
        try writer.write { db in
            guard let household = try Household.fetchOne(db, id: id) else { return }
            try DeviceState.set(.currentHouseholdId, id.description, db)
            try DeviceState.set(.currentHouseholdName, household.name, db)
        }
    }

    /// Forgets the chosen household: after the person has seen that it left, or before this
    /// device removes it itself, so that is never taken for being removed by someone else.
    /// The oldest household left, if any, becomes current.
    func forgetCurrentHousehold() throws {
        try writer.write { db in
            try DeviceState.set(.currentHouseholdId, nil, db)
            try DeviceState.set(.currentHouseholdName, nil, db)
        }
    }

    /// Remembers whose iCloud holds a household this device joins, to name them if they
    /// remove it later.
    func rememberOwner(_ name: String?, of householdId: Household.ID) throws {
        try writer.write { db in
            try DeviceState.set(DeviceState.ownerKey(householdId), name, db)
        }
    }
}
