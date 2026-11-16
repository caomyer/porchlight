import Foundation
import GRDB

extension AppDatabase {
    /// Calendar tables. Append new migrations; never edit a shipped one.
    static func registerCalendarMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("calendar v1: calendar sources") { db in
            // One row per external calendar this household has seen: who it
            // belongs to and how it shows on the wall.
            try db.create(table: "calendarSource") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("household", onDelete: .cascade).notNull()
                t.column("externalId", .text).notNull()
                t.column("title", .text).notNull()
                t.column("account", .text).notNull()
                t.column("colorHex", .integer).notNull()
                // NULL means the whole household ("Both").
                t.belongsTo("owner", inTable: "person", onDelete: .setNull)
                t.column("visibility", .text).notNull()
                t.column("isShown", .boolean).notNull()
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["householdId", "externalId"])
            }
        }
    }
}

extension AppDatabase {
    /// Calendar changes made after "sync v1" rebuilt the table. Append new ones.
    static func registerCalendarMigrationsAfterSync(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("calendar v2: just me") { db in
            // A phone's own calendar can be kept to that phone ("Just me"). The table is
            // STRICT, so the flag is an INTEGER.
            try db.execute(sql: #"ALTER TABLE calendarSource ADD COLUMN "isPersonal" INTEGER NOT NULL DEFAULT 0"#)
        }
    }
}

// MARK: - Records

/// How much of a calendar's events the wall reveals.
enum CalendarVisibility: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    /// Title, time, place and notes.
    case full
    /// Only "Busy" and the time. Handy for work calendars.
    case busy

    var label: String {
        switch self {
        case .full: "Full details"
        case .busy: "Busy only"
        }
    }
}

/// The household's settings for one external calendar.
struct CalendarSource: Codable, Equatable, Identifiable, Sendable {
    typealias ID = Porchlight.ID<CalendarSource>

    var id: ID = .new()
    var householdId: Household.ID
    /// The provider's stable calendar identifier.
    var externalId: String
    var title: String
    /// Where it comes from, e.g. "Google · james@example.com".
    var account: String
    /// The calendar's own color as 0xRRGGBB.
    var colorHex: Int
    /// The person it belongs to, or nil for the whole household.
    var ownerId: Person.ID?
    var visibility: CalendarVisibility
    var isShown: Bool
    var createdAt: Date
    /// Kept to this device ("Just me"), never shown to the household. Calendars are only
    /// read on the device that has them today, so this matters once mappings sync.
    var isPersonal = false

    var owner: Owner { ownerId.map(Owner.person) ?? .everyone }

    /// How the phone's Calendars page describes the calendar's sharing.
    var sharing: CalendarSharing {
        if isPersonal { return .justMe }
        return visibility == .busy ? .busyOnly : .household
    }
}

/// What someone chooses for one of their calendars on the phone: shared with the
/// household in full, shared as busy only, or kept to this device.
enum CalendarSharing: String, CaseIterable, Identifiable, Sendable {
    case household, busyOnly, justMe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .household: "Household"
        case .busyOnly: "Busy only"
        case .justMe: "Just me"
        }
    }

    /// The source's settings for this choice.
    func apply(to source: inout CalendarSource) {
        source.isPersonal = self == .justMe
        source.visibility = self == .busyOnly ? .busy : .full
    }
}

extension CalendarSource: FetchableRecord, PersistableRecord {
    static let databaseTableName = "calendarSource"
}

// MARK: - Writes

enum CalendarSourceError: Error, Equatable, LocalizedError {
    case unknownCalendar
    case ownerNotInHousehold

    var errorDescription: String? {
        switch self {
        case .unknownCalendar: "That calendar is no longer available."
        case .ownerNotInHousehold: "Pick someone who lives here."
        }
    }
}

