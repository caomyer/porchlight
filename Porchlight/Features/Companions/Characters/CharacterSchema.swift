import Foundation
import GRDB

// A companion's face beyond its photo: the photo sticker made on a device, a character drawn
// in the house style, and which face the household chose (docs/design/companion-characters.md).

// MARK: - Tables

extension SyncSchema {
    /// The tables "characters v1" adds, both under the companion: an updating device puts
    /// new tables' rows in, table by table, in no set order, so the pictures hang off the
    /// companion every device already has, never off the new face row.
    static let characterTables: [Table] = [
        // The face the household chose for a companion, and how its character is drawn; one per
        // companion that has chosen, keyed by the companion.
        Table(name: "companionCharacter", parent: "companion", columns: """
            "companionId" TEXT PRIMARY KEY NOT NULL REFERENCES "companion"("id") ON DELETE CASCADE,
            "face" TEXT NOT NULL, "style" TEXT NOT NULL, "personId" TEXT, "chosenAt" TEXT NOT NULL
            """),
        // One per companion, set (sticker or character), mood and kind of picture. `byteCount`
        // before `image`, so reading it never walks the picture's pages.
        Table(name: "companionCharacterImage", parent: "companion", columns: """
            \(id), \(parent("companionId", "companion")), "source" TEXT NOT NULL, "mood" TEXT NOT NULL,
            "kind" TEXT NOT NULL, "frameCount" INTEGER NOT NULL, "byteCount" INTEGER NOT NULL, "image" BLOB NOT NULL
            """),
    ]
}

extension AppDatabase {
    static let characterMigration = "characters v1: a companion's face, its sticker and its character"

    static func registerCharacterMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(characterMigration) { db in
            for table in SyncSchema.characterTables {
                try db.execute(sql: "CREATE TABLE \"\(table.name)\" (\(table.columns)) STRICT")
            }
            try db.execute(sql: #"CREATE INDEX "companionCharacterImage_on_companionId" ON "companionCharacterImage"("companionId")"#)
        }
    }
}

// MARK: - Records

/// Which face shows for a companion, everywhere, for the whole household.
enum CompanionFaceChoice: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    /// The character drawn in the house style.
    case character
    /// The photo sticker.
    case sticker
    /// The photo in a circle.
    case photo
    /// The drawn dog or cat face, or the emoji, as for a companion with no photo.
    case drawn

    func label(species: Species) -> String {
        switch self {
        case .character: "Character"
        case .sticker: "Photo sticker"
        case .photo: "Photo"
        case .drawn: species.hasDrawnFace ? "Drawn face" : "Emoji"
        }
    }
}

/// Which set a picture belongs to: a companion can have both, and switching between them
/// redraws nothing.
enum FaceSource: String, Codable, Sendable, DatabaseValueConvertible {
    case sticker
    case character
}

/// How a character is drawn. One house style for every pet.
enum CharacterStyle: String, Codable, Sendable, DatabaseValueConvertible {
    case pixel
}

/// How a companion is doing, as its character shows it (docs/design/companion-characters.md,
/// "Moods follow the day").
enum CharacterMood: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case fine
    case waiting
    case zoomies
    case asleep

    var label: String {
        switch self {
        case .fine: "Doing fine"
        case .waiting: "Waiting"
        case .zoomies: "Zoomies"
        case .asleep: "Asleep"
        }
    }
}

/// A picture: one still, or a strip of animation frames side by side.
enum CharacterImageKind: String, Codable, Sendable, DatabaseValueConvertible {
    case still
    case frames
}

/// The face a household chose for a companion, keyed by the companion.
struct CompanionCharacter: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    var companionId: Companion.ID
    var face: CompanionFaceChoice
    var style: CharacterStyle = .pixel
    /// Who chose it, when someone did.
    var personId: Person.ID?
    var chosenAt: Date
}

