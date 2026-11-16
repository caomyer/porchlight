/// The table definitions "sync v1" builds, parents before children
/// (see docs/design/sync-foundation.md, "Table definitions"), and the photo tables
/// "sync v2" adds.
///
/// Later migrations may add nullable or defaulted columns, never rename or remove one.
/// "sync v2" removed the photo file names from `companion` and `journalEntryPhoto`, the
/// last removal allowed: sync had never been on anywhere then.
enum SyncSchema {
    struct Table {
        var name: String
        /// The parent every row hangs off; nil for the household, the root.
        var parent: String?
        /// Device-local tables never sync, so they keep their unique constraints and
        /// second foreign keys.
        var synced = true
        var columns: String
    }

    /// Every id column: a lowercase UUID, which SQLiteData and CloudKit record names expect.
    static let id = #""id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())"#

    private static func parent(_ column: String, _ table: String) -> String {
        #""\#(column)" TEXT NOT NULL REFERENCES "\#(table)"("id") ON DELETE CASCADE"#
    }

    static let tables: [Table] = [
        Table(name: "household", columns: """
            \(id), "name" TEXT NOT NULL, "timeZoneIdentifier" TEXT NOT NULL, "firstWeekday" INTEGER NOT NULL,
            "createdAt" TEXT NOT NULL, "setupCompleted" INTEGER NOT NULL DEFAULT 1
            """),
        Table(name: "person", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "name" TEXT NOT NULL, "color" TEXT NOT NULL,
            "sortOrder" INTEGER NOT NULL, "createdAt" TEXT NOT NULL, "archivedAt" TEXT
            """),
        Table(name: "calendarSource", parent: "household", synced: false, columns: """
            \(id), \(parent("householdId", "household")), "externalId" TEXT NOT NULL, "title" TEXT NOT NULL,
            "account" TEXT NOT NULL, "colorHex" INTEGER NOT NULL,
            "ownerId" TEXT REFERENCES "person"("id") ON DELETE SET NULL,
            "visibility" TEXT NOT NULL, "isShown" INTEGER NOT NULL, "createdAt" TEXT NOT NULL,
            UNIQUE ("householdId", "externalId")
            """),
        Table(name: "companion", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "name" TEXT NOT NULL, "species" TEXT NOT NULL,
            "coat" TEXT NOT NULL, "photoFile" TEXT, "about" TEXT NOT NULL DEFAULT '', "birthDate" TEXT,
            "captionTone" TEXT NOT NULL, "sortOrder" INTEGER NOT NULL, "createdAt" TEXT NOT NULL
            """),
        Table(name: "careRoutine", parent: "companion", columns: """
            \(id), \(parent("companionId", "companion")), "kind" TEXT NOT NULL, "title" TEXT NOT NULL,
            "emoji" TEXT NOT NULL, "everyDays" INTEGER NOT NULL DEFAULT 1, "windows" TEXT NOT NULL,
            "trackedFields" TEXT NOT NULL, "stars" INTEGER NOT NULL DEFAULT 0, "nudgeAfterMinutes" INTEGER,
            "sortOrder" INTEGER NOT NULL, "repeatKind" TEXT NOT NULL DEFAULT 'daily',
            "weekdayMask" INTEGER NOT NULL DEFAULT 0, "anchorDay" TEXT NOT NULL DEFAULT ''
            """),
        Table(name: "careLog", parent: "careRoutine", columns: """
            \(id), \(parent("careRoutineId", "careRoutine")), "occurredAt" TEXT NOT NULL, "durationMinutes" INTEGER,
            "pee" INTEGER, "poo" INTEGER, "vibe" TEXT, "note" TEXT, "stars" INTEGER NOT NULL DEFAULT 0,
            "createdAt" TEXT NOT NULL
            """),
        Table(name: "careLogPerson", parent: "careLog", columns: """
            \(id), \(parent("careLogId", "careLog")), "personId" TEXT NOT NULL
            """),
        Table(name: "journal", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "kind" TEXT NOT NULL, "title" TEXT NOT NULL,
            "enabled" INTEGER NOT NULL DEFAULT 1, "slots" TEXT NOT NULL, "createdAt" TEXT NOT NULL
            """),
        Table(name: "foodPlace", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "name" TEXT NOT NULL, "address" TEXT, "latitude" REAL,
            "longitude" REAL, "category" TEXT, "phone" TEXT, "url" TEXT, "mapsId" TEXT, "createdAt" TEXT NOT NULL
            """),
        Table(name: "journalEntry", parent: "journal", columns: """
            \(id), \(parent("journalId", "journal")), "day" TEXT NOT NULL, "slot" TEXT NOT NULL,
            "source" TEXT NOT NULL, "title" TEXT NOT NULL, "emoji" TEXT, "tint" INTEGER,
            "rating" INTEGER CHECK (("rating" IS NULL) OR (("rating" >= 1) AND ("rating" <= 4))),
            "eatenAt" TEXT NOT NULL, "createdAt" TEXT NOT NULL, "placeId" TEXT
            """),
        Table(name: "journalEntryEater", parent: "journalEntry", columns: """
            \(id), \(parent("entryId", "journalEntry")), "personId" TEXT NOT NULL
            """),
        Table(name: "journalEntryPhoto", parent: "journalEntry", columns: """
            \(id), \(parent("entryId", "journalEntry")), "photoFile" TEXT NOT NULL, "thumbnailFile" TEXT NOT NULL,
            "sortOrder" INTEGER NOT NULL, "createdAt" TEXT NOT NULL, "cropX" REAL, "cropY" REAL,
            "cropWidth" REAL, "cropHeight" REAL
            """),
        Table(name: "journalPage", parent: "journal", columns: """
            \(id), \(parent("journalId", "journal")), "day" TEXT NOT NULL, "drawing" BLOB NOT NULL,
            "updatedAt" TEXT NOT NULL
            """),
        Table(name: "chore", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "title" TEXT NOT NULL, "emoji" TEXT, "ownerId" TEXT,
            "repeatKind" TEXT NOT NULL, "weekdayMask" INTEGER NOT NULL DEFAULT 0,
            "intervalDays" INTEGER NOT NULL DEFAULT 1, "anchorDay" TEXT NOT NULL, "timeHint" TEXT,
            "stars" INTEGER NOT NULL, "archived" INTEGER NOT NULL DEFAULT 0, "sortOrder" INTEGER NOT NULL,
            "createdAt" TEXT NOT NULL
            """),
        Table(name: "choreCompletion", parent: "chore", columns: """
            \(id), \(parent("choreId", "chore")), "day" TEXT NOT NULL, "personId" TEXT, "stars" INTEGER NOT NULL,
            "completedAt" TEXT NOT NULL
            """),
        Table(name: "reward", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "title" TEXT NOT NULL, "emoji" TEXT,
            "targetStars" INTEGER NOT NULL, "ownerId" TEXT, "startDay" TEXT NOT NULL,
            "archived" INTEGER NOT NULL DEFAULT 0, "sortOrder" INTEGER NOT NULL, "createdAt" TEXT NOT NULL
            """),
        Table(name: "rewardRedemption", parent: "reward", columns: """
            \(id), \(parent("rewardId", "reward")), "personId" TEXT, "stars" INTEGER NOT NULL, "day" TEXT NOT NULL,
            "redeemedAt" TEXT NOT NULL
            """),
        Table(name: "homeList", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "title" TEXT NOT NULL, "kind" TEXT NOT NULL,
            "sortOrder" INTEGER NOT NULL, "createdAt" TEXT NOT NULL
            """),
        Table(name: "listItem", parent: "homeList", columns: """
            \(id), \(parent("listId", "homeList")), "title" TEXT NOT NULL, "section" TEXT, "addedById" TEXT,
            "checked" INTEGER NOT NULL DEFAULT 0, "sortOrder" INTEGER NOT NULL, "createdAt" TEXT NOT NULL
            """),
        Table(name: "mealPlan", parent: "household", columns: """
            \(id), \(parent("householdId", "household")), "day" TEXT NOT NULL, "title" TEXT NOT NULL, "emoji" TEXT
            """),
        Table(name: "ambientPhoto", parent: "household", synced: false, columns: """
            \(id), \(parent("householdId", "household")), "fileName" TEXT NOT NULL UNIQUE, "caption" TEXT,
            "createdAt" TEXT NOT NULL
            """),
    ]

    /// Photo bytes, one table per kind of picture (docs/design/sync-icloud.md, "Photos").
    ///
    /// Each row is keyed by the id of the row it belongs to, which is also its one foreign
    /// key. `byteCount` comes before `image`, so reading it never walks the image's pages.
    static let photoTables: [Table] = [
        ("companionPhoto", "companionId", "companion"),
        ("journalEntryPhotoThumb", "photoId", "journalEntryPhoto"),
        ("journalEntryPhotoImage", "photoId", "journalEntryPhoto"),
    ].map { (name: String, key: String, parent: String) in
        Table(name: name, parent: parent, columns: """
            "\(key)" TEXT PRIMARY KEY NOT NULL REFERENCES "\(parent)"("id") ON DELETE CASCADE,
            "byteCount" INTEGER NOT NULL, "image" BLOB NOT NULL
            """)
    }

    /// Every synced table, parents before children, in the order the sync engine is given them.
    static var synced: [Table] {
        (tables + photoTables).filter(\.synced)
    }

    /// The indexes the old schema had, minus the ones that only backed a unique constraint.
    static let indexes: [String] = [
        ("person", ["householdId"]),
        ("calendarSource", ["householdId"]), ("calendarSource", ["ownerId"]),
        ("companion", ["householdId"]),
        ("careRoutine", ["companionId"]),
        ("careLog", ["careRoutineId"]), ("careLog", ["occurredAt"]),
        ("careLogPerson", ["careLogId"]), ("careLogPerson", ["personId"]),
        ("journal", ["householdId"]),
        ("foodPlace", ["householdId"]),
        ("journalEntry", ["journalId"]), ("journalEntry", ["journalId", "day"]), ("journalEntry", ["placeId"]),
        ("journalEntryEater", ["entryId"]), ("journalEntryEater", ["personId"]),
        ("journalEntryPhoto", ["entryId"]), ("journalEntryPhoto", ["entryId", "sortOrder"]),
        ("journalPage", ["journalId"]),
        ("chore", ["householdId"]), ("chore", ["ownerId"]),
        ("choreCompletion", ["choreId"]), ("choreCompletion", ["personId"]), ("choreCompletion", ["day"]),
        ("reward", ["householdId"]), ("reward", ["ownerId"]),
        ("rewardRedemption", ["rewardId"]), ("rewardRedemption", ["personId"]), ("rewardRedemption", ["day"]),
        ("homeList", ["householdId"]),
        ("listItem", ["listId"]), ("listItem", ["addedById"]),
        ("mealPlan", ["householdId"]),
        ("ambientPhoto", ["householdId"]),
    ].map { table, columns in
        let name = "\(table)_on_\(columns.joined(separator: "_"))"
        return #"CREATE INDEX "\#(name)" ON "\#(table)"(\#(columns.map { "\"\($0)\"" }.joined(separator: ", ")))"#
    }
}
