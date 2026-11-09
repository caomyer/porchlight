import Foundation
import GRDB
import UIKit

// MARK: - Drafts

/// A routine as edited in setup and settings.
struct CareRoutineDraft: Equatable, Identifiable, Sendable {
    /// Stable identity for lists while editing; not stored.
    var id = UUID()
    var routineId: Int64?
    var kind: CareKind
    var title: String
    var emoji: String
    var recurrence: Recurrence
    /// The day it starts; nil means today when saved.
    var startDay: DayKey?
    var windows: [CareWindow]
    var trackedFields: [CareField]
    var stars: Int
    var nudgeAfterMinutes: Int?

    init(
        kind: CareKind,
        title: String? = nil,
        emoji: String? = nil,
        recurrence: Recurrence = .daily,
        startDay: DayKey? = nil,
        windows: [CareWindow],
        trackedFields: [CareField] = [],
        stars: Int = 1,
        nudgeAfterMinutes: Int? = nil
    ) {
        self.kind = kind
        self.title = title ?? kind.defaultTitle
        self.emoji = emoji ?? kind.defaultEmoji
        self.recurrence = recurrence
        self.startDay = startDay
        self.windows = windows
        self.trackedFields = trackedFields
        self.stars = stars
        self.nudgeAfterMinutes = nudgeAfterMinutes
    }

    init(_ routine: CareRoutine) {
        self.init(
            kind: routine.kind, title: routine.title, emoji: routine.emoji, recurrence: routine.recurrence,
            startDay: routine.anchorDay.isEmpty ? nil : routine.start, windows: routine.windows, trackedFields: routine.trackedFields,
            stars: routine.stars, nudgeAfterMinutes: routine.nudgeAfterMinutes
        )
        routineId = routine.id
    }

    /// The routine as it would be stored, for previews and the logic.
    func routine(companionId: Int64 = 0, sortOrder: Int = 0) -> CareRoutine {
        var routine = CareRoutine(
            id: routineId, companionId: companionId, kind: kind, title: title, emoji: emoji,
            everyDays: 1, windows: windows, trackedFields: trackedFields,
            stars: stars, nudgeAfterMinutes: nudgeAfterMinutes, sortOrder: sortOrder,
            anchorDay: startDay?.rawValue ?? ""
        )
        routine.recurrence = recurrence
        return routine
    }
}

/// A companion with its routines, as edited in setup and settings.
struct CompanionDraft: Equatable, Sendable {
    var companionId: Int64?
    var name: String = ""
    var species: Species = .dog
    var coat: CoatPreset = .honey
    var photoFile: String?
    var about: String = ""
    var birthDate: Date?
    var tone: CompanionTone = .cheeky
    var routines: [CareRoutineDraft] = []

    static func new(species: Species) -> CompanionDraft {
        CompanionDraft(species: species, routines: CompanionPresets.routines(for: species))
    }

    init(companionId: Int64? = nil, name: String = "", species: Species = .dog, coat: CoatPreset = .honey,
         photoFile: String? = nil, about: String = "", birthDate: Date? = nil, tone: CompanionTone = .cheeky,
         routines: [CareRoutineDraft] = []) {
        self.companionId = companionId
        self.name = name
        self.species = species
        self.coat = coat
        self.photoFile = photoFile
        self.about = about
        self.birthDate = birthDate
        self.tone = tone
        self.routines = routines
    }

    init(_ companion: Companion, routines: [CareRoutine]) {
        self.init(
            companionId: companion.id, name: companion.name, species: companion.species, coat: companion.coat,
            photoFile: companion.photoFile, about: companion.about, birthDate: companion.birthDate,
            tone: companion.captionTone, routines: routines.map(CareRoutineDraft.init)
        )
    }
}

/// What someone fills in on the log sheet.
struct CareLogDraft: Equatable, Sendable {
    var people: [Int64]
    var occurredAt: Date
    var durationMinutes: Int?
    var pee: Bool?
    var poo: Bool?
    var vibe: CareVibe?
    var note: String?
}

extension CareLogDraft {
    /// The log as it stands, for editing.
    init(_ entry: CareEntry) {
        self.init(
            people: entry.people, occurredAt: entry.log.occurredAt, durationMinutes: entry.log.durationMinutes,
            pee: entry.log.pee, poo: entry.log.poo, vibe: entry.log.vibe, note: entry.log.note
        )
    }
}

extension CareLog {
    /// Copies the draft's details, keeping only the fields the routine tracks.
    mutating func apply(_ draft: CareLogDraft, note: String?, routine: CareRoutine) {
        durationMinutes = routine.tracks(.duration) ? draft.durationMinutes : nil
        pee = routine.tracks(.pee) ? draft.pee : nil
        poo = routine.tracks(.poo) ? draft.poo : nil
        vibe = routine.tracks(.vibe) ? draft.vibe : nil
        self.note = note
    }
}

// MARK: - Validation

