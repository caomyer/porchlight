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
    var eaterIds: [Person.ID]
    var eatenAt: Date
    /// The restaurant, kept only for delivery and dining out.
    var place: PlaceDraft?
}

/// A meal's photo while it is being edited: one it already has, or a new one whose
/// files are saved but not yet attached. A list of these, in order, is the meal's photos.
enum MealPhotoItem: Equatable, Hashable, Identifiable, Sendable {
    case kept(MealPhoto)
    case added(FoodPhotoStore.Stored)

    var id: String {
        switch self {
        case let .kept(photo): "kept-\(photo.id)"
        case let .added(stored): "added-\(stored.photoFile)"
        }
    }

    var thumbnailFile: String {
        switch self {
        case let .kept(photo): photo.thumbnailFile
        case let .added(stored): stored.thumbnailFile
        }
    }

    var photoFile: String {
        switch self {
        case let .kept(photo): photo.photoFile
        case let .added(stored): stored.photoFile
        }
    }

    /// The square the wall shows; nil is the center square.
    var crop: PhotoCrop? {
        switch self {
        case let .kept(photo): photo.crop
        case let .added(stored): stored.crop
        }
    }

    /// The same photo framed by `crop`, with the thumbnail made for it.
    func reframed(_ crop: PhotoCrop, thumbnailFile: String) -> MealPhotoItem {
        switch self {
        case var .kept(photo):
            photo.crop = crop
            photo.thumbnailFile = thumbnailFile
            return .kept(photo)
        case var .added(stored):
            stored.crop = crop
            stored.thumbnailFile = thumbnailFile
            return .added(stored)
        }
    }

    /// Files of new (never attached) photos that going from `old` to `new` left unused: a
    /// new photo taken out, or the old thumbnail of one that was reframed. A saved photo's
    /// files are left to the save, which knows what the meal still uses.
    static func unusedFiles(from old: [MealPhotoItem], to new: [MealPhotoItem]) -> [String] {
        let current = Dictionary(new.map { ($0.photoFile, $0) }, uniquingKeysWith: { first, _ in first })
        return old.flatMap { item -> [String] in
            guard case let .added(stored) = item else { return [] }
            guard let now = current[stored.photoFile] else { return [stored.photoFile, stored.thumbnailFile] }
            return now.thumbnailFile == stored.thumbnailFile ? [] : [stored.thumbnailFile]
        }
    }
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
    /// The people who live here now, for pickers.
    var people: [Person]
    /// Everyone, removed people included, for naming who ate a past meal.
    var everyone: [Person] = []
    var journal: Journal?
    /// Entries in day and time order.
    var entries: [JournalEntry]
    /// Who ate each entry, by entry id, in household order.
    var eaters: [JournalEntry.ID: [Person.ID]]
    /// Each entry's photos by entry id, cover first.
    var photos: [JournalEntry.ID: [MealPhoto]] = [:]
    /// Days with ink and when each page last changed (drawings load lazily).
    var pages: [String: Date]
    /// The household's restaurants, most recently eaten at first.
    var places: [FoodPlace] = []

    static let empty = FoodSnapshot(household: nil, people: [], journal: nil, entries: [], eaters: [:], pages: [:])

