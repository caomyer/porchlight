import Foundation
import Testing
@testable import Porchlight

/// `Config/cloudkit-schema.ckdb` is what `scripts/cloud-schema.sh import` puts in CloudKit's
/// Development environment, and what James then deploys to Production, where a field can
/// never be removed. So the file must be exactly what the app writes: this derives that
/// from the app's own tables (`SyncMirror.all`) by the rules SQLiteData follows (see
/// docs/design/sync-icloud.md, "What CloudKit has to know") and compares, record type by
/// record type and field by field. No device or iCloud is involved.
@Suite("CloudKit schema file")
struct SchemaFileTests {
    /// Record types CloudKit or SQLiteData make that no table of ours describes: the
    /// built-in `Users` type and the share record. They are read and left out on purpose.
    static let notOurs: Set<String> = ["Users", "cloudkit.share"]

    /// Every record's own fields, the same for each type: `___recordID` and the like.
    static func isSystemField(_ name: String) -> Bool { name.hasPrefix("___") }

    /// What the app writes: for each synced table, its fields and their CloudKit types.
    static func expected() -> [String: [String: String]] {
        var types: [String: [String: String]] = [:]
        for mirror in SyncMirror.all {
            var fields = ["sqlitedata_icloud_userModificationTime": "ENCRYPTED INT64"]
            for column in SchemaSeed.columns(of: mirror) {
                fields["sqlitedata_icloud_userModificationTime_\(column.name)"] = "ENCRYPTED INT64"
                switch column.kind {
                case .uuid?, .string?: fields[column.name] = "ENCRYPTED STRING"
                case .date?: fields[column.name] = "ENCRYPTED TIMESTAMP"
                case .int?, .bool?: fields[column.name] = "ENCRYPTED INT64"
                case .double?: fields[column.name] = "ENCRYPTED DOUBLE"
                case .data?:
                    // Blobs travel as plain assets, with an encrypted hash beside them.
                    fields[column.name] = "ASSET"
                    fields["\(column.name)_hash"] = "ENCRYPTED BYTES"
                case nil: fields[column.name] = "unknown type"
                }
            }
            types[mirror.tableName] = fields
        }
        return types
    }

    /// The checked-in file, as record type -> field -> type. Grants and system fields are
    /// read and skipped; anything else the parser doesn't understand fails the test.
    static func parse(_ text: String) throws -> [String: [String: String]] {
        var types: [String: [String: String]] = [:]
        var current: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "DEFINE SCHEMA" { continue }
            if line.hasPrefix("RECORD TYPE ") {
                let name = line.dropFirst("RECORD TYPE ".count).replacingOccurrences(of: " (", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\" ("))
                current = name
                types[name] = [:]
                continue
            }
            if line == ");" { current = nil; continue }
            if line.hasPrefix("GRANT ") { continue }
            guard let type = current else { throw ParseError(line: line) }
            let body = line.hasSuffix(",") ? String(line.dropLast()) : line
            let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw ParseError(line: line) }
            let name = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if isSystemField(name) { continue }
            types[type, default: [:]][name] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return types
    }

    struct ParseError: Error, CustomStringConvertible {
        let line: String
        var description: String { "Can't read this line of the schema file: \(line)" }
    }

    static var file: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/cloudkit-schema.ckdb")
    }

    /// Everything that differs, one line each, naming the record type and field.
    static func problems(expected: [String: [String: String]], file: [String: [String: String]]) -> [String] {
        var problems: [String] = []
        let fileTypes = Set(file.keys).subtracting(notOurs)
        for type in Set(expected.keys).subtracting(fileTypes).sorted() { problems.append("missing record type \(type)") }
        for type in fileTypes.subtracting(expected.keys).sorted() { problems.append("extra record type \(type), which no table writes") }
        for (type, fields) in expected.sorted(by: { $0.key < $1.key }) {
            guard let have = file[type] else { continue }
            for name in Set(fields.keys).subtracting(have.keys).sorted() { problems.append("\(type).\(name) is missing (the app writes \(fields[name]!))") }
            for name in Set(have.keys).subtracting(fields.keys).sorted() { problems.append("\(type).\(name) is extra: the app never writes it") }
            for name in fields.keys.sorted() where have[name] != nil && have[name] != fields[name] {
                problems.append("\(type).\(name) is \(have[name]!), the app writes \(fields[name]!)")
            }
        }
        return problems
    }

    @Test("The checked-in schema is exactly what the app writes, type by type and field by field")
    func fileMatchesTheApp() throws {
        let file = try Self.parse(String(contentsOf: Self.file, encoding: .utf8))
        let problems = Self.problems(expected: Self.expected(), file: file)
        #expect(problems.isEmpty, "Config/cloudkit-schema.ckdb differs from what the app writes:\n\(problems.joined(separator: "\n"))")
        for type in Self.notOurs {
            #expect(file[type] != nil, "the file keeps CloudKit's own \(type), as an export has it")
        }
    }

    @Test("A missing, extra or mistyped field or record type is named")
    func catchesMistakes() throws {
        let good = try Self.parse(String(contentsOf: Self.file, encoding: .utf8))
        let expected = Self.expected()
        var file = good
        file["careLog"]?["slot"] = nil
        #expect(Self.problems(expected: expected, file: file) == ["careLog.slot is missing (the app writes ENCRYPTED INT64)"])
        file = good
        file["careLog"]?["slot"] = "ENCRYPTED STRING"
        #expect(Self.problems(expected: expected, file: file) == ["careLog.slot is ENCRYPTED STRING, the app writes ENCRYPTED INT64"])
        file = good
        file["careLog"]?["slots"] = "ENCRYPTED INT64"
        #expect(Self.problems(expected: expected, file: file) == ["careLog.slots is extra: the app never writes it"])
        file = good
        file["careLog"] = nil
        file["careLogs"] = [:]
        #expect(Self.problems(expected: expected, file: file) == ["missing record type careLog", "extra record type careLogs, which no table writes"])
    }

    @Test("The parser reads an export's own lines and refuses anything else")
    func parser() throws {
        let text = """
            DEFINE SCHEMA

                RECORD TYPE "cloudkit.share" (
                    "___createTime" TIMESTAMP,
                    "cloudkit.title" STRING,
                    GRANT READ TO "_world"
                );

                RECORD TYPE careLog (
                    "___recordID" REFERENCE,
                    slot          ENCRYPTED INT64,
                    image         ASSET,
                    GRANT WRITE TO "_creator"
                );
            """
        let parsed = try Self.parse(text)
        #expect(parsed["careLog"] == ["slot": "ENCRYPTED INT64", "image": "ASSET"])
        #expect(parsed["cloudkit.share"] == ["cloudkit.title": "STRING"])
        #expect(throws: ParseError.self) { try Self.parse("stray ENCRYPTED INT64,") }
    }
}