enum CareValidationError: Error, Equatable, LocalizedError {
    case noWindows
    case tooManyWindows(limit: Int)
    case invalidWindow(String)
    case overlappingWindows
    case invalidCadence
    case invalidStars
    case invalidNudge
    case noWalkers
    case invalidDuration
    case noteTooLong(limit: Int)
    case inTheFuture
    case unknownRoutine
    case unknownLog

    var errorDescription: String? {
        switch self {
        case .noWindows: "Add at least one time of day."
        case let .tooManyWindows(limit): "A routine can have at most \(limit) times a day."
        case let .invalidWindow(label): "\"\(label)\" needs to end after it starts."
        case .overlappingWindows: "Times of day can't overlap."
        case .invalidCadence: "Pick between every 2 and every 60 days."
        case .invalidStars: "Stars go from 0 to 10."
        case .invalidNudge: "Nudges go from 5 minutes to 12 hours."
        case .noWalkers: "Pick who did it."
        case .invalidDuration: "That duration doesn't look right."
        case let .noteTooLong(limit): "Notes can be at most \(limit) characters."
        case .inTheFuture: "That time hasn't happened yet."
        case .unknownRoutine: "That routine no longer exists."
        case .unknownLog: "That log was already removed."
        }
    }
}

enum CareRules {
    static let maxWindows = 6
    static let maxEveryDays = 60
    static let maxStars = 10
    static let noteLimit = 280

    /// Cleans up and checks a routine draft. Returns the routine to store.
    /// Checks a log's people, duration, note and time; returns the trimmed note, nil when empty.
    static func validatedNote(_ draft: CareLogDraft, now: Date) throws -> String? {
        guard !draft.people.isEmpty else { throw CareValidationError.noWalkers }
        if let duration = draft.durationMinutes, !(1...600).contains(duration) { throw CareValidationError.invalidDuration }
        let note = draft.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note, note.count > noteLimit { throw CareValidationError.noteTooLong(limit: noteLimit) }
        guard draft.occurredAt <= now.addingTimeInterval(5 * 60) else { throw CareValidationError.inTheFuture }
        return (note?.isEmpty ?? true) ? nil : note
    }

    /// `today` starts routines that have no start day yet.
    static func validated(_ draft: CareRoutineDraft, companionId: Int64, sortOrder: Int, today: DayKey = DayKey(.now, calendar: .current)) throws -> CareRoutine {
        let title = try Names.validated(draft.title)
        let emoji = draft.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.recurrence {
        case let .everyNDays(n) where !(1...maxEveryDays).contains(n): throw CareValidationError.invalidCadence
        case let .weekdays(days) where days.filter({ (1...7).contains($0) }).isEmpty: throw CareValidationError.invalidCadence
        case .once: throw CareValidationError.invalidCadence
        default: break
        }
        var windows = try draft.windows.map { window in
            let label = try Names.validated(window.label)
            guard window.start >= 0, window.end <= 24 * 60, window.start < window.end else {
                throw CareValidationError.invalidWindow(label)
            }
            return CareWindow(label, start: window.start, end: window.end)
        }
        guard !windows.isEmpty else { throw CareValidationError.noWindows }
        guard windows.count <= maxWindows else { throw CareValidationError.tooManyWindows(limit: maxWindows) }
        windows.sort { $0.start < $1.start }
        for (earlier, later) in zip(windows, windows.dropFirst()) where later.start < earlier.end {
            throw CareValidationError.overlappingWindows
        }
        guard (0...maxStars).contains(draft.stars) else { throw CareValidationError.invalidStars }
        if let nudge = draft.nudgeAfterMinutes, !(5...720).contains(nudge) { throw CareValidationError.invalidNudge }
        var fieldsSeen = Set<CareField>()
        let fields = draft.trackedFields.filter { fieldsSeen.insert($0).inserted }
        var routine = CareRoutine(
            id: draft.routineId, companionId: companionId, kind: draft.kind, title: title,
            emoji: emoji.isEmpty ? draft.kind.defaultEmoji : String(emoji.prefix(2)),
            everyDays: 1, windows: windows, trackedFields: fields,
            stars: draft.stars, nudgeAfterMinutes: draft.nudgeAfterMinutes, sortOrder: sortOrder,
            anchorDay: (draft.startDay ?? today).rawValue
        )
        routine.recurrence = draft.recurrence
        return routine
    }
}

// MARK: - Writes