    static func fetch(_ db: Database) throws -> FoodSnapshot {
        guard let household = try Household.current(db) else { return .empty }
        let householdId = household.id
        let everyone = try Person.everyone(in: householdId).fetchAll(db)
        let people = everyone.active
        guard let journal = try Journal.foodJournal(db, householdId: householdId) else {
            return FoodSnapshot(household: household, people: people, everyone: everyone, journal: nil, entries: [], eaters: [:], pages: [:])
        }
        let entries = try JournalEntry
            .filter(JournalEntry.Columns.journalId == journal.id)
            .order(JournalEntry.Columns.day, JournalEntry.Columns.eatenAt, Column("createdAt"), Column("id"))
            .fetchAll(db)
        let order = Dictionary(uniqueKeysWithValues: everyone.enumerated().map { index, person in (person.id, index) })
        let eaterRows = try JournalEntryEater.fetchAll(
            db,
            sql: "SELECT e.* FROM journalEntryEater e JOIN journalEntry j ON j.id = e.entryId WHERE j.journalId = ?",
            arguments: [journal.id]
        )
        var eaters: [JournalEntry.ID: [Person.ID]] = [:]
        for row in eaterRows { eaters[row.entryId, default: []].append(row.personId) }
        for key in eaters.keys { eaters[key]?.sort { (order[$0] ?? .max, $0) < (order[$1] ?? .max, $1) } }
        let pageRows = try Row.fetchAll(db, sql: "SELECT day, updatedAt FROM journalPage WHERE journalId = ?", arguments: [journal.id])
        let pages = Dictionary(pageRows.map { ($0["day"] as String, $0["updatedAt"] as Date) }, uniquingKeysWith: max)
        let photoRows = try MealPhoto.fetchAll(
            db,
            sql: """
                SELECT p.* FROM journalEntryPhoto p JOIN journalEntry j ON j.id = p.entryId
                WHERE j.journalId = ? ORDER BY p.entryId, p.sortOrder, p.createdAt, p.id
                """,
            arguments: [journal.id]
        )
        let photos = Dictionary(grouping: photoRows, by: \.entryId)
        let places = try FoodPlace.fetchAll(
            db,
            sql: """
                SELECT p.* FROM foodPlace p
                LEFT JOIN journalEntry e ON e.placeId = p.id
                WHERE p.householdId = ?
                GROUP BY p.id
                ORDER BY MAX(COALESCE(e.eatenAt, p.createdAt)) DESC, p.createdAt DESC, p.id DESC
                """,
            arguments: [householdId]
        )
        return FoodSnapshot(household: household, people: people, everyone: everyone, journal: journal, entries: entries, eaters: eaters, photos: photos, pages: pages, places: places)
    }
}

extension Journal {
    static func foodJournal(_ db: Database, householdId: Household.ID) throws -> Journal? {
        try Journal
            .filter(Columns.householdId == householdId && Columns.kind == Journal.foodKind)
            .order(Column("createdAt"), Column("id"))
            .fetchOne(db)
    }
}

extension AppDatabase {
    static let dishTitleLimit = 60
    static let placeNameLimit = 80
    /// Photos one meal can have: angles, the table, dessert, without becoming an album.
    static let photoLimit = 6

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
    func pageDrawing(journalId: Journal.ID, day: DayKey) throws -> Data? {
        try writer.read { db in
            try JournalPage.fetchOne(db, id: JournalPage.id(journalId: journalId, day: day))?.drawing
        }
    }

    // MARK: Journal

