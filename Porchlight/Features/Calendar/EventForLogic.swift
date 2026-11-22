import Foundation
import GRDB

// Who an event is for, kept on its event when the id iOS shares changes
// (docs/design/calendar-add-edit.md, "Keeping "For" on its event when the id changes").

enum EventForLogic {
    /// The record for an event: by its match key, else, while a new event's key settles, by
    /// its title key and start. A Busy only event has no title to key.
    static func record(
        for event: CalendarEvent, in records: [EventFor], householdId: Household.ID
    ) -> EventFor? {
        if let key = event.matchKey, let found = records.first(where: { $0.matchKey == key }) { return found }
        guard !event.isBusy, let titleKey = EventFor.titleKey(event.title, householdId: householdId) else { return nil }
        let start = CalendarPassOn.milliseconds(event.start)
        return records.first { $0.titleKey == titleKey && CalendarPassOn.milliseconds($0.occurrenceStart) == start }
    }

    /// Events with their "For" in place of their calendar's owner.
    static func apply(_ records: [EventFor], to events: [CalendarEvent], householdId: Household.ID) -> [CalendarEvent] {
        guard !records.isEmpty else { return events }
        return events.map { event in
            guard let found = record(for: event, in: records, householdId: householdId) else { return event }
            var event = event
            let owners = found.owners
            event.owner = owners[0]
            event.alsoFor = Array(owners.dropFirst())
            return event
        }
    }

    /// The local id of an occurrence ("item@start" is how a provider names it).
    static func itemId(ofOccurrence id: String) -> String {
        id.split(separator: "@", maxSplits: 1).first.map(String.init) ?? id
    }
}

extension AppDatabase {
    /// Sets who an event is for, for the whole household. On a device that has the event, its
    /// local id is remembered beside the record, so the record follows the event if its
    /// shared id changes. An empty `people` is everyone, and removes the record.
    func setEventFor(
        matchKey: String, title: String?, start: Date, itemId: String?, people: [Person.ID],
        householdId: Household.ID, now: Date = .now
    ) throws {
        try writer.write { db in
            let id = EventFor.id(householdId: householdId, matchKey: matchKey)
            if people.isEmpty {
                _ = try EventFor.deleteOne(db, id: id)
                try db.execute(sql: "DELETE FROM calendarItemFor WHERE eventForId = ?", arguments: [id])
                return
            }
            try EventFor(
                id: id, householdId: householdId, matchKey: matchKey,
                titleKey: title.flatMap { EventFor.titleKey($0, householdId: householdId) },
                occurrenceStart: CalendarPassOn.milliseconds(start),
                personIds: people.map(\.description).joined(separator: ","),
                setById: thisDeviceId(in: householdId), setAt: now
            ).save(db)
            if let itemId {
                try db.execute(sql: "INSERT OR REPLACE INTO calendarItemFor (itemId, eventForId) VALUES (?, ?)", arguments: [itemId, id])
            }
        }
    }

    /// Moves a record to a new match key: written under its new id with its people, the old
    /// one removed, in one write, and this device's memory of it moved too.
    static func rekeyEventFor(from old: String, to new: String, householdId: Household.ID, db: Database) throws {
        guard old != new else { return }
        let oldId = EventFor.id(householdId: householdId, matchKey: old)
        guard var record = try EventFor.fetchOne(db, id: oldId) else { return }
        let newId = EventFor.id(householdId: householdId, matchKey: new)
        _ = try EventFor.deleteOne(db, id: oldId)
        // A record already under the new key (set on another device meanwhile) stands.
        guard try !EventFor.exists(db, id: newId) else {
            try db.execute(sql: "UPDATE calendarItemFor SET eventForId = ? WHERE eventForId = ?", arguments: [newId, oldId])
            return
        }
        record.id = newId
        record.matchKey = new
        try record.insert(db)
        try db.execute(sql: "UPDATE calendarItemFor SET eventForId = ? WHERE eventForId = ?", arguments: [newId, oldId])
    }

    /// Re-keys every record set on one of this device's events whose shared id has moved:
    /// `current` is each of its events' local id and match key now.
    static func rekeyRemembered(current: [String: String], householdId: Household.ID, db: Database) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT itemId, eventForId FROM calendarItemFor")
        for row in rows {
            let itemId: String = row["itemId"]
            guard let key = current[itemId],
                  let forId = EventFor.ID(row["eventForId"] as String),
                  let record = try EventFor.fetchOne(db, id: forId), record.householdId == householdId,
                  record.matchKey != key else { continue }
            try rekeyEventFor(from: record.matchKey, to: key, householdId: householdId, db: db)
        }
    }

    func eventFors(householdId: Household.ID) throws -> [EventFor] {
        try writer.read { try EventFor.filter(Column("householdId") == householdId).fetchAll($0) }
    }
}