/// One picture of a companion's sticker or character.
///
/// A still is a PNG on clear, `stillSide` pixels square: the sticker as `PhotoSticker`
/// draws it, a character's mood as the relay sends it. An animation (kind `frames`) is one
/// PNG strip of `frameCount` square frames side by side, each `frameSide` pixels, scaled
/// down from the relay's GIF without smoothing; pixel art keeps it small. Keyed by companion,
/// set, mood and kind (`id(companionId:source:mood:kind:)`).
struct CharacterImage: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    typealias ID = Porchlight.ID<CharacterImage>
    static let databaseTableName = "companionCharacterImage"
    static let stillSide = 512
    static let frameSide = 256

    var id: ID
    var companionId: Companion.ID
    var source: FaceSource
    var mood: CharacterMood
    var kind: CharacterImageKind
    /// 1 for a still; the strip's frames, side by side, for an animation.
    var frameCount: Int
    var byteCount: Int
    var image: Data

    init(companionId: Companion.ID, source: FaceSource, mood: CharacterMood = .fine, kind: CharacterImageKind = .still, frameCount: Int = 1, image: Data) {
        id = Self.id(companionId: companionId, source: source, mood: mood, kind: kind)
        self.companionId = companionId
        self.source = source
        self.mood = mood
        self.kind = kind
        self.frameCount = frameCount
        byteCount = image.count
        self.image = image
    }

    /// Derived, so a picture redrawn on two devices at once is one row, not two.
    static func id(companionId: Companion.ID, source: FaceSource, mood: CharacterMood, kind: CharacterImageKind) -> ID {
        .derived(companionId.description, "face", source.rawValue, mood.rawValue, kind.rawValue)
    }
}

/// A companion's face beyond its photo, as the screens draw it: the face chosen, and which
/// pictures there are, by their sizes, so a picture that changes (or arrives by sync) is
/// never shown from the cache as the old one.
struct CharacterLook: Equatable, Sendable {
    struct Picture: Equatable, Sendable {
        var id: CharacterImage.ID
        var byteCount: Int
        var frameCount: Int
    }

    /// Nil until someone chooses: the photo, or the drawn face when there is none.
    var face: CompanionFaceChoice?
    var sticker: Picture?
    var stills: [CharacterMood: Picture] = [:]
    var frames: [CharacterMood: Picture] = [:]

    /// A character is drawn once its still for doing fine is here; until then, not at all.
    var hasCharacter: Bool { stills[.fine] != nil }
    var hasSticker: Bool { sticker != nil }

    /// The character's still for `mood`, else its one for doing fine.
    func still(_ mood: CharacterMood) -> Picture? {
        stills[mood] ?? stills[.fine]
    }

    /// The character's animation for `mood`, if it has one.
    func animation(_ mood: CharacterMood) -> Picture? {
        frames[mood]
    }

    /// What a face shows: the chosen one when it is here, else the photo or drawn face.
    var shown: CompanionFaceChoice? {
        switch face {
        case .character: hasCharacter ? .character : nil
        case .sticker: hasSticker ? .sticker : nil
        case .drawn: .drawn
        case .photo, nil: nil
        }
    }
}

// MARK: - Writes

enum CharacterError: Error, Equatable, LocalizedError {
    case unknownCompanion
    /// The face chosen isn't there for this companion (no character, sticker or photo).
    case faceNotAvailable

    var errorDescription: String? {
        switch self {
        case .unknownCompanion: "That companion is no longer here."
        case .faceNotAvailable: "That face isn't there anymore. Pick another one."
        }
    }
}

extension AppDatabase {
    /// Saves `sticker` (a PNG) as the companion's photo sticker and shows it, keeping any
    /// character; `photo` becomes its photo when the sticker was cut from one picked just now.
    func saveSticker(_ sticker: Data, photo: Data? = nil, companionId: Companion.ID, by person: Person.ID?, now: Date = .now) throws {
        try writer.write { db in
            guard try Companion.exists(db, key: companionId) else { throw CharacterError.unknownCompanion }
            if let photo {
                let saved = try Data.fetchOne(db, sql: "SELECT image FROM companionPhoto WHERE companionId = ?", arguments: [companionId])
                if saved != photo { try CompanionPhoto(companionId: companionId, image: photo).upsert(db) }
            }
            try Self.replace(.sticker, of: companionId, with: [CharacterImage(companionId: companionId, source: .sticker, image: sticker)], db: db)
            try Self.choose(.sticker, companionId: companionId, by: person, now: now, db: db)
        }
    }

    /// Shows `face` for the companion, everywhere. Nothing is drawn or deleted: a character or
    /// sticker not shown stays, and showing it again costs nothing.
    func chooseFace(_ face: CompanionFaceChoice, companionId: Companion.ID, by person: Person.ID?, now: Date = .now) throws {
        try writer.write { db in
            guard try Companion.exists(db, key: companionId) else { throw CharacterError.unknownCompanion }
            guard try Self.available(db, companionId: companionId).contains(face) else { throw CharacterError.faceNotAvailable }
            try Self.choose(face, companionId: companionId, by: person, now: now, db: db)
        }
    }

