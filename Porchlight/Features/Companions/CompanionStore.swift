import Foundation
import GRDB
import Observation
import SwiftUI

/// One companion as the rail needs it.
struct CompanionSummary: Identifiable, Equatable, Sendable {
    var id: Companion.ID
    var name: String
}

/// Everything about companions, read in one consistent snapshot.
struct CompanionSnapshot: Equatable, Sendable {
    var household: Household?
    /// The people who live here now, for pickers.
    var people: [Person] = []
    /// Everyone, removed people included, for naming who did past care.
    var everyone: [Person] = []
    var companions: [Companion] = []
    /// The size of each companion's photo, for those that have one.
    var photos: [Companion.ID: Int] = [:]
    /// Ordered by companion, then sort order.
    var routines: [CareRoutine] = []
    /// Every care log with its people, oldest first.
    var entries: [CareEntry] = []

    static let empty = CompanionSnapshot()

    static func fetch(_ db: Database) throws -> CompanionSnapshot {
        guard let household = try Household.current(db) else { return .empty }
        let householdId = household.id
        let everyone = try Person.everyone(in: householdId).fetchAll(db)
        let companions = try Companion
            .filter(Column("householdId") == householdId)
            .order(Column("sortOrder"), Column("createdAt"), Column("id"))
            .fetchAll(db)
        // Routines have no creation time; their id only keeps equal sort orders stable.
        let routines = try CareRoutine.fetchAll(db, sql: """
            SELECT careRoutine.* FROM careRoutine
            JOIN companion ON companion.id = careRoutine.companionId
            WHERE companion.householdId = ?
            ORDER BY companion.sortOrder, companion.createdAt, companion.id, careRoutine.sortOrder, careRoutine.id
            """, arguments: [householdId])
        let logs = try CareLog.fetchAll(db, sql: """
            SELECT careLog.* FROM careLog
            JOIN careRoutine ON careRoutine.id = careLog.careRoutineId
            JOIN companion ON companion.id = careRoutine.companionId
            WHERE companion.householdId = ?
            ORDER BY careLog.occurredAt, careLog.createdAt, careLog.id
            """, arguments: [householdId])
        // Only the sizes: the photos themselves load when a face shows them.
        let photoRows = try Row.fetchAll(db, sql: """
            SELECT companionPhoto.companionId, companionPhoto.byteCount FROM companionPhoto
            JOIN companion ON companion.id = companionPhoto.companionId
            WHERE companion.householdId = ?
            """, arguments: [householdId])
        let photos = Dictionary(uniqueKeysWithValues: photoRows.map { ($0["companionId"] as Companion.ID, $0["byteCount"] as Int) })
        let order = Dictionary(uniqueKeysWithValues: everyone.enumerated().map { index, person in (person.id, index) })
        var peopleByLog: [CareLog.ID: [Person.ID]] = [:]
        for link in try CareLogPerson.fetchAll(db) {
            peopleByLog[link.careLogId, default: []].append(link.personId)
        }
        let entries = logs.map { log in
            let people = (peopleByLog[log.id] ?? []).sorted { (order[$0] ?? .max, $0) < (order[$1] ?? .max, $1) }
            return CareEntry(log: log, people: people)
        }
        return CompanionSnapshot(
            household: household, people: everyone.active, everyone: everyone,
            companions: companions, photos: photos, routines: routines, entries: entries
        )
    }

    /// How a saved companion looks, with its photo when it has one.
    func look(of companion: Companion) -> CompanionLook {
        CompanionLook(companion, photo: photos[companion.id].map { .companion(companion.id, byteCount: $0) })
    }

    var calendar: Calendar { household?.calendar ?? .current }

    func routines(of companionId: Companion.ID) -> [CareRoutine] {
        routines.filter { $0.companionId == companionId }
    }

    func entries(of routineId: CareRoutine.ID?) -> [CareEntry] {
        guard let routineId else { return [] }
        return entries.filter { $0.log.careRoutineId == routineId }
    }

    /// Anyone who ever lived here, so past care keeps its name; nil for an id that
    /// points at nobody.
    func person(_ id: Person.ID) -> Person? {
        everyone.person(id)
    }

    /// Names of everyone, removed people included.
    var names: [Person.ID: String] {
        Dictionary(everyone.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}

/// "Now" for companion screens, the sample household and the phone's writes. DEBUG
/// builds can pin it with the `-debugCompanionNow 2026-11-07T18:05` launch argument for
/// screenshots and UI tests.
enum CompanionClock {
    static func now() -> Date {
        #if DEBUG
        if let text = UserDefaults.standard.string(forKey: "debugCompanionNow") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            if let date = formatter.date(from: text) { return date }
        }
        #endif
        return .now
    }
}

/// Live companion state: mirrors the database and forwards edits to it.
@MainActor
@Observable
final class CompanionStore {
    let database: AppDatabase
    private(set) var snapshot: CompanionSnapshot = .empty
    var lastError: String?

    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var reportCache: [String: CompanionReport] = [:]

    init(database: AppDatabase) {
        self.database = database
        if let first = try? database.writer.read(CompanionSnapshot.fetch) {
            snapshot = first
        }
        observe()
    }

