#if DEBUG
import Foundation
import GRDB

/// Debug-only launch arguments for screenshots and manual testing:
///   -resetData          start from an empty database (shows onboarding)
///   -sampleHousehold    start with a sample two-person household
///   -samplePhotos N     with -sampleHousehold, also put N painted photos in the photo frame
///   -me NAME            on a phone, belong to the person called NAME (skips "Which one is you?")
///   -debugRemoved       this device's household was removed by its owner (journey A6)
/// `-debugSharing` and `-debugJoin` are in `DebugSharing`.
enum DebugLaunch {
    /// `-onboardingStep calendars|companions|journals|display` shows that onboarding
    /// step over a sample household, for screenshots.
    static var onboardingStep: String? {
        UserDefaults.standard.string(forKey: "onboardingStep")
    }

    /// `-debugSetup you|people|companion|done` (with `-resetData`) opens that step of starting
    /// a household on a phone, filled in as The Lake House.
    static var setupStep: String? {
        UserDefaults.standard.string(forKey: "debugSetup")
    }

    /// Sample and reset launches start from an empty sandbox folder, database included.
    /// A simulator is shared by every checkout of the app, so the folder may hold a
    /// database another branch migrated to a schema this build doesn't know.
    static func clearSandbox(_ arguments: [String]) {
        guard AppFiles.isSandboxed, arguments.contains("-resetData") || arguments.contains("-sampleHousehold") else { return }
        try? FileManager.default.removeItem(at: AppFiles.root)
    }

    @MainActor
    static func apply(_ arguments: [String], to database: AppDatabase) throws {
        if arguments.contains("-resetData") || arguments.contains("-sampleHousehold") {
            // Deleting the household cascades to every feature's rows.
            try database.writer.write { db in
                try Household.deleteAll(db)
                // Which household this device showed goes with it, or it would read as removed.
                try db.execute(sql: "DELETE FROM deviceState WHERE key != ?", arguments: [DeviceState.Key.databaseToken.rawValue])
            }
            // A new household gets new people, so who this device was is gone too, and the
            // device starts with its own name and role, as a new install would.
            DeviceSettings.forgetMe()
            DeviceSettings.forgetNameAndRole()
        }
        if arguments.contains("-sampleHousehold") {
            try seedSampleHousehold(database)
        }
        if AppFiles.isSandboxed && arguments.contains("-debugRemoved") {
            // A household this device showed, gone: its owner removed this device.
            try database.writer.write { db in
                let gone = Household.ID.new()
                try DeviceState.set(.currentHouseholdId, gone.description, db)
                try DeviceState.set(.currentHouseholdName, "The Lake House", db)
                try DeviceState.set(DeviceState.ownerKey(gone), "James", db)
            }
        }
        if let name = UserDefaults.standard.string(forKey: "me") {
            let snapshot = try database.snapshot()
            if let household = snapshot.household, let person = snapshot.people.first(where: { $0.name == name }) {
                DeviceSettings.store(me: person.id, in: household.id)
            }
        }
    }

    /// The sample household, "The Lake House": James and Mia, with a week of everything.
    @MainActor
    @discardableResult
    static func seedSampleHousehold(_ database: AppDatabase) throws -> Household {
        let household = try database.createHousehold(
            name: "The Lake House",
            people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try database.markSetupCompleted(householdId: household.id)
        let snapshot = try database.snapshot()
        guard let seeded = snapshot.household else { return household }
        try CalendarSamples.seed(database, household: seeded, people: snapshot.people)
        try CompanionSamples.seed(database, household: seeded, people: snapshot.people)
        try FoodSamples.seed(database, household: seeded, people: snapshot.people)
        try HomeSamples.seed(database, household: seeded, people: snapshot.people)
        let photoCount = UserDefaults.standard.integer(forKey: "samplePhotos")
        if photoCount > 0 {
            try HomeSamples.seedPhotos(photoCount, database: database, householdId: seeded.id)
        }
        return seeded
    }
}
#endif

#if !DEBUG
enum DebugLaunch {
    static var onboardingStep: String? { nil }
    static var setupStep: String? { nil }
}
#endif
