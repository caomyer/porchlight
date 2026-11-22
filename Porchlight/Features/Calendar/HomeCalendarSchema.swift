import CryptoKit
import Foundation
import GRDB

// The home calendar and who an event is for (docs/design/calendar-add-edit.md, "The home
// calendar", "For whom", "Records").

// MARK: - Tables

extension SyncSchema {
    /// The tables "calendar v4" adds, both under the household.
    static let homeCalendarTables: [Table] = [
        Table(name: "homeCalendar", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "title" TEXT NOT NULL, "accountKind" TEXT NOT NULL,
            "chosenById" TEXT, "chosenAt" TEXT NOT NULL
            """),
        Table(name: "eventFor", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "matchKey" TEXT NOT NULL, "titleKey" TEXT,
            "occurrenceStart" TEXT NOT NULL, "personIds" TEXT NOT NULL DEFAULT '', "setById" TEXT, "setAt" TEXT NOT NULL
            """),
        // Which of this device's events (by local id) a "For" was set on; never synced.
        Table(name: "calendarItemFor", synced: false, columns: """
            "itemId" TEXT PRIMARY KEY NOT NULL, "eventForId" TEXT NOT NULL
            """),
    ]
}

extension AppDatabase {
    static let homeCalendarMigration = "calendar v4: the home calendar, and who an event is for"
    static let ownerChosenMigration = "calendar v5: whether a calendar's owner was picked here"

    /// Adds the household's home calendar and who each event is for, this device's half of the
    /// home calendar, and which of this device's events a "For" was set on.
    static func registerHomeCalendarMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(homeCalendarMigration) { db in
            for table in SyncSchema.homeCalendarTables {
                try db.execute(sql: "CREATE TABLE \"\(table.name)\" (\(table.columns)) STRICT")
            }
            try db.execute(sql: """
                CREATE INDEX "homeCalendar_on_householdId" ON "homeCalendar"("householdId");
                CREATE INDEX "eventFor_on_householdId" ON "eventFor"("householdId");
                CREATE INDEX "eventFor_on_matchKey" ON "eventFor"("matchKey");
                ALTER TABLE "calendarSource" ADD COLUMN "isHome" INTEGER NOT NULL DEFAULT 0;
                """)
        }
        // On this device only (calendarSource is never synced): no iCloud schema change.
        migrator.registerMigration(ownerChosenMigration) { db in
            try db.execute(sql: #"ALTER TABLE "calendarSource" ADD COLUMN "ownerChosen" INTEGER NOT NULL DEFAULT 0"#)
        }
    }
}

// MARK: - Records

/// The household's home calendar, named by what every device can see of it.
struct HomeCalendar: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<HomeCalendar>

    var id: ID
    var householdId: Household.ID
    var title: String
    var accountKind: String
    var chosenById: Device.ID?
    var chosenAt: Date

    static func id(householdId: Household.ID) -> ID { .derived(householdId.description, "homeCalendar") }
}

/// Who an event is for: the household's own fact about a real event, one per series.
struct EventFor: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<EventFor>

    var id: ID
    var householdId: Household.ID
    /// The event's match key (`CalendarPassOn.matchKey`).
    var matchKey: String
    /// The fallback while a new event's shared id settles; nil on a Busy only event.
    var titleKey: String?
    /// The start of the occurrence it was set on, for the fallback.
    var occurrenceStart: Date
    /// Comma-separated person ids; empty is everyone.
    var personIds: String
    var setById: Device.ID?
    var setAt: Date

    static func id(householdId: Household.ID, matchKey: String) -> ID { .derived(householdId.description, "eventFor", matchKey) }

    var people: [Person.ID] {
        personIds.split(separator: ",").compactMap { Person.ID(String($0)) }
    }

    var owners: [Owner] {
        let people = people
        return people.isEmpty ? [.everyone] : people.map(Owner.person)
    }

    /// A key of an event's title, of no use outside the household: a hash of the title,
    /// lowercased and trimmed, with the household's id.
    static func titleKey(_ title: String, householdId: Household.ID) -> String? {
        let words = title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !words.isEmpty else { return nil }
        return SHA256.hash(data: Data("\(householdId)|\(words)".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
