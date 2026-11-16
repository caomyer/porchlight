import CryptoKit
import Foundation
import GRDB

/// The id of one row of `Entity`: a UUID, stored as lowercase text.
///
/// Ids are globally unique so rows written on different devices can sync without
/// clashing (see docs/design/sync-foundation.md). The phantom `Entity` keeps a person
/// id from being passed where a chore id is expected.
///
/// Always use this rather than a bare `UUID` in queries: GRDB binds a `UUID` as a
/// 16-byte blob, which never matches the text ids in the tables.
struct ID<Entity>: Hashable, Sendable, CustomStringConvertible, Comparable {
    let uuid: UUID

    init(_ uuid: UUID) {
        self.uuid = uuid
    }

    /// Parses an id from its text form, in either case.
    init?(_ text: String) {
        guard let uuid = UUID(uuidString: text) else { return nil }
        self.uuid = uuid
    }

    /// A new random id.
    static func new() -> ID {
        ID(UUID())
    }

    /// The same id on every device for the same parts: the SHA-256 of the parts
    /// joined with `|`, folded into a UUID (marked as version 8, custom).
    ///
    /// Rows that must exist once per combination (a chore done on a day) use it,
    /// so two devices writing the same thing offline merge into one row.
    static func derived(_ parts: String...) -> ID {
        let digest = Array(SHA256.hash(data: Data(parts.joined(separator: "|").utf8)))
        var bytes = (0..<16).map { digest[$0] ^ digest[$0 + 16] }
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return ID(UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )))
    }

    /// The stored form, e.g. `3f2b8c1e-0d4a-4c7e-9a51-2b8e6f0c1d3a`.
    var description: String { uuid.uuidString.lowercased() }

    /// A number taken from the id, the same on every launch, for picking things
    /// "at random" but stably (like a log's caption).
    var stableSeed: UInt64 {
        withUnsafeBytes(of: uuid.uuid) { raw in
            raw.load(fromByteOffset: 0, as: UInt64.self) ^ raw.load(fromByteOffset: 8, as: UInt64.self)
        }
    }

    /// Text order, the same order SQLite sorts the column in.
    static func < (lhs: ID, rhs: ID) -> Bool {
        lhs.description < rhs.description
    }
}

extension ID: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let id = ID(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a UUID: \(text)")
        }
        self = id
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension ID: DatabaseValueConvertible {
    var databaseValue: DatabaseValue { description.databaseValue }

    /// Text only: an integer id from before the sync migration is not an id.
    static func fromDatabaseValue(_ dbValue: DatabaseValue) -> ID? {
        guard case let .string(text) = dbValue.storage else { return nil }
        return ID(text)
    }
}

extension Database {
    /// Registers `uuid()`, which the id columns use as their default. SQLiteData
    /// registers the same function once sync is on.
    func addUUIDFunction() {
        add(function: DatabaseFunction("uuid", argumentCount: 0, pure: false) { _ in
            UUID().uuidString.lowercased()
        })
    }
}