    /// The household's food diary, created (with the default meals) when missing.
    @discardableResult
    func ensureFoodJournal(householdId: Household.ID, enabled: Bool = true, now: Date = .now) throws -> Journal {
        try writer.write { db in
            if let existing = try Journal.foodJournal(db, householdId: householdId) { return existing }
            let journal = Journal(
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

    func setJournalEnabled(id: Journal.ID, _ enabled: Bool) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE journal SET enabled = ? WHERE id = ?", arguments: [enabled, id])
        }
    }

    /// Replaces the slots, keeping them in the known display order. At least one is required;
    /// entries in a removed slot are kept (they reappear if it is turned back on).
    func setJournalSlots(id: Journal.ID, _ slots: [String]) throws {
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

    /// Logs a meal with its already-saved photos (cover first) in one transaction.
    /// The caller owns the photo files until this succeeds: if it throws, they are
    /// left alone so the person can fix the form and save again.
    @discardableResult
    func addMeal(
        _ draft: MealDraft,
        journalId: Journal.ID,
        photos: [FoodPhotoStore.Stored] = [],
        now: Date = .now
    ) throws -> JournalEntry {
        guard photos.count <= Self.photoLimit else { throw FoodError.tooManyPhotos(limit: Self.photoLimit) }
        return try writer.write { db in
                guard let journal = try Journal.fetchOne(db, id: journalId) else { throw FoodError.noJournal }
                var entry = try Self.validated(draft, journal: journal, db: db, now: now)
                entry.placeId = try Self.resolvePlace(draft, householdId: journal.householdId, db: db, now: now)
                try entry.insert(db)
                for personId in Set(draft.eaterIds) {
                    try JournalEntryEater(entryId: entry.id, personId: personId).upsert(db)
                }
                for (index, stored) in photos.enumerated() {
                    var photo = MealPhoto(entryId: entry.id, photoFile: stored.photoFile, thumbnailFile: stored.thumbnailFile, sortOrder: index, createdAt: now)
                    photo.crop = stored.crop
                    try photo.insert(db)
                }
                return entry
        }
    }

    /// Adds already-saved photos after a meal's others. If they would pass the limit, or
    /// the meal is gone, nothing is added; the caller still owns the files then.
    @discardableResult
    func addMealPhotos(entryId: JournalEntry.ID, _ photos: [FoodPhotoStore.Stored], now: Date = .now) throws -> [MealPhoto] {
        try writer.write { db in
                guard try JournalEntry.exists(db, id: entryId) else { throw FoodError.mealNotFound }
                let count = try MealPhoto.filter(Column("entryId") == entryId).fetchCount(db)
                guard count + photos.count <= Self.photoLimit else { throw FoodError.tooManyPhotos(limit: Self.photoLimit) }
                return try photos.enumerated().map { index, stored in
                    var photo = MealPhoto(entryId: entryId, photoFile: stored.photoFile, thumbnailFile: stored.thumbnailFile, sortOrder: count + index, createdAt: now)
                    photo.crop = stored.crop
                    try photo.insert(db)
                    return photo
                }
        }
    }

    /// Replaces a meal's photos with `items`, in order: kept ones stay (re-ordered, and
    /// reframed when their crop changed), added ones are attached, and the rest are removed.
    /// Returns the files nobody uses any more (removed photos, replaced thumbnails), to
    /// delete once saved. Kept photos must belong to the meal. On failure nothing changes.
    private static func writePhotos(_ items: [MealPhotoItem], entryId: JournalEntry.ID, db: Database, now: Date) throws -> [String] {
        guard items.count <= photoLimit else { throw FoodError.tooManyPhotos(limit: photoLimit) }
        let existing = try MealPhoto.filter(Column("entryId") == entryId).fetchAll(db)
        let keptIds = Set(items.compactMap { if case let .kept(photo) = $0 { photo.id } else { nil } })
        guard keptIds.isSubset(of: Set(existing.map(\.id))) else { throw FoodError.mealNotFound }
        let removed = existing.filter { !keptIds.contains($0.id) }
        for photo in removed { _ = try photo.delete(db) }
        var unused = removed.flatMap { [$0.photoFile, $0.thumbnailFile] }
        let byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for (index, item) in items.enumerated() {
            switch item {
            case let .kept(photo):
                guard var stored = byId[photo.id] else { continue }
                if stored.thumbnailFile != photo.thumbnailFile { unused.append(stored.thumbnailFile) }
                stored.sortOrder = index
                stored.crop = photo.crop
                stored.thumbnailFile = photo.thumbnailFile
                try stored.update(db)
            case let .added(stored):
                var photo = MealPhoto(entryId: entryId, photoFile: stored.photoFile, thumbnailFile: stored.thumbnailFile, sortOrder: index, createdAt: now)
                photo.crop = stored.crop
                try photo.insert(db)
            }
        }
        return unused
    }

    private static func validated(_ draft: MealDraft, journal: Journal, db: Database, now: Date) throws -> JournalEntry {
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
            journalId: journal.id,
            day: draft.day.rawValue,
            slot: draft.slot,
            source: draft.source,
            title: title,
            emoji: (emoji?.isEmpty == false ? emoji : nil) ?? DishIllustration.suggestEmoji(for: title) ?? DishIllustration.fallbackEmoji,
            tint: draft.tint ?? DishIllustration.suggestTint(for: title),
            rating: draft.rating,
            eatenAt: draft.eatenAt,
            createdAt: now
        )
    }

    /// The place a draft names, found or created in the household. Home-cooked meals and
    /// blank names have none. A known place is matched by its Maps id, else by name and
    /// address, and picks up details it was missing.
    private static func resolvePlace(_ draft: MealDraft, householdId: Household.ID, db: Database, now: Date) throws -> FoodPlace.ID? {
        guard draft.source.hasPlace, let place = draft.place else { return nil }
        func clean(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        guard let name = clean(place.name) else { return nil }
        guard name.count <= placeNameLimit else { throw FoodError.placeNameTooLong(limit: placeNameLimit) }
        let address = clean(place.address)
        let mapsId = clean(place.mapsId)
        let candidates = try FoodPlace.filter(FoodPlace.Columns.householdId == householdId).order(Column("createdAt"), Column("id")).fetchAll(db)
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
        let inserted = FoodPlace(
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

    /// Changes a logged meal's details and who ate it, and its photos when `photos` is
    /// given (see `writePhotos`). The creation time stays; the day comes from the entry,
    /// not the draft. A new title gets a fresh illustration unless the draft names one.
    @discardableResult
    func updateMeal(id: JournalEntry.ID, _ draft: MealDraft, photos: [MealPhotoItem]? = nil, files: FoodPhotoStore = .standard, now: Date = .now) throws -> JournalEntry {
        let (updated, unused) = try writer.write { db -> (JournalEntry, [String]) in
            guard var existing = try JournalEntry.fetchOne(db, id: id),
                  let journal = try Journal.fetchOne(db, id: existing.journalId) else { throw FoodError.mealNotFound }
            var draft = draft
            draft.day = existing.dayKey
            let titleChanged = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) != existing.title
            if !titleChanged {
                draft.emoji = draft.emoji ?? existing.emoji
                draft.tint = draft.tint ?? existing.tint
            }
            let validated = try Self.validated(draft, journal: journal, db: db, now: existing.createdAt)
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
                try JournalEntryEater(entryId: id, personId: personId).upsert(db)
            }
            let unused = try photos.map { try Self.writePhotos($0, entryId: id, db: db, now: now) } ?? []
            return (existing, unused)
        }
        files.delete(unused)
        return updated
    }

    /// Deletes an entry and its photo files.
    func deleteMeal(id: JournalEntry.ID, files: FoodPhotoStore) throws {
        let photos = try writer.write { db -> [MealPhoto] in
            let photos = try MealPhoto.filter(Column("entryId") == id).fetchAll(db)
            _ = try JournalEntry.deleteOne(db, id: id)
            return photos
        }
        files.delete(photos.flatMap { [$0.photoFile, $0.thumbnailFile] })
    }

    // MARK: Pages

    /// Saves a day's drawing. Empty drawings (`nil` or no strokes) remove the page.
    func savePage(journalId: Journal.ID, day: DayKey, drawing: Data?, now: Date = .now) throws {
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
    private static func writePage(_ db: Database, journalId: Journal.ID, day: DayKey, drawing: Data?, now: Date) throws {
        guard let drawing else {
            _ = try JournalPage.deleteOne(db, id: JournalPage.id(journalId: journalId, day: day))
            return
        }
        try JournalPage(journalId: journalId, day: day, drawing: drawing, updatedAt: now).upsert(db)
    }

    /// Every photo file name still referenced, for `FoodPhotoStore.sweep`.
    func referencedPhotoFiles() throws -> Set<String> {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT photoFile, thumbnailFile FROM journalEntryPhoto")
            return Set(rows.flatMap { [$0["photoFile"] as String, $0["thumbnailFile"] as String] })
        }
    }
}
