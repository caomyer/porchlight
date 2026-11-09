import Foundation
import GRDB
import Observation
import SwiftUI

/// One companion as the rail needs it.
struct CompanionSummary: Identifiable, Equatable, Sendable {
    var id: Int64
    var name: String
}

/// Everything about companions, read in one consistent snapshot.
struct CompanionSnapshot: Equatable, Sendable {
    var household: Household?
    var people: [Person] = []
    var companions: [Companion] = []
    /// Ordered by companion, then sort order.
    var routines: [CareRoutine] = []
    /// Every care log with its people, oldest first.
    var entries: [CareEntry] = []

    static let empty = CompanionSnapshot()

    static func fetch(_ db: Database) throws -> CompanionSnapshot {
        guard let household = try Household.order(Column("id")).fetchOne(db), let householdId = household.id else { return .empty }
        let people = try Person
            .filter(Column("householdId") == householdId)
            .order(Column("sortOrder"), Column("id"))
            .fetchAll(db)
        let companions = try Companion
            .filter(Column("householdId") == householdId)
            .order(Column("sortOrder"), Column("id"))
            .fetchAll(db)
        let routines = try CareRoutine.fetchAll(db, sql: """
            SELECT careRoutine.* FROM careRoutine
            JOIN companion ON companion.id = careRoutine.companionId
            WHERE companion.householdId = ?
            ORDER BY companion.sortOrder, companion.id, careRoutine.sortOrder, careRoutine.id
            """, arguments: [householdId])
        let logs = try CareLog.fetchAll(db, sql: """
            SELECT careLog.* FROM careLog
            JOIN careRoutine ON careRoutine.id = careLog.careRoutineId
            JOIN companion ON companion.id = careRoutine.companionId
            WHERE companion.householdId = ?
            ORDER BY careLog.occurredAt, careLog.id
            """, arguments: [householdId])
        let order = Dictionary(uniqueKeysWithValues: people.enumerated().compactMap { index, person in person.id.map { ($0, index) } })
        var peopleByLog: [Int64: [Int64]] = [:]
        for link in try CareLogPerson.fetchAll(db) {
            peopleByLog[link.careLogId, default: []].append(link.personId)
        }
        let entries = logs.map { log in
            let people = (peopleByLog[log.id ?? -1] ?? []).sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
            return CareEntry(log: log, people: people)
        }
        return CompanionSnapshot(household: household, people: people, companions: companions, routines: routines, entries: entries)
    }

    var calendar: Calendar { household?.calendar ?? .current }

    func routines(of companionId: Int64) -> [CareRoutine] {
        routines.filter { $0.companionId == companionId }
    }

    func entries(of routineId: Int64?) -> [CareEntry] {
        guard let routineId else { return [] }
        return entries.filter { $0.log.careRoutineId == routineId }
    }

    func person(_ id: Int64) -> Person? {
        people.first { $0.id == id }
    }

    var names: [Int64: String] {
        Dictionary(uniqueKeysWithValues: people.compactMap { person in person.id.map { ($0, person.name) } })
    }
}

/// "Now" for companion screens. DEBUG builds can pin it with the
/// `-debugCompanionNow 2026-11-07T18:05` launch argument for screenshots.
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
        snapshot.companions.compactMap { companion in companion.id.map { CompanionSummary(id: $0, name: companion.name) } }
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

    func companion(_ id: Int64) -> Companion? {
        snapshot.companions.first { $0.id == id }
    }

    /// Everything a companion's card and page show, as of `now` (cached per minute).
    func report(for companionId: Int64, now: Date = CompanionClock.now()) -> CompanionReport? {
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

    /// Walks and expected walks for the Today agenda.
    func timelineItems(for day: DayKey) -> [TimelineItem] {
        CompanionTimeline.items(snapshot: snapshot, day: day, now: CompanionClock.now())
    }

    /// Paw lanes for the week grid and month cells.
    func calendarLanes() -> [CalendarLane] {
        CompanionLanes.lanes(snapshot: snapshot)
    }

    // MARK: Edits (errors are surfaced through `lastError`)

    /// Saves a companion draft. Returns the companion id, or nil when validation failed.
    @discardableResult
    func save(_ draft: CompanionDraft, previousPhoto: String? = nil) -> Int64? {
        guard let householdId = snapshot.household?.id ?? (try? database.snapshot().household?.id) else { return nil }
        do {
            let id = try database.saveCompanion(draft, householdId: householdId)
            if let previousPhoto, previousPhoto != draft.photoFile {
                CompanionPhotoStore.shared.delete(previousPhoto)
            }
            lastError = nil
            return id
        } catch {
            lastError = error.userMessage
            return nil
        }
    }

    func delete(companionId: Int64) {
        perform {
            if let photo = try database.deleteCompanion(id: companionId) {
                CompanionPhotoStore.shared.delete(photo)
            }
        }
    }

    @discardableResult
    func log(routineId: Int64, _ draft: CareLogDraft) -> CareLog? {
        do {
            let log = try database.logCare(routineId: routineId, draft)
            lastError = nil
            return log
        } catch {
            lastError = error.userMessage
            return nil
        }
    }

    /// Saves edits to a log. Returns false, with `lastError` set, when they are rejected.
    @discardableResult
    func updateLog(id: Int64, _ draft: CareLogDraft) -> Bool {
        perform { _ = try database.updateCareLog(id: id, draft) }
    }

    func deleteLog(id: Int64) {
        perform { try database.deleteCareLog(id: id) }
    }

    func moveCompanions(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let householdId = snapshot.household?.id else { return }
        var ids = snapshot.companions.compactMap(\.id)
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
