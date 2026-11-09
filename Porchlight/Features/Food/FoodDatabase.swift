import Foundation
import GRDB

// All food diary reads and writes, with validation.

/// A meal about to be logged.
struct MealDraft: Equatable, Sendable {
    var day: DayKey
    var slot: String
    var source: MealSource = .home
    var title: String = ""
    var emoji: String?
    var tint: Int?
    var rating: MealRating? = .again
    var eaterIds: [Int64]
    var eatenAt: Date
    /// The restaurant, kept only for delivery and dining out.
    var place: PlaceDraft?
}

/// A restaurant about to be named on a meal: from the map search, or just a typed name.
struct PlaceDraft: Equatable, Hashable, Sendable {
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var category: String?
    var phone: String?
    var url: String?
    var mapsId: String?

    init(name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil,
         category: String? = nil, phone: String? = nil, url: String? = nil, mapsId: String? = nil) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.phone = phone
        self.url = url
        self.mapsId = mapsId
    }

    init(_ place: FoodPlace) {
        self.init(name: place.name, address: place.address, latitude: place.latitude, longitude: place.longitude,
                  category: place.category, phone: place.phone, url: place.url, mapsId: place.mapsId)
    }
}

/// Everything the food screens need, read in one consistent snapshot.
struct FoodSnapshot: Equatable, Sendable {
    var household: Household?
    var people: [Person]
    var journal: Journal?
    /// Entries in day and time order.
    var entries: [JournalEntry]
    /// Who ate each entry, by entry id, in household order.
    var eaters: [Int64: [Int64]]
    /// Days with ink and when each page last changed (drawings load lazily).
    var pages: [String: Date]
    /// The household's restaurants, most recently eaten at first.
    var places: [FoodPlace] = []

    static let empty = FoodSnapshot(household: nil, people: [], journal: nil, entries: [], eaters: [:], pages: [:])

    static func fetch(_ db: Database) throws -> FoodSnapshot {
        let household = try Household.order(Column("id")).fetchOne(db)
        guard let household, let householdId = household.id else { return .empty }
        let people = try Person
            .filter(Column("householdId") == householdId)
            .order(Column("sortOrder"), Column("id"))
            .fetchAll(db)
        guard let journal = try Journal.foodJournal(db, householdId: householdId) else {
            return FoodSnapshot(household: household, people: people, journal: nil, entries: [], eaters: [:], pages: [:])
        }
        let entries = try JournalEntry
            .filter(JournalEntry.Columns.journalId == journal.id)
            .order(JournalEntry.Columns.day, JournalEntry.Columns.eatenAt, Column("id"))
            .fetchAll(db)
        let order = Dictionary(uniqueKeysWithValues: people.enumerated().compactMap { index, person in person.id.map { ($0, index) } })
        let eaterRows = try JournalEntryEater.fetchAll(
            db,
            sql: "SELECT e.* FROM journalEntryEater e JOIN journalEntry j ON j.id = e.entryId WHERE j.journalId = ?",
            arguments: [journal.id]
        )
        var eaters: [Int64: [Int64]] = [:]
        for row in eaterRows { eaters[row.entryId, default: []].append(row.personId) }
        for key in eaters.keys { eaters[key]?.sort { (order[$0] ?? .max) < (order[$1] ?? .max) } }
        let pageRows = try Row.fetchAll(db, sql: "SELECT day, updatedAt FROM journalPage WHERE journalId = ?", arguments: [journal.id])
        let pages = Dictionary(pageRows.map { ($0["day"] as String, $0["updatedAt"] as Date) }, uniquingKeysWith: max)
        let places = try FoodPlace.fetchAll(
            db,
            sql: """
                SELECT p.* FROM foodPlace p
                LEFT JOIN journalEntry e ON e.placeId = p.id
                WHERE p.householdId = ?
                GROUP BY p.id
                ORDER BY MAX(COALESCE(e.eatenAt, p.createdAt)) DESC, p.id DESC
                """,
            arguments: [householdId]
        )
        return FoodSnapshot(household: household, people: people, journal: journal, entries: entries, eaters: eaters, pages: pages, places: places)
    }
}

extension Journal {
    static func foodJournal(_ db: Database, householdId: Int64) throws -> Journal? {
        try Journal
            .filter(Columns.householdId == householdId && Columns.kind == Journal.foodKind)
            .order(Column("id"))
            .fetchOne(db)
    }
}

extension AppDatabase {
    static let dishTitleLimit = 60
    static let placeNameLimit = 80

    // MARK: Reads

    func foodSnapshot() throws -> FoodSnapshot {
        try writer.read(FoodSnapshot.fetch)
    }

    /// Emits a new snapshot every time the household, people or food diary change.
    func foodUpdates() -> AsyncValueObservation<FoodSnapshot> {
        ValueObservation
            .tracking(FoodSnapshot.fetch)
            .removeDuplicates()
            .values(in: writer)
    }

