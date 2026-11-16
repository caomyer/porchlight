import Foundation
import SQLiteData

/// One mirror per synced table, describing it to the sync engine
/// (see docs/design/sync-icloud.md, "Shape").
///
/// The app never reads or writes through these: it keeps its GRDB records. The engine
/// only needs each table's name, primary key and columns. Every column has a plain type,
/// and enums and JSON are `String`, so a value written by a newer version of the app never
/// fails to decode on an older one. A test checks every mirror against its table, both ways.
enum SyncMirror {
    @Table("household") struct Household {
        let id: UUID
        var name: String
        var timeZoneIdentifier: String
        var firstWeekday: Int
        var createdAt: Date
        var setupCompleted: Bool
    }

    @Table("person") struct Person {
        let id: UUID
        var householdId: UUID
        var name: String
        var color: String
        var sortOrder: Int
        var createdAt: Date
        var archivedAt: Date?
    }

    @Table("companion") struct Companion {
        let id: UUID
        var householdId: UUID
        var name: String
        var species: String
        var coat: String
        var about: String
        var birthDate: Date?
        var captionTone: String
        var sortOrder: Int
        var createdAt: Date
    }

    @Table("careRoutine") struct CareRoutine {
        let id: UUID
        var companionId: UUID
        var kind: String
        var title: String
        var emoji: String
        var everyDays: Int
        var windows: String
        var trackedFields: String
        var stars: Int
        var nudgeAfterMinutes: Int?
        var sortOrder: Int
        var repeatKind: String
        var weekdayMask: Int
        var anchorDay: String
    }

    @Table("careLog") struct CareLog {
        let id: UUID
        var careRoutineId: UUID
        var occurredAt: Date
        var durationMinutes: Int?
        var pee: Bool?
        var poo: Bool?
        var vibe: String?
        var note: String?
        var stars: Int
        var createdAt: Date
    }

    @Table("careLogPerson") struct CareLogPerson {
        let id: UUID
        var careLogId: UUID
        var personId: UUID
    }

    @Table("journal") struct Journal {
        let id: UUID
        var householdId: UUID
        var kind: String
        var title: String
        var enabled: Bool
        var slots: String
        var createdAt: Date
    }

    @Table("foodPlace") struct FoodPlace {
        let id: UUID
        var householdId: UUID
        var name: String
        var address: String?
        var latitude: Double?
        var longitude: Double?
        var category: String?
        var phone: String?
        var url: String?
        var mapsId: String?
        var createdAt: Date
    }

    @Table("journalEntry") struct JournalEntry {
        let id: UUID
        var journalId: UUID
        var day: String
        var slot: String
        var source: String
        var title: String
        var emoji: String?
        var tint: Int?
        var rating: Int?
        var eatenAt: Date
        var createdAt: Date
        var placeId: UUID?
    }

    @Table("journalEntryEater") struct JournalEntryEater {
        let id: UUID
        var entryId: UUID
        var personId: UUID
    }

    @Table("journalEntryPhoto") struct JournalEntryPhoto {
        let id: UUID
        var entryId: UUID
        var sortOrder: Int
        var createdAt: Date
        var cropX: Double?
        var cropY: Double?
        var cropWidth: Double?
        var cropHeight: Double?
    }

    @Table("journalPage") struct JournalPage {
        let id: UUID
        var journalId: UUID
        var day: String
        var drawing: Data
        var updatedAt: Date
    }

    @Table("chore") struct Chore {
        let id: UUID
        var householdId: UUID
        var title: String
        var emoji: String?
        var ownerId: UUID?
        var repeatKind: String
        var weekdayMask: Int
        var intervalDays: Int
        var anchorDay: String
        var timeHint: String?
        var stars: Int
        var archived: Bool
        var sortOrder: Int
        var createdAt: Date
    }

    @Table("choreCompletion") struct ChoreCompletion {
        let id: UUID
        var choreId: UUID
        var day: String
        var personId: UUID?
        var stars: Int
        var completedAt: Date
    }

    @Table("reward") struct Reward {
        let id: UUID
        var householdId: UUID
        var title: String
        var emoji: String?
        var targetStars: Int
        var ownerId: UUID?
        var startDay: String
        var archived: Bool
        var sortOrder: Int
        var createdAt: Date
    }

    @Table("rewardRedemption") struct RewardRedemption {
        let id: UUID
        var rewardId: UUID
        var personId: UUID?
        var stars: Int
        var day: String
        var redeemedAt: Date
    }

    @Table("homeList") struct HomeList {
        let id: UUID
        var householdId: UUID
        var title: String
        var kind: String
        var sortOrder: Int
        var createdAt: Date
    }

    @Table("listItem") struct ListItem {
        let id: UUID
        var listId: UUID
        var title: String
        var section: String?
        var addedById: UUID?
        var checked: Bool
        var sortOrder: Int
        var createdAt: Date
    }

    @Table("mealPlan") struct MealPlan {
        let id: UUID
        var householdId: UUID
        var day: String
        var title: String
        var emoji: String?
    }

    // Photo bytes, each keyed by the row it belongs to. The engine sends every BLOB as an
    // iCloud asset.

    @Table("companionPhoto") struct CompanionPhoto {
        @Column(primaryKey: true) let companionId: UUID
        var byteCount: Int
        var image: Data
    }

    @Table("journalEntryPhotoThumb") struct JournalEntryPhotoThumb {
        @Column(primaryKey: true) let photoId: UUID
        var byteCount: Int
        var image: Data
    }

    @Table("journalEntryPhotoImage") struct JournalEntryPhotoImage {
        @Column(primaryKey: true) let photoId: UUID
        var byteCount: Int
        var image: Data
    }
}

extension SyncMirror {
    /// A sync engine for every mirror, in `SyncSchema.synced` order, created stopped:
    /// `SyncController` decides when it runs.
    ///
    /// Creating it validates the schema and installs the triggers that record every write,
    /// so it is created right after migrations, before anything else writes.
    static func engine(for database: any DatabaseWriter, delegate: any SyncEngineDelegate) throws -> SyncEngine {
        try SyncEngine(
            for: database,
            tables: Household.self, Person.self,
            Companion.self, CareRoutine.self, CareLog.self, CareLogPerson.self,
            Journal.self, FoodPlace.self, JournalEntry.self, JournalEntryEater.self, JournalEntryPhoto.self,
            JournalPage.self,
            Chore.self, ChoreCompletion.self, Reward.self, RewardRedemption.self,
            HomeList.self, ListItem.self, MealPlan.self,
            CompanionPhoto.self, JournalEntryPhotoThumb.self, JournalEntryPhotoImage.self,
            containerIdentifier: SyncController.containerIdentifier,
            startImmediately: false,
            delegate: delegate
        )
    }
}
