#if DEBUG
import Foundation
import GRDB
import UserNotifications

/// Debug-only launch arguments for screenshots and manual testing:
///   -resetData          start from an empty database (shows onboarding)
///   -sampleHousehold    start with a sample two-person household
///   -samplePhotos N     with -sampleHousehold, also put N painted photos in the photo frame
///   -samplePeople N     with -sampleHousehold, N people instead of two (up to six)
///   -me NAME            on a phone, belong to the person called NAME (skips "Which one is you?")
///   -debugRemoved       this device's household was removed by its owner (journey A6)
///   -debugForgetDisplay YES   with either of the first two: the wall's display settings
///                       (photo frame, night hours, idle minutes) as on a new install
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
        // `-debugForgetDisplay YES`: the wall's display settings back to what a new install
        // has. They are this device's own, kept in UserDefaults, so they outlive a sample
        // launch; a UI test that changes one asks for this afterwards, so the next test
        // never starts from what the last one left (`forgetDisplaySettingsAfterwards`).
        if UserDefaults.standard.bool(forKey: "debugForgetDisplay") {
            for key in [
                AmbientSettings.showKey, AmbientSettings.nightEnabledKey, AmbientSettings.nightStartKey, AmbientSettings.nightEndKey,
                DisplaySettings.ambientMinutesKey, DisplaySettings.keepAwakeKey,
            ] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
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
            // Reminders for the old rows go too, so a run sees only what it scheduled.
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        if arguments.contains("-sampleHousehold") {
            let lakeHouse = try seedSampleHousehold(database)
            // `-sampleSecondHousehold`: Grandma Rosa's too, a household of its own, with
            // The Lake House still the one showing (journey A5).
            if arguments.contains("-sampleSecondHousehold") {
                try seedSecondHousehold(database)
                try database.chooseHousehold(lakeHouse.id)
            }
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
        // `-me NAME`: this phone is NAME's in every household that has someone called that.
        if let name = UserDefaults.standard.string(forKey: "me") {
            let people = try database.writer.read { db in
                try Person.filter(Column("name") == name && Column("archivedAt") == nil).fetchAll(db)
            }
            for person in people {
                DeviceSettings.store(me: person.id, in: person.householdId)
            }
        }
    }

    /// "Grandma Rosa's", a second household for journey A5: Rosa and James, the tomatoes
    /// watered every three days (due today), and one chore of James's.
    @MainActor
    @discardableResult
    static func seedSecondHousehold(_ database: AppDatabase) throws -> Household {
        let household = try database.createHousehold(
            name: "Grandma Rosa's",
            people: [PersonDraft(name: "Rosa", color: .plum), PersonDraft(name: "James", color: .blue)]
        )
        try database.markSetupCompleted(householdId: household.id)
        let people = try database.writer.read { try Person.active(in: household.id).fetchAll($0) }
        let calendar = household.calendar
        let now = CompanionClock.now()
        let today = DayKey(now, calendar: calendar)
        var tomatoes = CompanionDraft.new(species: .plant)
        tomatoes.name = "Tomatoes"
        tomatoes.about = "On the back porch"
        for index in tomatoes.routines.indices { tomatoes.routines[index].startDay = today.adding(days: -9, calendar: calendar) }
        let id = try database.saveCompanion(tomatoes, householdId: household.id, now: now)
        if let water = try database.writer.read({ db in try CareRoutine.filter(Column("companionId") == id).fetchOne(db) }) {
            for back in [9, 6, 3] {
                let day = today.adding(days: -back, calendar: calendar)
                try database.logCare(routineId: water.id, CareLogDraft(people: [people[0].id], occurredAt: CareLogic.date(day, minute: 10 * 60, calendar: calendar)), now: now)
            }
        }
        _ = try database.saveChore(
            ChoreDraft(title: "Call Rosa about Thanksgiving", emoji: "📞", ownerId: people[1].id, recurrence: .daily, anchorDay: today, timeHint: nil, stars: 1),
            householdId: household.id
        )
        try database.ensureDefaultLists(householdId: household.id)
        return household
    }

    /// The sample household, "The Lake House": James and Mia, with a week of everything.
    @MainActor
    @discardableResult
    static func seedSampleHousehold(_ database: AppDatabase) throws -> Household {
        var people = [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        let more = ["Ava", "Leo", "Grandma Rosa", "Sam"]
        for index in 0..<max(0, min(UserDefaults.standard.integer(forKey: "samplePeople"), 6) - 2) {
            people.append(PersonDraft(name: more[index], color: .suggested(for: index + 2)))
        }
        let household = try database.createHousehold(name: "The Lake House", people: people)
        try database.markSetupCompleted(householdId: household.id)
        let snapshot = try database.snapshot()
        guard let seeded = snapshot.household else { return household }
        try CalendarSamples.seed(database, household: seeded, people: snapshot.people)
        try CalendarSamples.seedShared(database, household: seeded, people: snapshot.people, now: CompanionClock.now())
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