    var companions: [CompanionSummary] {
        snapshot.companions.map { CompanionSummary(id: $0.id, name: $0.name) }
    }

    private func observe() {
        observation = Task { [weak self, database] in
            do {
                let updates = ValueObservation
                    .tracking(CompanionSnapshot.fetch)
                    .removeDuplicates()
                    .values(in: database.writer)
                for try await snapshot in updates {
                    self?.apply(snapshot)
                }
            } catch {
                self?.lastError = error.userMessage
            }
        }
    }

    private func apply(_ snapshot: CompanionSnapshot) {
        // Store first, then drop cached reports. Observers hear about the change in
        // `willSet`, so a report built then still sees the old snapshot; clearing
        // afterwards keeps it from outliving the change.
        self.snapshot = snapshot
        reportCache = [:]
    }

    // MARK: Reads

    func companion(_ id: Companion.ID) -> Companion? {
        snapshot.companions.first { $0.id == id }
    }

    /// Everything a companion's card and page show, as of `now` (cached per minute).
    func report(for companionId: Companion.ID, now: Date = CompanionClock.now()) -> CompanionReport? {
        // Read the snapshot even on a cache hit, so views that only ask for a report
        // still refresh when a log is added, fixed or removed.
        let snapshot = snapshot
        let minute = Int(now.timeIntervalSince1970 / 60)
        let key = "\(companionId)-\(minute)"
        if let cached = reportCache[key] { return cached }
        guard let report = CompanionReport.make(snapshot: snapshot, companionId: companionId, now: now) else { return nil }
        if reportCache.count > 64 { reportCache = [:] }
        reportCache[key] = report
        return report
    }

    /// Today's companion care, slot by slot, for the Pitch in board.
    func careTasks(now: Date = CompanionClock.now()) -> [CareTask] {
        companions.flatMap { summary -> [CareTask] in
            guard let report = report(for: summary.id, now: now) else { return [] }
            return ([report.primary].compactMap { $0 } + report.others).flatMap { today in
                today.slots.map { CareTask(companionId: summary.id, companionName: summary.name, routine: today.routine, slot: $0) }
            }
        }
    }

    /// Walks and expected walks for the Today agenda.
    func timelineItems(for day: DayKey) -> [TimelineItem] {
        CompanionTimeline.items(snapshot: snapshot, day: day, now: CompanionClock.now())
    }

    /// Paw lanes for the week grid and month cells.
    func calendarLanes() -> [CalendarLane] {
        CompanionLanes.lanes(snapshot: snapshot)
    }

    // MARK: Edits (errors are surfaced through `lastError`)

    /// A saved companion as a draft to edit, with its routines and photo.
    func draft(of companion: Companion) -> CompanionDraft {
        CompanionDraft(companion, routines: snapshot.routines(of: companion.id), photo: try? database.companionPhoto(id: companion.id))
    }

    /// Saves a companion draft. Returns the companion id, or nil when validation failed.
    @discardableResult
    func save(_ draft: CompanionDraft) -> Companion.ID? {
        guard let householdId = snapshot.household?.id ?? (try? database.snapshot().household?.id) else { return nil }
        do {
            let id = try database.saveCompanion(draft, householdId: householdId)
            lastError = nil
            return id
        } catch {
            lastError = error.userMessage
            return nil
        }
    }

    func delete(companionId: Companion.ID) {
        perform { try database.deleteCompanion(id: companionId) }
    }

    @discardableResult
    func log(routineId: CareRoutine.ID, _ draft: CareLogDraft, now: Date = .now) -> CareLog? {
        do {
            let log = try database.logCare(routineId: routineId, draft, now: now)
            lastError = nil
            return log
        } catch {
            lastError = error.userMessage
            return nil
        }
    }

    /// Logs one slot of a day unless someone already did it, in which case their log
    /// comes back instead. Nil, with `lastError` set, when the log is rejected.
    func log(routineId: CareRoutine.ID, slot: Int, on day: DayKey, _ draft: CareLogDraft, now: Date = CompanionClock.now()) -> CareSlotLog? {
        do {
            let result = try database.logCare(routineId: routineId, slot: slot, on: day, draft, now: now)
            lastError = nil
            return result
        } catch {
            lastError = error.userMessage
            return nil
        }
    }

    /// Adds people to a log ("I went too").
    @discardableResult
    func addPeople(_ people: [Person.ID], toLog id: CareLog.ID) -> Bool {
        perform { try database.addPeople(people, toCareLog: id) }
    }

    /// Takes people off a log again.
    @discardableResult
    func removePeople(_ people: [Person.ID], fromLog id: CareLog.ID) -> Bool {
        perform { try database.removePeople(people, fromCareLog: id) }
    }

    /// Saves edits to a log. Returns false, with `lastError` set, when they are rejected.
    @discardableResult
    func updateLog(id: CareLog.ID, _ draft: CareLogDraft) -> Bool {
        perform { _ = try database.updateCareLog(id: id, draft) }
    }

    func deleteLog(id: CareLog.ID) {
        perform { try database.deleteCareLog(id: id) }
    }

    func moveCompanions(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let householdId = snapshot.household?.id else { return }
        var ids = snapshot.companions.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        perform { try database.reorderCompanions(householdId: householdId, ids: ids) }
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
