import Foundation
import GRDB

/// Tells whether the database was replaced underneath the app since it last ran, for
/// example by `scripts/restore-ipad.sh`, so sync never starts on its own over a copy that
/// iCloud has moved past (docs/design/sync-icloud.md, "Backups and restore").
///
/// Each launch puts a fresh random token in the database's device-only `deviceState` and
/// in UserDefaults. A restored backup brings back its own older token (or none), while
/// UserDefaults, which a backup never holds, keeps the newest; so the two disagree. The
/// sync engine's metadata database missing while this install has synced before is the
/// same hazard: every row would look new to the engine and be sent again.
enum DatabaseIdentity {
    /// What the launch found.
    struct Evidence: Equatable {
        /// The token in the database, if any.
        var databaseToken: String?
        /// The tokens UserDefaults accepts: the newest, plus the one being replaced while a
        /// launch rotates them, so a crash in between is never taken for a restore.
        var knownTokens: [String]
        /// Whether the sync engine's metadata database was there before the app opened.
        var metadataExisted: Bool
        /// Whether this install has synced before (it knows its iCloud account).
        var hasSynced: Bool
        var hasHousehold: Bool
    }

    /// Whether the database on disk is not the one this install last ran with.
    ///
    /// A database with no household has nothing to send. Neither token means the first
    /// launch of an install, or of the version that brought tokens. A database token with
    /// none in UserDefaults means the data folder was copied into a fresh install, which has
    /// never synced: like any device that already has a household, it starts with the sync
    /// switch off, so its first upload is the owner's deliberate act (as when the wall's
    /// data moves to a new bundle id).
    static func isReplaced(_ evidence: Evidence) -> Bool {
        guard evidence.hasHousehold else { return false }
        if evidence.hasSynced && !evidence.metadataExisted { return true }
        // Nothing in UserDefaults: a fresh install, or the first launch with tokens.
        guard !evidence.knownTokens.isEmpty else { return false }
        return evidence.databaseToken.map { !evidence.knownTokens.contains($0) } ?? true
    }

    /// The engine's metadata database beside the app's own (SQLiteData names it after the
    /// database and the container).
    static func metadataURL(in folder: URL) -> URL {
        folder.appendingPathComponent(".porchlight.metadata-\(SyncController.containerIdentifier).sqlite")
    }

    /// Checks the database this launch opened, records a restored copy for the owner to
    /// decide about, and rotates the token. Call it once per launch, right after opening the
    /// database and before the sync engine exists.
    static func check(_ database: AppDatabase, metadataExisted: Bool, preferences: SyncPreferences) throws {
        let (token, hasHousehold) = try database.writer.read { db in
            (try DeviceState.value(.databaseToken, db), try Household.fetchCount(db) > 0)
        }
        let evidence = Evidence(
            databaseToken: token,
            knownTokens: preferences.databaseTokens,
            metadataExisted: metadataExisted,
            hasSynced: preferences.accountName != nil,
            hasHousehold: hasHousehold
        )
        if isReplaced(evidence) {
            preferences.restoredCopy = .undecided
        }
        try rotate(database, preferences: preferences, from: token)
    }

    /// Writes a new token: first next to the old one in UserDefaults, then into the
    /// database, then alone in UserDefaults. A crash at any point leaves the two agreeing.
    private static func rotate(_ database: AppDatabase, preferences: SyncPreferences, from old: String?) throws {
        let new = UUID().uuidString
        preferences.databaseTokens = (old.map { [$0] } ?? []) + [new]
        try database.writer.write { db in try DeviceState.set(.databaseToken, new, db) }
        preferences.databaseTokens = [new]
    }
}
