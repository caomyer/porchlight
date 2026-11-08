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
            guard let id = entry.id else { return nil }
            var subtitle = entry.source.label
            if let rating = entry.rating { subtitle += " · \(rating.emoji) \(rating.phrase)" }
            return TimelineItem(
                id: "food-\(id)",
                kind: .log,
                time: entry.eatenAt,
                title: "\(entry.slot) · \(entry.title)",
                subtitle: subtitle,
                owner: owner(of: entry),
                leading: AnyView(MealThumbnail(entry: entry, size: 34)),
                trailing: AnyView(EaterBadge(people: eaters(of: entry), everyone: ateTogether(entry), size: 30))
            )
        }
    }

    /// Mini-plate lanes for the week grid and month cells.
    func calendarLanes() -> [CalendarLane] {
        guard isEnabled else { return [] }
        return [
            CalendarLane(
                id: "meals",
                label: AnyView(MealsLaneLabel()),
                title: "meals",
                cell: { [self] day, style in AnyView(MealPlatesCell(store: self, day: day, style: style)) }
            ),
        ]
    }

    /// Recent meal photos, offered to Ambient mode as a photo source.
    func recentPhotoURLs(limit: Int) -> [URL] {
        guard isEnabled, limit > 0 else { return [] }
        return snapshot.entries
            .filter { $0.photoFile != nil }
            .sorted { $0.eatenAt > $1.eatenAt }
            .prefix(limit)
            .compactMap { $0.photoFile.map(photos.url(for:)) }
    }

    // MARK: Reads

    var journal: Journal? { snapshot.journal }
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

    func eaters(of entry: JournalEntry) -> [Person] {
        guard let id = entry.id else { return [] }
        let ids = snapshot.eaters[id] ?? []
        return ids.compactMap { personId in people.first { $0.id == personId } }
    }

    /// Everyone in the household ate it (shown as ♥).
    func ateTogether(_ entry: JournalEntry) -> Bool {
        let eaters = eaters(of: entry)
        return eaters.isEmpty || (people.count > 1 && eaters.count == people.count)
    }

    func owner(of entry: JournalEntry) -> Owner {
        let eaters = eaters(of: entry)
        if eaters.count == 1, let id = eaters[0].id, !ateTogether(entry) { return .person(id) }
        return .everyone
    }

    func photoURL(_ file: String?) -> URL? { file.map(photos.url(for:)) }

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
        FoodMemory.find(in: snapshot.entries, today: today, calendar: calendar)
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

    /// Saves the photo (off the main actor), then the meal and the day's page together.
    func addMeal(_ draft: MealDraft, photo: UIImage?, page: PKDrawing?) async throws -> JournalEntry {
        guard let journalId = journal?.id else { throw FoodError.noJournal }
        let photos = photos
        let stored = try await Task.detached(priority: .userInitiated) {
            try photo.map { try photos.save($0) }
        }.value
        return try database.addMeal(draft, journalId: journalId, photo: stored, page: page?.dataRepresentation(), photos: photos)
    }

    /// Saves edits to a logged meal. Returns false, with `lastError` set, when they are rejected.
    @discardableResult
    func updateMeal(_ entry: JournalEntry, _ draft: MealDraft) -> Bool {
        guard let id = entry.id else { return false }
        return perform { try database.updateMeal(id: id, draft) }
    }

    func deleteMeal(_ entry: JournalEntry) {
        guard let id = entry.id else { return }
        perform { try database.deleteMeal(id: id, photos: photos) }
    }

    /// Turns the diary on or off, creating it the first time.
    func setEnabled(_ enabled: Bool) {
        guard let householdId = snapshot.household?.id else { return }
        perform {
            let journal = try database.ensureFoodJournal(householdId: householdId, enabled: enabled)
            if journal.enabled != enabled, let id = journal.id { try database.setJournalEnabled(id: id, enabled) }
        }
    }

    func setSlot(_ slot: String, on: Bool) {
        guard let journal, let id = journal.id else { return }
        var slots = journal.slots.filter { $0 != slot }
        if on { slots.append(slot) }
        perform { try database.setJournalSlots(id: id, slots) }
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