extension AppDatabase {
    /// Creates or updates a companion and replaces its routines with the draft's.
    /// Routines missing from the draft are deleted along with their logs.
    @discardableResult
    func saveCompanion(_ draft: CompanionDraft, householdId: Int64, now: Date = .now) throws -> Int64 {
        let name = try Names.validated(draft.name)
        let about = draft.about.trimmingCharacters(in: .whitespacesAndNewlines)
        guard about.count <= 60 else { throw ValidationError.nameTooLong(limit: 60) }
        return try writer.write { db in
            var companion: Companion
            if let id = draft.companionId, let existing = try Companion.fetchOne(db, id: id), existing.householdId == householdId {
                companion = existing
            } else {
                let nextOrder = try Int.fetchOne(
                    db, sql: "SELECT COALESCE(MAX(sortOrder) + 1, 0) FROM companion WHERE householdId = ?", arguments: [householdId]
                ) ?? 0
                companion = Companion(
                    householdId: householdId, name: name, species: draft.species, coat: draft.coat,
                    about: about, captionTone: draft.tone, sortOrder: nextOrder, createdAt: now
                )
            }
            companion.name = name
            companion.species = draft.species
            companion.coat = draft.coat
            companion.photoFile = draft.photoFile
            companion.about = about
            companion.birthDate = draft.birthDate
            companion.captionTone = draft.tone
            try companion.save(db)
            let companionId = companion.id!
            let calendar = try Household.fetchOne(db, id: householdId)?.calendar ?? .current
            let today = DayKey(now, calendar: calendar)

            let existingIds = try Set(Int64.fetchAll(db, sql: "SELECT id FROM careRoutine WHERE companionId = ?", arguments: [companionId]))
            var keptIds = Set<Int64>()
            for (index, routineDraft) in draft.routines.enumerated() {
                var routine = try CareRules.validated(routineDraft, companionId: companionId, sortOrder: index, today: today)
                if let id = routine.id, existingIds.contains(id) {
                    try routine.update(db)
                    keptIds.insert(id)
                } else {
                    routine.id = nil
                    try routine.insert(db)
                }
            }
            for id in existingIds.subtracting(keptIds) {
                _ = try CareRoutine.deleteOne(db, id: id)
            }
            return companionId
        }
    }

    /// Removes a companion with its routines and logs. Returns its photo file, if any, to clean up.
    @discardableResult
    func deleteCompanion(id: Int64) throws -> String? {
        try writer.write { db in
            guard let companion = try Companion.fetchOne(db, id: id) else { return nil }
            _ = try Companion.deleteOne(db, id: id)
            let rest = try Companion
                .filter(Column("householdId") == companion.householdId)
                .order(Column("sortOrder"), Column("id"))
                .fetchAll(db)
            for (index, var other) in rest.enumerated() where other.sortOrder != index {
                other.sortOrder = index
                try other.update(db)
            }
            return companion.photoFile
        }
    }

    /// Records that people did a routine.
    @discardableResult
    func logCare(routineId: Int64, _ draft: CareLogDraft, now: Date = .now) throws -> CareLog {
        let note = try CareRules.validatedNote(draft, now: now)
        return try writer.write { db in
            guard let routine = try CareRoutine.fetchOne(db, id: routineId) else { throw CareValidationError.unknownRoutine }
            var log = CareLog(careRoutineId: routineId, occurredAt: draft.occurredAt, stars: routine.stars, createdAt: now)
            log.apply(draft, note: note, routine: routine)
            try log.insert(db)
            try Self.replacePeople(of: log.id!, with: draft.people, in: db)
            return log
        }
    }

    /// Fixes a logged routine: who, when, how long and the details. The routine and
    /// the stars it earned stay as they were.
    func updateCareLog(id: Int64, _ draft: CareLogDraft, now: Date = .now) throws -> CareLog {
        let note = try CareRules.validatedNote(draft, now: now)
        return try writer.write { db in
            guard var log = try CareLog.fetchOne(db, id: id) else { throw CareValidationError.unknownLog }
            guard let routine = try CareRoutine.fetchOne(db, id: log.careRoutineId) else { throw CareValidationError.unknownRoutine }
            log.occurredAt = draft.occurredAt
            log.apply(draft, note: note, routine: routine)
            try log.update(db)
            try CareLogPerson.filter(Column("careLogId") == id).deleteAll(db)
            try Self.replacePeople(of: id, with: draft.people, in: db)
            return log
        }
    }

    private static func replacePeople(of logId: Int64, with people: [Int64], in db: Database) throws {
        var seen = Set<Int64>()
        for personId in people where seen.insert(personId).inserted {
            try CareLogPerson(careLogId: logId, personId: personId).insert(db)
        }
    }

    func deleteCareLog(id: Int64) throws {
        try writer.write { db in
            _ = try CareLog.deleteOne(db, id: id)
        }
    }

    /// Persists a new companion order, given ids in display order.
    func reorderCompanions(householdId: Int64, ids: [Int64]) throws {
        try writer.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE companion SET sortOrder = ? WHERE id = ? AND householdId = ?",
                    arguments: [index, id, householdId]
                )
            }
        }
    }
}

// MARK: - Photos

/// Companion photos live as JPEG files in Application Support; the database keeps the file name.
struct CompanionPhotoStore: Sendable {
    let folder: URL

    static let shared: CompanionPhotoStore = {
        CompanionPhotoStore(folder: AppFiles.folder("CompanionPhotos"))
    }()

    func url(for fileName: String) -> URL {
        folder.appendingPathComponent(fileName)
    }

    /// Saves picked image data as a square-ish JPEG no larger than 800 pt. Returns the file name.
    func save(imageData: Data) throws -> String {
        guard let image = UIImage(data: imageData) else { throw CocoaError(.fileReadCorruptFile) }
        let scale = min(1, 800 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: url(for: name), options: .atomic)
        return name
    }

    func image(named fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: fileName).path)
    }

    func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
