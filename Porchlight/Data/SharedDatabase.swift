import Foundation

extension AppDatabase {
    /// The database this launch opened, through the one open path in `PorchlightApp`
    /// (the restore check, then the sync engine attached). A notification action handled
    /// with the app launched in the background uses this same instance, so its writes are
    /// recorded by the engine and seen by every store; nothing opens a second connection.
    @MainActor static var launched: AppDatabase?
}
