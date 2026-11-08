import Foundation
import Observation

/// Live chores / lists / ambient state (STUB: owned by the Home feature).
@MainActor
@Observable
final class HomeStore {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }
}