    /// The stored drawing of one day's page, if it has ink.
    func pageDrawing(journalId: Int64, day: DayKey) throws -> Data? {
        try writer.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT drawing FROM journalPage WHERE journalId = ? AND day = ?",
                arguments: [journalId, day.rawValue]
            )
        }
    }

    // MARK: Journal

    /// The household's food diary, created (with the default meals) when missing.
    @discardableResult
    func ensureFoodJournal(householdId: Int64, enabled: Bool = true, now: Date = .now) throws -> Journal {
        try writer.write { db in
            if let existing = try Journal.foodJournal(db, householdId: householdId) { return existing }
            var journal = Journal(
                householdId: householdId,
                kind: Journal.foodKind,
                title: "Food diary",
                enabled: enabled,
                slots: MealSlot.defaultNames,
                createdAt: now
            )
            try journal.insert(db)
            return journal
        }
    }

    func setJournalEnabled(id: Int64, _ enabled: Bool) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE journal SET enabled = ? WHERE id = ?", arguments: [enabled, id])
        }
    }

    /// Replaces the slots, keeping them in the known display order. At least one is required;
    /// entries in a removed slot are kept (they reappear if it is turned back on).
    func setJournalSlots(id: Int64, _ slots: [String]) throws {
        var unique: [String] = []
        for slot in slots.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !slot.isEmpty {
            if !unique.contains(where: { $0.caseInsensitiveCompare(slot) == .orderedSame }) { unique.append(slot) }
        }
        guard !unique.isEmpty else { throw ValidationError.emptyName }
        let order = MealSlot.known.map(\.name)
        unique.sort { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        try writer.write { db in
            guard var journal = try Journal.fetchOne(db, id: id) else { throw FoodError.noJournal }
            journal.slots = unique
            try journal.update(db)
        }
    }

    // MARK: Entries

    /// Logs a meal, optionally with an already-saved photo, in one transaction.
    /// If the write fails, the photo files are removed.
    @discardableResult
    func addMeal(
        _ draft: MealDraft,
        journalId: Int64,
        photo: FoodPhotoStore.Stored? = nil,
        photos: FoodPhotoStore,
        now: Date = .now
    ) throws -> JournalEntry {
        do {
            return try writer.write { db in
                guard let journal = try Journal.fetchOne(db, id: journalId) else { throw FoodError.noJournal }
                var entry = try Self.validated(draft, journal: journal, db: db, photo: photo, now: now)
                entry.placeId = try Self.resolvePlace(draft, householdId: journal.householdId, db: db, now: now)
                var inserted = entry
                try inserted.insert(db)
                for personId in Set(draft.eaterIds) {
                    try JournalEntryEater(entryId: inserted.id!, personId: personId).insert(db)
                }
                return inserted
            }
        } catch {
            photos.delete([photo?.photoFile, photo?.thumbnailFile])
            throw error
        }
    }

    private static func validated(_ draft: MealDraft, journal: Journal, db: Database, photo: FoodPhotoStore.Stored?, now: Date) throws -> JournalEntry {
        guard journal.slots.contains(draft.slot) else { throw FoodError.unknownSlot(draft.slot) }
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? draft.slot : trimmed
        guard title.count <= dishTitleLimit else { throw FoodError.titleTooLong(limit: dishTitleLimit) }
        let ids = Set(draft.eaterIds)
        guard !ids.isEmpty else { throw FoodError.nobodyAte }
        let members = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM person WHERE householdId = ? AND id IN (\(ids.map { _ in "?" }.joined(separator: ",")))",
            arguments: StatementArguments([journal.householdId] + ids.map { $0 as (any DatabaseValueConvertible) })
        ) ?? 0
        guard members == ids.count else { throw FoodError.nobodyAte }
        let emoji = draft.emoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        return JournalEntry(
            journalId: journal.id!,
            day: draft.day.rawValue,
            slot: draft.slot,
            source: draft.source,
            title: title,
            emoji: (emoji?.isEmpty == false ? emoji : nil) ?? DishIllustration.suggestEmoji(for: title) ?? DishIllustration.fallbackEmoji,
            tint: draft.tint ?? DishIllustration.suggestTint(for: title),
            rating: draft.rating,
            photoFile: photo?.photoFile,
            thumbnailFile: photo?.thumbnailFile,
            eatenAt: draft.eatenAt,
            createdAt: now
        )
    }

    /// The place a draft names, found or created in the household. Home-cooked meals and
    /// blank names have none. A known place is matched by its Maps id, else by name and
    /// address, and picks up details it was missing.
    private static func resolvePlace(_ draft: MealDraft, householdId: Int64, db: Database, now: Date) throws -> Int64? {
        guard draft.source.hasPlace, let place = draft.place else { return nil }
        func clean(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        guard let name = clean(place.name) else { return nil }
        guard name.count <= placeNameLimit else { throw FoodError.placeNameTooLong(limit: placeNameLimit) }
        let address = clean(place.address)
        let mapsId = clean(place.mapsId)
        let candidates = try FoodPlace.filter(FoodPlace.Columns.householdId == householdId).order(Column("id")).fetchAll(db)
        let match = candidates.first { mapsId != nil && $0.mapsId == mapsId }
            ?? candidates.first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
                    && ($0.address ?? "").caseInsensitiveCompare(address ?? "") == .orderedSame
            }
        if var existing = match {
            let before = existing
            existing.address = existing.address ?? address
            existing.latitude = existing.latitude ?? place.latitude
            existing.longitude = existing.longitude ?? place.longitude
            existing.category = existing.category ?? clean(place.category)
            existing.phone = existing.phone ?? clean(place.phone)
            existing.url = existing.url ?? clean(place.url)
            existing.mapsId = existing.mapsId ?? mapsId
            if existing != before { try existing.update(db) }
            return existing.id
        }
        var inserted = FoodPlace(
            householdId: householdId,
            name: name,
            address: address,
            latitude: place.latitude,
            longitude: place.longitude,
            category: clean(place.category),
            phone: clean(place.phone),
            url: clean(place.url),
            mapsId: mapsId,
            createdAt: now
        )
        try inserted.insert(db)
        return inserted.id
    }

    /// Changes a logged meal's details and who ate it. The photo and creation time stay; the day comes from the entry, not the draft. A new title gets a fresh
    /// illustration unless the draft names one.
    @discardableResult
    func updateMeal(id: Int64, _ draft: MealDraft, now: Date = .now) throws -> JournalEntry {
        try writer.write { db in
            guard var existing = try JournalEntry.fetchOne(db, id: id),
                  let journal = try Journal.fetchOne(db, id: existing.journalId) else { throw FoodError.mealNotFound }
            var draft = draft
            draft.day = existing.dayKey
            let titleChanged = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) != existing.title
            if !titleChanged {
                draft.emoji = draft.emoji ?? existing.emoji
                draft.tint = draft.tint ?? existing.tint
            }
            let validated = try Self.validated(draft, journal: journal, db: db, photo: nil, now: existing.createdAt)
            existing.slot = validated.slot
            existing.source = validated.source
            existing.title = validated.title
            existing.emoji = validated.emoji
            existing.tint = validated.tint
            existing.rating = validated.rating
            existing.eatenAt = validated.eatenAt
            existing.placeId = try Self.resolvePlace(draft, householdId: journal.householdId, db: db, now: now)
            try existing.update(db)
            try db.execute(sql: "DELETE FROM journalEntryEater WHERE entryId = ?", arguments: [id])
            for personId in Set(draft.eaterIds) {
                try JournalEntryEater(entryId: id, personId: personId).insert(db)
            }
            return existing
        }
    }

    /// Deletes an entry and its photo files.
    func deleteMeal(id: Int64, photos: FoodPhotoStore) throws {
        let entry = try writer.write { db -> JournalEntry? in
            guard let entry = try JournalEntry.fetchOne(db, id: id) else { return nil }
            _ = try JournalEntry.deleteOne(db, id: id)
            return entry
        }
        if let entry { photos.delete([entry.photoFile, entry.thumbnailFile]) }
    }

    // MARK: Pages

    /// Saves a day's drawing. Empty drawings (`nil` or no strokes) remove the page.
    func savePage(journalId: Int64, day: DayKey, drawing: Data?, now: Date = .now) throws {
        let drawing = drawing.flatMap(Self.nonBlank)
        try writer.write { db in
            try Self.writePage(db, journalId: journalId, day: day, drawing: drawing, now: now)
        }
    }

    /// The drawing, or nil when it has no strokes. Must run outside database closures:
    /// decoding a PencilKit drawing can hop to the main thread, which may be waiting on the write.
    private static func nonBlank(_ drawing: Data) -> Data? {
        drawing.isEmpty || PageInkData.isBlank(drawing) ? nil : drawing
    }

    /// Upserts a page; `nil` (already checked by `nonBlank`) deletes it.
    private static func writePage(_ db: Database, journalId: Int64, day: DayKey, drawing: Data?, now: Date) throws {
        guard let drawing else {
            try db.execute(sql: "DELETE FROM journalPage WHERE journalId = ? AND day = ?", arguments: [journalId, day.rawValue])
            return
        }
        try db.execute(
            sql: """
                INSERT INTO journalPage (journalId, day, drawing, updatedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(journalId, day) DO UPDATE SET drawing = excluded.drawing, updatedAt = excluded.updatedAt
                """,
            arguments: [journalId, day.rawValue, drawing, now]
        )
    }

    /// Every photo file name still referenced, for `FoodPhotoStore.sweep`.
    func referencedPhotoFiles() throws -> Set<String> {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT photoFile, thumbnailFile FROM journalEntry WHERE photoFile IS NOT NULL OR thumbnailFile IS NOT NULL")
            return Set(rows.flatMap { [$0["photoFile"] as String?, $0["thumbnailFile"] as String?].compactMap { $0 } })
        }
    }
}
