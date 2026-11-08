#if DEBUG
import Foundation
import GRDB

/// Debug-only launch arguments for screenshots and manual testing:
///   -resetData          start from an empty database (shows onboarding)
///   -sampleHousehold    start with a sample two-person household
enum DebugLaunch {
    static func apply(_ arguments: [String], to database: AppDatabase) throws {
        if arguments.contains("-resetData") || arguments.contains("-sampleHousehold") {
            try database.writer.write { db in
                try Person.deleteAll(db)
                try Household.deleteAll(db)
            }
        }
        if arguments.contains("-sampleHousehold") {
            try database.createHousehold(
                name: "The Lake House",
                people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
            )
        }
    }
}
#endif
