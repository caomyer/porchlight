import Foundation
import GRDB

/// The home this display belongs to. One per install today.
struct Household: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var name: String
    var timeZoneIdentifier: String
    /// 1 = Sunday … 7 = Saturday, matching `Calendar.firstWeekday`.
    var firstWeekday: Int
    /// False until the whole onboarding flow has been finished.
    var setupCompleted: Bool
    var createdAt: Date
}

extension Household: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Someone who lives here. People get credit for walks, meals and chores.
struct Person: Codable, Equatable, Identifiable, Sendable {
    var id: Int64?
    var householdId: Int64
    var name: String
    var color: PersonColor
    var sortOrder: Int
    var createdAt: Date

    /// The single letter shown in the avatar.
    var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

extension Person: FetchableRecord, MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// The color a person is shown in everywhere. Stored as a stable token, not a
/// hex value, so the palette can be retuned without migrating data.
enum PersonColor: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case blue, coral, sage, ochre, plum, teal

    /// A sensible color for the n-th person added.
    static func suggested(for index: Int) -> PersonColor {
        allCases[index % allCases.count]
    }
}