extension AppDatabase {
    /// Makes sure every calendar the provider knows has a source row.
    ///
    /// New calendars default to shown, full details and a guessed owner.
    /// Existing rows keep the household's choices; only their title, account
    /// and color follow the provider. Rows for calendars that disappeared are
    /// kept, so choices survive an account being removed and re-added.
    func syncCalendarSources(householdId: Household.ID, calendars: [ExternalCalendar], now: Date = .now) throws {
        guard !calendars.isEmpty else { return }
        try writer.write { db in
            let people = try Person.active(in: householdId).fetchAll(db)
            let existing = try CalendarSource
                .filter(Column("householdId") == householdId)
                .fetchAll(db)
            let byExternalId = Dictionary(existing.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
            for calendar in calendars {
                if var source = byExternalId[calendar.id] {
                    guard source.title != calendar.title || source.account != calendar.account || source.colorHex != calendar.colorHex else { continue }
                    source.title = calendar.title
                    source.account = calendar.account
                    source.colorHex = calendar.colorHex
                    try source.update(db)
                } else {
                    let source = CalendarSource(
                        householdId: householdId,
                        externalId: calendar.id,
                        title: calendar.title,
                        account: calendar.account,
                        colorHex: calendar.colorHex,
                        ownerId: CalendarOwnerGuess.owner(for: calendar, people: people),
                        visibility: .full,
                        isShown: true,
                        createdAt: now
                    )
                    try source.insert(db)
                }
            }
        }
    }

    /// Assigns a calendar to a person, or to everyone with `.everyone`.
    func setCalendarSourceOwner(id: CalendarSource.ID, owner: Owner) throws {
        try writer.write { db in
            guard var source = try CalendarSource.fetchOne(db, id: id) else { throw CalendarSourceError.unknownCalendar }
            switch owner {
            case .everyone:
                source.ownerId = nil
            case let .person(personId):
                guard let person = try Person.fetchOne(db, id: personId), person.householdId == source.householdId else {
                    throw CalendarSourceError.ownerNotInHousehold
                }
                source.ownerId = personId
            }
            try source.update(db)
        }
    }

    func setCalendarSourceVisibility(id: CalendarSource.ID, visibility: CalendarVisibility) throws {
        try updateCalendarSource(id: id) { $0.visibility = visibility }
    }

    func setCalendarSourceSharing(id: CalendarSource.ID, sharing: CalendarSharing) throws {
        try updateCalendarSource(id: id) { sharing.apply(to: &$0) }
    }

    func setCalendarSourceShown(id: CalendarSource.ID, isShown: Bool) throws {
        try updateCalendarSource(id: id) { $0.isShown = isShown }
    }

    private func updateCalendarSource(id: CalendarSource.ID, _ change: (inout CalendarSource) -> Void) throws {
        try writer.write { db in
            guard var source = try CalendarSource.fetchOne(db, id: id) else { throw CalendarSourceError.unknownCalendar }
            change(&source)
            try source.update(db)
        }
    }
}

// MARK: - Reads

/// What the calendar store needs from the database, read consistently.
struct CalendarSnapshot: Equatable, Sendable {
    var household: Household?
    var people: [Person]
    var sources: [CalendarSource]

    static let empty = CalendarSnapshot(household: nil, people: [], sources: [])

    static func fetch(_ db: Database) throws -> CalendarSnapshot {
        let base = try HouseholdSnapshot.fetch(db)
        guard let id = base.household?.id else { return .empty }
        let sources = try CalendarSource
            .filter(Column("householdId") == id)
            .order(Column("createdAt"), Column("id"))
            .fetchAll(db)
        return CalendarSnapshot(household: base.household, people: base.people, sources: sources)
    }
}

extension AppDatabase {
    func calendarSnapshot() throws -> CalendarSnapshot {
        try writer.read(CalendarSnapshot.fetch)
    }

    func calendarUpdates() -> AsyncValueObservation<CalendarSnapshot> {
        ValueObservation
            .tracking(CalendarSnapshot.fetch)
            .removeDuplicates()
            .values(in: writer)
    }
}
