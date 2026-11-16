import Foundation

extension AppDatabase {
    /// The one on-disk database of this process. The app's screens and a notification
    /// action handled with the app in the background use the same instance, so a write
    /// from either is seen by the stores observing it.
    @MainActor
    static func sharedOnDisk() throws -> AppDatabase {
        if let shared = SharedDatabase.instance { return shared }
        let database = try openOnDisk()
        SharedDatabase.instance = database
        return database
    }
}

@MainActor
private enum SharedDatabase {
    static var instance: AppDatabase?
}
