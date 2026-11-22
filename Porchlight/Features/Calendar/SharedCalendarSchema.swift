import Foundation
import GRDB

// The shared calendar (docs/design/calendar-shared.md): each device passes on the calendars
// chosen on it, under its own `device` row, as a feed, its calendars and their occurrences.

// MARK: - Tables

extension SyncSchema {
    /// The tables "calendar v3" adds. A device writes only under its own `device` row, so no
    /// two devices write the same row; removing the device removes everything it passed on.
    static let calendarTables: [Table] = [
        Table(name: "calendarFeed", parent: "device", columns: """
            \(id), \(parent("deviceId", "device")), "passedOnAt" TEXT NOT NULL, "passedOnBy" TEXT NOT NULL,
            "windowStart" TEXT NOT NULL, "windowEnd" TEXT NOT NULL, "eventCount" INTEGER NOT NULL DEFAULT 0
            """),
        Table(name: "sharedCalendar", parent: "calendarFeed", columns: """
            \(id), \(parent("feedId", "calendarFeed")), "title" TEXT NOT NULL DEFAULT '', "accountKind" TEXT NOT NULL,
            "colorHex" INTEGER NOT NULL, "ownerId" TEXT, "choice" TEXT NOT NULL
            """),
        Table(name: "sharedEvent", parent: "sharedCalendar", columns: """
            \(id), \(parent("sharedCalendarId", "sharedCalendar")), "matchKey" TEXT, "title" TEXT, "location" TEXT,
            "notes" TEXT, "start" TEXT NOT NULL, "end" TEXT NOT NULL, "isAllDay" INTEGER NOT NULL DEFAULT 0
            """),
    ]
}

extension AppDatabase {
    static let sharedCalendarMigration = "calendar v3: the shared calendar, and four choices per calendar"

    /// Adds the shared calendar's tables, and each calendar's choice on this device, from
    /// what it had: "Just me" stays Just me, busy becomes Busy only, the rest Show everything.
    static func registerSharedCalendarMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(sharedCalendarMigration) { db in
            for table in SyncSchema.calendarTables {
                try db.execute(sql: "CREATE TABLE \"\(table.name)\" (\(table.columns)) STRICT")
            }
            try db.execute(sql: """
                CREATE INDEX "calendarFeed_on_deviceId" ON "calendarFeed"("deviceId");
                CREATE INDEX "sharedCalendar_on_feedId" ON "sharedCalendar"("feedId");
                CREATE INDEX "sharedEvent_on_sharedCalendarId" ON "sharedEvent"("sharedCalendarId");
                CREATE INDEX "sharedEvent_on_start" ON "sharedEvent"("start");
                ALTER TABLE "calendarSource" ADD COLUMN "sharing" TEXT NOT NULL DEFAULT 'everything';
                UPDATE "calendarSource" SET "sharing" = CASE
                    WHEN "isPersonal" = 1 THEN 'justMe'
                    WHEN "visibility" = 'busy' THEN 'busy'
                    ELSE 'everything' END;
                """)
        }
    }
}

// MARK: - The four choices

/// What the household gets from one of this device's calendars.
enum CalendarChoice: String, Codable, CaseIterable, Identifiable, Sendable, DatabaseValueConvertible {
    /// Titles, places, notes and times.
    case everything
    /// The same, shown to the household as one soft block per person per day.
    case quiet
    /// Times only: the title, place and notes never leave the device.
    case busy
    /// Nothing leaves the device.
    case justMe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everything: "Show everything"
        case .quiet: "Keep it quiet"
        case .busy: "Busy only"
        case .justMe: "Just me"
        }
    }

    /// One line for the choice, where it is picked.
    var explanation: String {
        switch self {
        case .everything: "Everyone sees the events."
        case .quiet: "Everyone sees one block a day, like \"at work until 5:30\", with the events a tap away."
        case .busy: "Everyone sees the times, without titles, places or notes."
        case .justMe: "Nothing leaves this device."
        }
    }

    /// Whether anything of the calendar is passed on.
    var passesOn: Bool { self != .justMe }
}

// MARK: - Records

/// One device's calendars, as passed on: when, why, the window and how many events.
struct CalendarFeed: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<CalendarFeed>

    var id: ID
    var deviceId: Device.ID
    var passedOnAt: Date
    var passedOnBy: CalendarPassTrigger
    var windowStart: Date
    var windowEnd: Date
    var eventCount: Int

    static func id(deviceId: Device.ID) -> ID { .derived(deviceId.description, "calendarFeed") }
}

/// Why a device passed its calendars on: for reading off how fresh real devices keep it.
enum CalendarPassTrigger: String, Codable, Sendable, DatabaseValueConvertible {
    /// The calendars changed on the device.
    case change
    /// The app came to the front, or launched.
    case open
    /// iOS gave the app a background refresh.
    case background
    /// The day turned, or the wall's hourly pass.
    case day
    /// A calendar's choice changed.
    case choice

    var words: String {
        switch self {
        case .change: "a calendar changed"
        case .open: "opened"
        case .background: "in the background"
        case .day: "on schedule"
        case .choice: "a choice changed"
        }
    }
}

/// A calendar as passed on. Its id is derived from the device and the calendar's id there.
struct SharedCalendar: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<SharedCalendar>

    var id: ID
    var feedId: CalendarFeed.ID
    /// '' for Busy only.
    var title: String
    /// A word for where it comes from, never an address.
    var accountKind: String
    var colorHex: Int
    /// A plain id: nil is the whole household.
    var ownerId: Person.ID?
    var choice: CalendarChoice

    static func id(deviceId: Device.ID, calendarId: String) -> ID { .derived(deviceId.description, "sharedCalendar", calendarId) }

    var owner: Owner { ownerId.map(Owner.person) ?? .everyone }
}

/// One occurrence as passed on. Its id is derived from its calendar's row and the
/// occurrence, so an unchanged event is the same row from one pass to the next.
struct SharedEvent: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<SharedEvent>

    var id: ID
    var sharedCalendarId: SharedCalendar.ID
    /// A hash of the event's id across devices, to show one invite once.
    var matchKey: String?
    /// nil for Busy only.
    var title: String?
    var location: String?
    var notes: String?
    var start: Date
    var end: Date
    var isAllDay: Bool

    static func id(sharedCalendarId: SharedCalendar.ID, occurrence: String) -> ID {
        .derived(sharedCalendarId.description, "sharedEvent", occurrence)
    }
}
