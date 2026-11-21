import Foundation
import Observation
import PencilKit
import SwiftUI

/// Live food diary state: mirrors the database and forwards edits to it.
@MainActor
@Observable
final class FoodStore: StoredFirstObservable {
    let database: AppDatabase

    /// What the database says now, stored before observers are told (see `AppModel.snapshot`).
    private(set) var snapshot: FoodSnapshot {
        get {
            access(keyPath: \.snapshot)
            return storedSnapshot
        }
        set {
            storedSnapshot = newValue
            storedBook = nil
            withMutation(keyPath: \.snapshot) {}
            // A title in Chinese or Japanese asks iOS for the handwriting's companion, once.
            HandCompanionFonts.shared.note(titles: newValue.entries.lazy.map(\.title))
        }
    }

    /// The dishes of the snapshot, worked out once per snapshot (docs/design/dishes.md).
    var book: DishBook {
        // Read the snapshot first, so views that only ask for the book still follow changes.
        let snapshot = snapshot
        if let storedBook { return storedBook }
        let book = DishBook(snapshot)
        storedBook = book
        return book
    }

    @ObservationIgnored private var storedBook: DishBook?

    @ObservationIgnored private var storedSnapshot: FoodSnapshot = .empty
    @ObservationIgnored @StoredFirst var lastError: String? = nil

    // MARK: Pen state, shared by the month tool bar, the day editor and the note strip

    /// The chosen ink, or nil to use the first person's own pen.
    var chosenInk: PageInk?
    var tip: PenTip = .felt
    var isErasing = false

    /// Apple Pencil only by default so resting hands leave no marks; a device setting.
    var allowsFingerDrawing: Bool = UserDefaults.standard.bool(forKey: FoodStore.fingerDrawingKey) {
        didSet { UserDefaults.standard.set(allowsFingerDrawing, forKey: Self.fingerDrawingKey) }
    }

    static let fingerDrawingKey = "food.allowFingerDrawing"

