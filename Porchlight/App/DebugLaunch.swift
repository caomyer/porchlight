#if DEBUG
import Foundation
import GRDB

/// Debug-only launch arguments for screenshots and manual testing:
///   -resetData          start from an empty database (shows onboarding)
///   -sampleHousehold    start with a sample two-person household
enum DebugLaunch {
    static func apply(_ arguments: [String], to database: AppDatabase) throws {
        if arguments.contains("-resetData") || arguments.contains("-sampleHousehold") {
            // Deleting the household cascades to every feature's rows.
            _ = try database.writer.write { db in
                try Household.deleteAll(db)
            }
        }
        if arguments.contains("-sampleHousehold") {
            let household = try database.createHousehold(
                name: "The Lake House",
                people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
            )
            try database.markSetupCompleted(householdId: household.id!)
            let snapshot = try database.snapshot()
            guard let seeded = snapshot.household else { return }
            try CalendarSamples.seed(database, household: seeded, people: snapshot.people)
            try CompanionSamples.seed(database, household: seeded, people: snapshot.people)
            try FoodSamples.seed(database, household: seeded, people: snapshot.people)
            try HomeSamples.seed(database, household: seeded, people: snapshot.people)
        }
    }
}
#endif
