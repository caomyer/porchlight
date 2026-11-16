#if DEBUG
import Foundation
import GRDB

/// Debug-only launch arguments for screenshots and manual testing:
///   -resetData          start from an empty database (shows onboarding)
///   -sampleHousehold    start with a sample two-person household
///   -samplePhotos N     with -sampleHousehold, also put N painted photos in the photo frame
///   -me NAME            on a phone, belong to the person called NAME (skips "Which one is you?")
enum DebugLaunch {
    /// `-onboardingStep calendars|companions|journals|display` shows that onboarding
    /// step over a sample household, for screenshots.
    static var onboardingStep: String? {
        UserDefaults.standard.string(forKey: "onboardingStep")
    }

    @MainActor
    static func apply(_ arguments: [String], to database: AppDatabase) throws {
        if arguments.contains("-resetData") || arguments.contains("-sampleHousehold") {
            // Deleting the household cascades to every feature's rows.
            _ = try database.writer.write { db in
                try Household.deleteAll(db)
            }
            // A new household gets new people, so who this device was is gone too.
            DeviceSettings.forgetMe()
        }
        if arguments.contains("-sampleHousehold") {
            let household = try database.createHousehold(
                name: "The Lake House",
                people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
            )
            try database.markSetupCompleted(householdId: household.id)
            let snapshot = try database.snapshot()
            guard let seeded = snapshot.household else { return }
            try CalendarSamples.seed(database, household: seeded, people: snapshot.people)
            try CompanionSamples.seed(database, household: seeded, people: snapshot.people)
            try FoodSamples.seed(database, household: seeded, people: snapshot.people)
            try HomeSamples.seed(database, household: seeded, people: snapshot.people)
            let photoCount = UserDefaults.standard.integer(forKey: "samplePhotos")
            if photoCount > 0 {
                try HomeSamples.seedPhotos(photoCount, database: database, householdId: seeded.id)
            }
        }
        if let name = UserDefaults.standard.string(forKey: "me") {
            let snapshot = try database.snapshot()
            if let household = snapshot.household, let person = snapshot.people.first(where: { $0.name == name }) {
                DeviceSettings.store(me: person.id, in: household.id)
            }
        }
    }
}
#endif

#if !DEBUG
enum DebugLaunch {
    static var onboardingStep: String? { nil }
}
#endif