    @ObservationIgnored let pageImages = PageImageCache()
    @ObservationIgnored private var observation: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        if let first = try? database.foodSnapshot() { snapshot = first }
        observe()
    }

    private func observe() {
        observation = Task { [weak self, database] in
            do {
                for try await snapshot in database.foodUpdates() {
                    self?.snapshot = snapshot
                    await Self.tidy(database)
                }
            } catch {
                self?.lastError = error.userMessage
            }
        }
    }

    /// Gives meals an older build logged their dish, and merges dishes two devices made
    /// with one name. Off the main actor; a failure waits for the next change.
    private nonisolated static func tidy(_ database: AppDatabase) async {
        await Task.detached(priority: .utility) {
            guard (try? database.dishesNeedTidying()) == true else { return }
            try? database.tidyDishes()
        }.value
    }

    // MARK: Integration surface

    /// Whether the household uses the food diary (controls the rail entry).
    var isEnabled: Bool { snapshot.journal?.enabled ?? false }

    /// Logged meals for the Today agenda.
    func timelineItems(for day: DayKey) -> [TimelineItem] {
        guard isEnabled else { return [] }
        return entries(on: day).compactMap { entry in
            let id = entry.id
            var subtitle = place(of: entry).map { "\(entry.sources.label) · \($0.name)" } ?? entry.sources.label
            if let rating = entry.rating { subtitle += " · \(rating.emoji) \(rating.phrase)" }
            // The thumbnail is too small for a count badge, so the count joins the subtitle.
            let photoCount = photos(of: entry).count
            if photoCount > 1 { subtitle += " · \(photoCount) photos" }
            return TimelineItem(
                id: "food-\(id)",
                kind: .log,
                time: entry.eatenAt,
                title: "\(entry.slot) · \(entry.title)",
                subtitle: subtitle,
                owner: owner(of: entry),
                leading: AnyView(MealThumbnail(entry: entry, size: 34)),
                trailing: AnyView(EaterBadge(people: eaters(of: entry), everyone: ateTogether(entry), size: 30)),
                target: .meal(id),
                origin: RowOrigin(rowId: id.description, deviceId: entry.deviceId)
            )
        }
    }

    /// Mini-plate lanes for month cells (the week and day grids show each meal at its time).
    func calendarLanes() -> [CalendarLane] {
        guard isEnabled else { return [] }
        return [
            CalendarLane(
                id: "meals",
                styles: [.month],
                label: AnyView(MealsLaneLabel()),
                title: "meals",
                cell: { [self] day, style in AnyView(MealPlatesCell(store: self, day: day, style: style)) }
            ),
        ]
    }

    /// Recent meal photos for Ambient mode, newest meals first. At most
    /// `ambientPhotosPerMeal` come from one meal, so a six-angle dinner doesn't take over.
    /// Only whole shots: a thumbnail would look blurry full screen.
    func recentPhotos(limit: Int) -> [PhotoSource] {
        guard isEnabled, limit > 0 else { return [] }
        let meals = snapshot.entries.sorted { $0.eatenAt > $1.eatenAt }
        return Array(meals.lazy.flatMap { self.photos(of: $0).compactMap(self.image(of:)).prefix(Self.ambientPhotosPerMeal) }.prefix(limit))
    }

    static let ambientPhotosPerMeal = 3

    // MARK: Reads

    var journal: Journal? { snapshot.journal }
    /// The people who live here now, for pickers.
    var people: [Person] { snapshot.people }
    var calendar: Calendar { snapshot.household?.calendar ?? .current }
    var slots: [String] { journal?.slots ?? MealSlot.defaultNames }
    /// Slots shown as the day's plates on Today (breakfast, lunch, dinner).
    var mainSlots: [String] { Array(slots.filter { MealSlot.named($0).isMain }.prefix(3)) }

    func today(_ now: Date = .now) -> DayKey { DayKey(now, calendar: calendar) }

    func entries(on day: DayKey) -> [JournalEntry] {
        snapshot.entries.filter { $0.day == day.rawValue }
    }

    func entries(on day: DayKey, slot: String) -> [JournalEntry] {
        snapshot.entries.filter { $0.day == day.rawValue && $0.slot == slot }
    }

    /// Who ate a meal, removed people included; ids that point at nobody are skipped.
    func eaters(of entry: JournalEntry) -> [Person] {
        (snapshot.eaters[entry.id] ?? []).compactMap { snapshot.everyone.person($0) }
    }

    /// Everyone in the household ate it (shown as ♥).
    func ateTogether(_ entry: JournalEntry) -> Bool {
        let eaters = eaters(of: entry)
        return eaters.isEmpty || (people.count > 1 && eaters.count == people.count)
    }

    func owner(of entry: JournalEntry) -> Owner {
        let eaters = eaters(of: entry)
        if eaters.count == 1, !ateTogether(entry) { return .person(eaters[0].id) }
        return .everyone
    }

    /// The restaurant a meal was eaten at or delivered from.
    func place(of entry: JournalEntry) -> FoodPlace? {
        guard let id = entry.placeId else { return nil }
        return snapshot.places.first { $0.id == id }
    }

    /// The household's restaurant a form names, matched as saving matches it: by its Maps
    /// id, else by name and address. Nil for a place new to the diary.
    func place(matching draft: PlaceDraft?) -> FoodPlace? {
        guard let draft, !DishName.key(draft.name).isEmpty else { return nil }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = draft.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let mapsId = draft.mapsId, let match = snapshot.places.first(where: { $0.mapsId == mapsId }) { return match }
        return snapshot.places.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && ($0.address ?? "").caseInsensitiveCompare(address) == .orderedSame
        }
    }

    /// A photo's thumbnail, the square the wall shows; nil until it has one.
    func thumbnail(of photo: MealPhoto) -> PhotoSource? {
        snapshot.photoSizes[photo.id]?.thumbnail.map { .mealThumbnail(photo.id, byteCount: $0) }
    }

    /// A photo's whole shot; nil when it has none (only its thumbnail survived from a file).
    func image(of photo: MealPhoto) -> PhotoSource? {
        snapshot.photoSizes[photo.id]?.image.map { .mealImage(photo.id, byteCount: $0) }
    }

    /// The thumbnail of a photo in an edit, which may not be saved yet.
    func thumbnail(of item: MealPhotoItem) -> PhotoSource? {
        switch item {
        case let .kept(photo, reframed): reframed.map(PhotoSource.unsaved) ?? thumbnail(of: photo)
        case let .added(new): .unsaved(new.thumbnail)
        }
    }

    /// The whole shot of a photo in an edit, which may not be saved yet.
    func image(of item: MealPhotoItem) -> PhotoSource? {
        switch item {
        case let .kept(photo, _): image(of: photo)
        case let .added(new): .unsaved(new.image)
        }
    }

    /// A meal's photos, cover first.
    func photos(of entry: JournalEntry) -> [MealPhoto] {
        snapshot.photos[entry.id] ?? []
    }

    /// The picture shown for the meal wherever many meals appear at once.
    func cover(of entry: JournalEntry) -> MealPhoto? {
        photos(of: entry).first
    }

    /// Days that have a meal or ink.
    var activeDays: Set<DayKey> {
        Set(snapshot.entries.map(\.dayKey)).union(snapshot.pages.keys.map(DayKey.init(rawValue:)))
    }

    func streak(today: DayKey) -> Int {
        DiaryStreak.length(activeDays: activeDays, today: today, calendar: calendar)
    }

    func weekStats(days: [DayKey]) -> WeekStats {
        guard let first = days.min() else { return WeekStats() }
        let keys = Set(days.map(\.rawValue))
        let week = snapshot.entries.filter { keys.contains($0.day) }
        let history = snapshot.entries.filter { $0.day < first.rawValue }
        return WeekStats.make(week: week, history: history)
    }

    func memory(today: DayKey) -> FoodMemory? {
        FoodMemory.find(in: snapshot.entries, withPhotos: Set(snapshot.photos.keys), today: today, calendar: calendar)
    }

    /// The default pen: the chosen ink, else the first person's own color.
    var ink: PageInk {
        chosenInk ?? people.first.map { PageInk.defaultInk(for: $0.color) } ?? .midnight
    }

    // MARK: Pages

    func pageDrawing(for day: DayKey) -> PKDrawing {
        guard let journalId = journal?.id, snapshot.pages[day.rawValue] != nil else { return PKDrawing() }
        return PageInkData.drawing(from: try? database.pageDrawing(journalId: journalId, day: day))
    }

    /// The day's ink rendered at `scale`, cached until the page changes.
    func pageImage(for day: DayKey, scale: CGFloat, displayScale: CGFloat) -> UIImage? {
        guard let journalId = journal?.id, let updatedAt = snapshot.pages[day.rawValue] else { return nil }
        return pageImages.image(day: day, updatedAt: updatedAt, scale: scale, displayScale: displayScale) {
            try? database.pageDrawing(journalId: journalId, day: day)
        }
    }

    func savePage(_ drawing: PKDrawing, for day: DayKey) {
        guard let journalId = journal?.id else { return }
        perform { try database.savePage(journalId: journalId, day: day, drawing: drawing.dataRepresentation()) }
    }

    // MARK: Edits

    /// Makes a photo and its thumbnail off the main actor. It is held in memory, attached to
    /// nothing, until it goes to `addMeal`, `addPhotos` or an edit.
    func preparePhoto(_ image: UIImage) async throws -> NewMealPhoto {
        try await Task.detached(priority: .userInitiated) { try MealPhotoImaging.prepare(image) }.value
    }

    /// A new thumbnail of a photo's whole shot for `crop`, made off the main actor.
    func thumbnail(ofImage data: Data, crop: PhotoCrop) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { try MealPhotoImaging.thumbnail(ofImage: data, crop: crop) }.value
    }

    /// Logs a meal with its photos, cover first. If it throws, nothing is saved and the
    /// caller still holds the photos for another try.
    func addMeal(_ draft: MealDraft, photos: [NewMealPhoto] = []) throws -> JournalEntry {
        guard let journalId = journal?.id else { throw FoodError.noJournal }
        return try database.addMeal(dishesFromTitle(draft, lines: []), journalId: journalId, photos: photos)
    }

    /// Adds photos to a meal that is already saved. Returns false, with `lastError` set,
    /// when they could not be added.
    @discardableResult
    func addPhotos(_ images: [UIImage], to entry: JournalEntry) async -> Bool {
        guard !images.isEmpty else { return false }
        let id = entry.id
        do {
            var photos: [NewMealPhoto] = []
            for image in images { photos.append(try await preparePhoto(image)) }
            try database.addMealPhotos(entryId: id, photos)
            lastError = nil
            return true
        } catch {
            lastError = error.userMessage
            return false
        }
    }

    /// Saves edits to a logged meal, and its photos when given. Returns false, with
    /// `lastError` set, when they are rejected.
    @discardableResult
    func updateMeal(_ entry: JournalEntry, _ draft: MealDraft, photos items: [MealPhotoItem]? = nil) -> Bool {
        let id = entry.id
        let draft = dishesFromTitle(draft, lines: snapshot.lines[id] ?? [])
        return perform { try database.updateMeal(id: id, draft, photos: items) }
    }

    /// Until Snap and Edit name dishes one by one, "What was it?" is the meal's one dish: a
    /// typed name is its dish (the same one it had when the name still matches), and no name
    /// is no dish. A meal with several dishes keeps them; the title can't speak for them.
    private func dishesFromTitle(_ draft: MealDraft, lines: [MealDish]) -> MealDraft {
        guard draft.dishes == nil, lines.count <= 1 else { return draft }
        var draft = draft
        let name = DishName.cleaned(draft.title)
        if DishName.key(name).isEmpty || DishName.key(name) == DishName.key(draft.slot) {
            draft.dishes = []
        } else {
            let kept = lines.first.flatMap { book.dish($0.dishId) }.flatMap { $0.key == DishName.key(name) ? $0.id : nil }
            draft.dishes = [DishLineDraft(name: name, dishId: kept, rating: draft.rating)]
        }
        return draft
    }

    func deleteMeal(_ entry: JournalEntry) {
        let id = entry.id
        perform { try database.deleteMeal(id: id) }
    }

    // MARK: Dishes

    /// Renames a dish everywhere. Throws `DishError.nameTaken` when another dish of its
    /// kitchen has the name, so the caller can offer to merge.
    func renameDish(_ id: Dish.ID, to name: String) throws {
        try database.renameDish(id: id, to: name)
    }

    func mergeDish(_ id: Dish.ID, into survivor: Dish.ID) {
        perform { try database.mergeDish(id: id, into: survivor) }
    }

    func setFavorite(_ id: Dish.ID, _ favorite: Bool) {
        perform { try database.setFavorite(dishId: id, favorite) }
    }

    /// Removes a dish from every meal; nil when it couldn't.
    func removeDish(_ id: Dish.ID) -> DishRemoval? {
        do {
            let removal = try database.removeDish(id: id)
            lastError = nil
            return removal
        } catch {
            lastError = error.userMessage
            return nil
        }
    }

    func restore(_ removal: DishRemoval) {
        perform { try database.restore(removal) }
    }

    // MARK: Recipes (docs/design/dishes.md, "Recipes")

    /// The recipe bank, read from this snapshot's dish book.
    var recipeBank: RecipeBank { RecipeBank(book) }

    /// Adds or edits a recipe; throws so the editor can say why, and offer the dish a name
    /// is taken by.
    @discardableResult
    func saveRecipe(_ draft: RecipeDraft, addedBy: Person.ID?) throws -> Dish {
        guard let householdId = snapshot.household?.id else { throw DishError.dishNotFound }
        let saved = try database.saveRecipe(draft, householdId: householdId, addedBy: addedBy)
        lastError = nil
        return saved.dish
    }

    /// Removes a dish's recipe; nil when it couldn't.
    func removeRecipe(of dishId: Dish.ID) -> RecipeRemoval? {
        do {
            let removal = try database.removeRecipe(dishId: dishId)
            lastError = nil
            return removal
        } catch {
            lastError = error.userMessage
            return nil
        }
    }

    func restore(_ removal: RecipeRemoval) {
        perform { try database.restore(removal) }
    }

    func setTableFace(_ line: MealDish, _ rating: MealRating?) {
        perform { try database.setTableFace(lineId: line.id, rating) }
    }

    func setPersonFace(_ line: MealDish, person: Person.ID, _ rating: MealRating?) {
        perform { try database.setPersonFace(lineId: line.id, personId: person, rating) }
    }

    /// Turns the diary on or off, creating it the first time.
    func setEnabled(_ enabled: Bool) {
        guard let householdId = snapshot.household?.id else { return }
        perform {
            let journal = try database.ensureFoodJournal(householdId: householdId, enabled: enabled)
            if journal.enabled != enabled { try database.setJournalEnabled(id: journal.id, enabled) }
        }
    }

    func setSlot(_ slot: String, on: Bool) {
        guard let journal else { return }
        var slots = journal.slots.filter { $0 != slot }
        if on { slots.append(slot) }
        perform { try database.setJournalSlots(id: journal.id, slots) }
    }

    @discardableResult
    private func perform(_ work: () throws -> Void) -> Bool {
        do {
            try work()
            lastError = nil
            return true
        } catch {
            lastError = error.userMessage
            return false
        }
    }
}
