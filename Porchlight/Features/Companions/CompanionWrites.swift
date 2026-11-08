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
    var everyDays: Int
    var windows: [CareWindow]
    var rotation: [Int64]
    var trackedFields: [CareField]
    var stars: Int
    var nudgeAfterMinutes: Int?

    init(
        kind: CareKind,
        title: String? = nil,
        emoji: String? = nil,
        everyDays: Int = 1,
        windows: [CareWindow],
        rotation: [Int64] = [],
        trackedFields: [CareField] = [],
        stars: Int = 1,
        nudgeAfterMinutes: Int? = nil
    ) {
        self.kind = kind
        self.title = title ?? kind.defaultTitle
        self.emoji = emoji ?? kind.defaultEmoji
        self.everyDays = everyDays
        self.windows = windows
        self.rotation = rotation
        self.trackedFields = trackedFields
        self.stars = stars
        self.nudgeAfterMinutes = nudgeAfterMinutes
    }

    init(_ routine: CareRoutine) {
        self.init(
            kind: routine.kind, title: routine.title, emoji: routine.emoji, everyDays: routine.everyDays,
            windows: routine.windows, rotation: routine.rotation, trackedFields: routine.trackedFields,
            stars: routine.stars, nudgeAfterMinutes: routine.nudgeAfterMinutes
        )
        routineId = routine.id
    }

    /// The routine as it would be stored, for previews and the logic.
    func routine(companionId: Int64 = 0, sortOrder: Int = 0) -> CareRoutine {
        CareRoutine(
            id: routineId, companionId: companionId, kind: kind, title: title, emoji: emoji,
            everyDays: max(everyDays, 1), windows: windows, rotation: rotation, trackedFields: trackedFields,
            stars: stars, nudgeAfterMinutes: nudgeAfterMinutes, sortOrder: sortOrder
        )
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

    static func new(species: Species, rotation: [Int64]) -> CompanionDraft {
        CompanionDraft(species: species, routines: CompanionPresets.routines(for: species, rotation: rotation))
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
        }
    }
}

enum CareRules {
    static let maxWindows = 6
    static let maxEveryDays = 60
    static let maxStars = 10
    static let noteLimit = 280

    /// Cleans up and checks a routine draft. Returns the routine to store.
    static func validated(_ draft: CareRoutineDraft, companionId: Int64, sortOrder: Int, people: Set<Int64>) throws -> CareRoutine {
        let title = try Names.validated(draft.title)
        let emoji = draft.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.everyDays >= 1, draft.everyDays <= maxEveryDays else { throw CareValidationError.invalidCadence }
        var windows = try draft.windows.map { window in
            let label = try Names.validated(window.label)
            guard window.start >= 0, window.end <= 24 * 60, window.start < window.end else {
                throw CareValidationError.invalidWindow(label)
            }
            return CareWindow(label, start: window.start, end: window.end)
        }
        guard !windows.isEmpty else { throw CareValidationError.noWindows }
        if draft.everyDays > 1 { windows = Array(windows.prefix(1)) }
        guard windows.count <= maxWindows else { throw CareValidationError.tooManyWindows(limit: maxWindows) }
        windows.sort { $0.start < $1.start }
        for (earlier, later) in zip(windows, windows.dropFirst()) where later.start < earlier.end {
            throw CareValidationError.overlappingWindows
        }
        guard (0...maxStars).contains(draft.stars) else { throw CareValidationError.invalidStars }
        if let nudge = draft.nudgeAfterMinutes, !(5...720).contains(nudge) { throw CareValidationError.invalidNudge }
        var seen = Set<Int64>()
        let rotation = draft.rotation.filter { people.contains($0) && seen.insert($0).inserted }
        var fieldsSeen = Set<CareField>()
        let fields = draft.trackedFields.filter { fieldsSeen.insert($0).inserted }
        return CareRoutine(
            id: draft.routineId, companionId: companionId, kind: draft.kind, title: title,
            emoji: emoji.isEmpty ? draft.kind.defaultEmoji : String(emoji.prefix(2)),
            everyDays: draft.everyDays, windows: windows, rotation: rotation, trackedFields: fields,
            stars: draft.stars, nudgeAfterMinutes: draft.nudgeAfterMinutes, sortOrder: sortOrder
        )
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
            let people = try Set(Int64.fetchAll(db, sql: "SELECT id FROM person WHERE householdId = ?", arguments: [householdId]))
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

            let existingIds = try Set(Int64.fetchAll(db, sql: "SELECT id FROM careRoutine WHERE companionId = ?", arguments: [companionId]))
            var keptIds = Set<Int64>()
            for (index, routineDraft) in draft.routines.enumerated() {
                var routine = try CareRules.validated(routineDraft, companionId: companionId, sortOrder: index, people: people)
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
        guard !draft.people.isEmpty else { throw CareValidationError.noWalkers }
        if let duration = draft.durationMinutes, !(1...600).contains(duration) { throw CareValidationError.invalidDuration }
        let note = draft.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note, note.count > CareRules.noteLimit { throw CareValidationError.noteTooLong(limit: CareRules.noteLimit) }
        guard draft.occurredAt <= now.addingTimeInterval(5 * 60) else { throw CareValidationError.inTheFuture }
        return try writer.write { db in
            guard let routine = try CareRoutine.fetchOne(db, id: routineId) else { throw CareValidationError.unknownRoutine }
            var log = CareLog(
                careRoutineId: routineId,
                occurredAt: draft.occurredAt,
                durationMinutes: routine.tracks(.duration) ? draft.durationMinutes : nil,
                pee: routine.tracks(.pee) ? draft.pee : nil,
                poo: routine.tracks(.poo) ? draft.poo : nil,
                vibe: routine.tracks(.vibe) ? draft.vibe : nil,
                note: (note?.isEmpty ?? true) ? nil : note,
                stars: routine.stars,
                createdAt: now
            )
            try log.insert(db)
            var seen = Set<Int64>()
            for personId in draft.people where seen.insert(personId).inserted {
                try CareLogPerson(careLogId: log.id!, personId: personId).insert(db)
            }
            return log
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
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return CompanionPhotoStore(folder: base.appendingPathComponent("Porchlight/CompanionPhotos", isDirectory: true))
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