    /// Deletes the companion's character for everyone. If it was shown, the sticker shows
    /// instead when there is one, else the photo.
    func removeCharacter(companionId: Companion.ID, by person: Person.ID?, now: Date = .now) throws {
        try writer.write { db in
            try CharacterImage.filter(Column("companionId") == companionId && Column("source") == FaceSource.character.rawValue).deleteAll(db)
            guard let row = try CompanionCharacter.fetchOne(db, key: companionId), row.face == .character else { return }
            let hasSticker = try CharacterImage.filter(Column("companionId") == companionId && Column("source") == FaceSource.sticker.rawValue).fetchCount(db) > 0
            try Self.choose(hasSticker ? .sticker : .photo, companionId: companionId, by: person, now: now, db: db)
        }
    }

    /// The faces a companion can show now.
    static func available(_ db: Database, companionId: Companion.ID) throws -> Set<CompanionFaceChoice> {
        var faces: Set<CompanionFaceChoice> = [.drawn]
        if try CompanionPhoto.exists(db, key: companionId) { faces.insert(.photo) }
        let sources = try String.fetchSet(db, sql: """
            SELECT DISTINCT source FROM companionCharacterImage
            WHERE companionId = ? AND mood = 'fine' AND kind = 'still'
            """, arguments: [companionId])
        if sources.contains(FaceSource.sticker.rawValue) { faces.insert(.sticker) }
        if sources.contains(FaceSource.character.rawValue) { faces.insert(.character) }
        return faces
    }

    private static func choose(_ face: CompanionFaceChoice, companionId: Companion.ID, by person: Person.ID?, now: Date, db: Database) throws {
        if var row = try CompanionCharacter.fetchOne(db, key: companionId) {
            guard row.face != face else { return }
            row.face = face
            row.personId = person
            row.chosenAt = now
            try row.update(db)
        } else {
            try CompanionCharacter(companionId: companionId, face: face, personId: person, chosenAt: now).insert(db)
        }
    }

    /// One set of pictures (the sticker, or the character) in one transaction: no picture
    /// left over from the set before, and unchanged bytes left alone, so sync sends nothing
    /// for them.
    static func replace(_ source: FaceSource, of companionId: Companion.ID, with images: [CharacterImage], db: Database) throws {
        // Ids only: a picture a newer build added (a mood this build doesn't know) is still
        // one of the set, and goes with it.
        let keep = Set(images.map(\.id))
        let old = try CharacterImage.ID.fetchAll(db, sql: "SELECT id FROM companionCharacterImage WHERE companionId = ? AND source = ?",
                                                 arguments: [companionId, source.rawValue])
        for id in old where !keep.contains(id) {
            _ = try CharacterImage.deleteOne(db, id: id)
        }
        for image in images {
            let saved = try Data.fetchOne(db, sql: "SELECT image FROM companionCharacterImage WHERE id = ?", arguments: [image.id])
            if saved != image.image { try image.upsert(db) }
        }
    }

    /// Every companion's face beyond its photo, in a household: sizes only, never bytes.
    static func characterLooks(_ db: Database, householdId: Household.ID) throws -> [Companion.ID: CharacterLook] {
        var looks: [Companion.ID: CharacterLook] = [:]
        // Read as rows: a face, set, mood or kind a newer build added is left to that build.
        for row in try Row.fetchAll(db, sql: """
            SELECT c.companionId, c.face FROM companionCharacter c
            JOIN companion ON companion.id = c.companionId
            WHERE companion.householdId = ?
            """, arguments: [householdId]) {
            looks[row["companionId"], default: CharacterLook()].face = CompanionFaceChoice(rawValue: row["face"])
        }
        for row in try Row.fetchAll(db, sql: """
            SELECT i.id, i.companionId, i.source, i.mood, i.kind, i.frameCount, i.byteCount FROM companionCharacterImage i
            JOIN companion ON companion.id = i.companionId
            WHERE companion.householdId = ?
            """, arguments: [householdId]) {
            guard let source = FaceSource(rawValue: row["source"]), let mood = CharacterMood(rawValue: row["mood"]),
                  let kind = CharacterImageKind(rawValue: row["kind"]) else { continue }
            let companionId: Companion.ID = row["companionId"]
            let picture = CharacterLook.Picture(id: row["id"], byteCount: row["byteCount"], frameCount: row["frameCount"])
            switch (source, kind) {
            case (.sticker, .still) where mood == .fine: looks[companionId, default: CharacterLook()].sticker = picture
            case (.sticker, _): continue
            case (.character, .still): looks[companionId, default: CharacterLook()].stills[mood] = picture
            case (.character, .frames): looks[companionId, default: CharacterLook()].frames[mood] = picture
            }
        }
        return looks
    }
}
