import Foundation
import GRDB

/// The newest row another device wrote: what the sync line in Settings names ("last change
/// 2 min ago from Mia's phone", journey D2).
struct LastChange: Equatable, Sendable {
    var deviceId: Device.ID
    var at: Date

    /// Every stamped table with the time its rows were written.
    private static let times: [(table: String, column: String)] = [
        ("careLog", "createdAt"), ("journalEntry", "createdAt"), ("choreCompletion", "completedAt"),
        ("rewardRedemption", "redeemedAt"), ("listItem", "createdAt"),
    ]

    /// The newest row stamped by any device but `excluded` (this one).
    static func fetch(_ db: Database, excluding excluded: Device.ID?) throws -> LastChange? {
        let union = times.map { table, column in
            #"SELECT "deviceId", "\#(column)" AS "at" FROM "\#(table)" WHERE "deviceId" IS NOT NULL"#
        }.joined(separator: " UNION ALL ")
        let row = try Row.fetchOne(db, sql: """
            SELECT deviceId, at FROM (\(union)) WHERE deviceId IS NOT ? ORDER BY at DESC LIMIT 1
            """, arguments: [excluded])
        guard let row, let id = (row["deviceId"] as String?).flatMap(Device.ID.init), let at = row["at"] as Date? else { return nil }
        return LastChange(deviceId: id, at: at)
    }
}

extension AppDatabase {
    /// Emits the newest change from another device whenever a stamped row changes.
    func lastChangeUpdates(excluding excluded: Device.ID?) -> AsyncValueObservation<LastChange?> {
        ValueObservation
            .tracking { try LastChange.fetch($0, excluding: excluded) }
            .removeDuplicates()
            .values(in: writer)
    }
}
