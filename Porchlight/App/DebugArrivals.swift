#if DEBUG
import Foundation
import GRDB

/// `-debugArrival` (with `-sampleHousehold`): James and Mia have phones, what Mia pitched in
/// on today and today's meals came from Mia's, and a few seconds after launch a walk arrives from James's phone, so the wall
/// shows its tags, the glow and the toast (journey D1) without a second device.
enum DebugArrivals {
    @MainActor
    static func start(_ arguments: [String], database: AppDatabase) {
        guard AppFiles.isSandboxed, arguments.contains("-debugArrival") else { return }
        guard let (james, _) = try? seedPhones(database) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            try? arriveWalk(database, from: james)
        }
    }

    /// The two phones, and Mia's chores and today's meals tagged as from her phone.
    private static func seedPhones(_ database: AppDatabase) throws -> (james: Device, mia: Device)? {
        let snapshot = try database.snapshot()
        guard let household = snapshot.household,
              let james = snapshot.people.first(where: { $0.name == "James" }),
              let mia = snapshot.people.first(where: { $0.name == "Mia" }) else { return nil }
        let now = Date.now
        func phone(_ person: Person) -> Device {
            Device(
                id: Device.id(householdId: household.id, install: "debug-\(person.name)"), householdId: household.id,
                name: "\(person.name.possessive) iPhone", role: .personal, model: "iPhone", personId: person.id,
                userName: "_\(person.name.lowercased())", createdAt: now, seenAt: now
            )
        }
        let phones = (phone(james), phone(mia))
        let today = DayKey(now, calendar: household.calendar)
        try database.writer.write { db in
            try phones.0.save(db)
            try phones.1.save(db)
            try db.execute(sql: "UPDATE journalEntry SET deviceId = ? WHERE day = ?", arguments: [phones.1.id, today.rawValue])
            try db.execute(
                sql: "UPDATE choreCompletion SET deviceId = ? WHERE day = ? AND personId = ?",
                arguments: [phones.1.id, today.rawValue, mia.id]
            )
        }
        return phones
    }

    /// A walk James logs on his phone, as sync would write it.
    private static func arriveWalk(_ database: AppDatabase, from phone: Device) throws {
        try database.writer.write { db in
            guard let walk = try CareRoutine.filter(Column("kind") == CareKind.walk.rawValue).order(Column("sortOrder")).fetchOne(db),
                  let james = phone.personId else { return }
            let now = Date.now
            let log = CareLog(careRoutineId: walk.id, occurredAt: now, stars: walk.stars, createdAt: now, deviceId: phone.id)
            try log.insert(db)
            try CareLogPerson(careLogId: log.id, personId: james).insert(db)
        }
    }
}
#endif
