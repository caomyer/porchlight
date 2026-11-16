import Foundation
import Observation
import PencilKit
import SwiftUI

/// Live food diary state: mirrors the database and forwards edits to it.
@MainActor
@Observable
final class FoodStore {
    let database: AppDatabase
    let photos: FoodPhotoStore

    private(set) var snapshot: FoodSnapshot = .empty
    var lastError: String?

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
        self.photos = .standard
        if let first = try? database.foodSnapshot() { snapshot = first }
        observe()
        sweepPhotos()
    }

    private func observe() {
        observation = Task { [weak self, database] in
            do {
                for try await snapshot in database.foodUpdates() {
                    self?.snapshot = snapshot
                }
            } catch {
                self?.lastError = error.userMessage
            }
        }
    }

    private func sweepPhotos() {
        let photos = photos
        guard let referenced = try? database.referencedPhotoFiles() else { return }
        Task.detached(priority: .background) { photos.sweep(keeping: referenced) }
    }

    // MARK: Integration surface

    /// Whether the household uses the food diary (controls the rail entry).
    var isEnabled: Bool { snapshot.journal?.enabled ?? false }

    /// Logged meals for the Today agenda.
    func timelineItems(for day: DayKey) -> [TimelineItem] {
        guard isEnabled else { return [] }
        return entries(on: day).compactMap { entry in
            let id = entry.id
            var subtitle = place(of: entry).map { "\(entry.source.label) · \($0.name)" } ?? entry.source.label
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
                target: .meal(id)
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
    func recentPhotoURLs(limit: Int) -> [URL] {
        guard isEnabled, limit > 0 else { return [] }
        let meals = snapshot.entries.sorted { $0.eatenAt > $1.eatenAt }
        return Array(meals.lazy.flatMap { self.photos(of: $0).prefix(Self.ambientPhotosPerMeal) }.prefix(limit))
            .map { self.photos.url(for: $0.photoFile) }
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

    func photoURL(_ file: String?) -> URL? { file.map(photos.url(for:)) }

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

    /// Writes a photo and its thumbnail to disk off the main actor. Not attached to any
    /// meal yet: pass it to `addMeal`, `addPhotos` or an edit, or `discard` it.
    func savePhoto(_ image: UIImage) async throws -> FoodPhotoStore.Stored {
        let photos = photos
        return try await Task.detached(priority: .userInitiated) { try photos.save(image) }.value
    }

    /// Deletes saved photos that were never attached, e.g. when a capture is discarded.
    func discard(_ stored: [FoodPhotoStore.Stored]) {
        discard(files: stored.flatMap { [$0.photoFile, $0.thumbnailFile] })
    }

    /// Deletes photo files nothing uses.
    func discard(files: [String]) {
        photos.delete(files)
    }

    /// A new thumbnail of a saved photo for `crop`, written off the main actor.
    func thumbnail(of photoFile: String, crop: PhotoCrop) async throws -> String {
        let photos = photos
        return try await Task.detached(priority: .userInitiated) { try photos.thumbnail(of: photoFile, crop: crop) }.value
    }

    /// Logs a meal with its saved photos, cover first. If it throws, the caller still owns
    /// the photos (keep them for another try, or `discard` them).
    func addMeal(_ draft: MealDraft, photos stored: [FoodPhotoStore.Stored] = []) throws -> JournalEntry {
        guard let journalId = journal?.id else { throw FoodError.noJournal }
        return try database.addMeal(draft, journalId: journalId, photos: stored)
    }

    /// Adds photos to a meal that is already saved. Returns false, with `lastError` set,
    /// when they could not be added.
    @discardableResult
    func addPhotos(_ images: [UIImage], to entry: JournalEntry) async -> Bool {
        guard !images.isEmpty else { return false }
        let id = entry.id
        var stored: [FoodPhotoStore.Stored] = []
        do {
            for image in images { stored.append(try await savePhoto(image)) }
            try database.addMealPhotos(entryId: id, stored)
            lastError = nil
            return true
        } catch {
            discard(stored)
            lastError = error.userMessage
            return false
        }
    }

    /// Saves edits to a logged meal, and its photos when given. Returns false, with
    /// `lastError` set, when they are rejected.
    @discardableResult
    func updateMeal(_ entry: JournalEntry, _ draft: MealDraft, photos items: [MealPhotoItem]? = nil) -> Bool {
        let id = entry.id
        return perform { try database.updateMeal(id: id, draft, photos: items, files: photos) }
    }

    func deleteMeal(_ entry: JournalEntry) {
        let id = entry.id
        perform { try database.deleteMeal(id: id, files: photos) }
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
