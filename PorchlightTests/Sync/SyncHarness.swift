import CloudKit
import Foundation
import GRDB
import Testing
import UIKit
@testable import Porchlight

extension SyncController.Timing {
    /// The app's timing, without "Up to date" waiting on a check: tests of other things
    /// never run the checks (`SyncCheckStatusTests` covers that).
    static var tests: SyncController.Timing {
        var timing = SyncController.Timing()
        timing.checkFreshness = nil
        return timing
    }
}

/// A database on disk with its own sync metadata, the device's own preferences, and a
/// device whose iCloud account a test controls. Sync runs against SQLiteData's stand-in
/// for iCloud, which it uses whenever it runs under tests.
@MainActor
final class SyncHarness {
    let folder: URL
    let database: AppDatabase
    let device = FakeSyncDevice()
    let defaults: UserDefaults
    private let suiteName = "sync-tests-\(UUID().uuidString)"
    private(set) var removedFiles = 0

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        database = try AppDatabase.openOnDisk(folder: folder)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        // The engine and the database keep each other alive (it observes every transaction),
        // so close the connections here, or each test would leave its files open. The folder
        // stays: the engine's own metadata database is still open.
        try? database.writer.close()
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    var preferences: SyncPreferences { SyncPreferences(defaults: defaults) }

    /// A controller as the app makes one at launch, settled.
    func controller(timing: SyncController.Timing = .tests) async -> SyncController {
        let hasHousehold = try? database.snapshot().household != nil
        let controller = SyncController(
            .sync(database.writer, device: device),
            preferences: preferences,
            hasHousehold: hasHousehold ?? false,
            timing: timing,
            followsApplication: false,
            removeFiles: { [weak self] in self?.removedFiles += 1 }
        )
        await controller.settle()
        return controller
    }

    /// Fills every synced table through the app's own write functions.
    ///
    /// A few rows each: SQLiteData's stand-in for iCloud refuses more than 200 records per
    /// request, where the real sync engine splits them into batches itself.
    func fill() throws {
        let household = try database.createHousehold(
            name: "The Lake House",
            people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try database.markSetupCompleted(householdId: household.id)
        let people = try database.snapshot().people.map(\.id)
        try database.saveThisDevice(
            ThisDevice(name: "Hallway iPad", role: .sharedScreen, model: "iPad", personId: nil, userName: "owner"), in: household.id
        )
        let today = DayKey(CompanionClock.now(), calendar: household.calendar)

        var yoyo = CompanionDraft.new(species: .dog)
        yoyo.name = "Yo-Yo"
        yoyo.photo = try CompanionPhotos.prepared(try #require(Self.image().jpegData(compressionQuality: 0.8)))
        let companionId = try database.saveCompanion(yoyo, householdId: household.id)
        try database.saveSticker(try #require(Self.image().pngData()), companionId: companionId, by: people[0])
        let walk = try #require(try database.writer.read { db in
            try CareRoutine.filter(Column("companionId") == companionId).fetchOne(db)
        })
        _ = try database.logCare(routineId: walk.id, CareLogDraft(people: people, occurredAt: CompanionClock.now(), vibe: .smooth))

        let chore = try database.saveChore(
            ChoreDraft(title: "Dishes", emoji: "🍽️", ownerId: people[0], recurrence: .daily, anchorDay: today, timeHint: nil, stars: 1),
            householdId: household.id
        )
        _ = try database.toggleChore(id: chore.id, day: today, personId: people[1])
        let reward = try database.saveReward(
            RewardDraft(title: "Ice cream trip", emoji: "🍦", targetStars: 20, ownerId: people[0]), householdId: household.id, today: today
        )
        try database.cashInReward(id: reward.id, stars: 20, day: today, after: nil)
        let list = try database.createList(title: "Groceries", kind: .grocery, householdId: household.id)
        _ = try database.addListItem(title: "Basil", to: list.id, addedBy: people[0])
        let tacos = try database.saveRecipe(
            RecipeDraft(
                name: "Tacos", serves: 4, ingredients: ["8 tortillas", "2 limes"], steps: ["Warm the tortillas."],
                photos: [.added(NewRecipePhoto(image: try #require(Self.image().jpegData(compressionQuality: 0.8)), thumbnail: Data("small".utf8)))]
            ),
            householdId: household.id, addedBy: people[1]
        )
        try database.setMeal(day: today, title: "Tacos", emoji: "🌮", householdId: household.id, dishId: tacos.dish.id)

        // This device's calendars, passed on: one calendar and one of its events.
        let calendars = [ExternalCalendar(id: "home", title: "Home", account: "iCloud", colorHex: 0x336699, accountKind: "iCloud")]
        try database.syncCalendarSources(householdId: household.id, calendars: calendars)
        let start = today.startDate(in: household.calendar).addingTimeInterval(19 * 3600)
        let plan = CalendarPassOn.plan(
            sources: try database.calendarSnapshot().sources, calendars: calendars,
            events: [ExternalEvent(id: "dinner@1", calendarId: "home", title: "Dinner with the Lees", start: start, end: start.addingTimeInterval(7200), isAllDay: false)],
            deviceId: database.thisDeviceId(in: household.id), deviceCalendar: household.calendar, householdCalendar: household.calendar
        )
        try database.passOnCalendars(
            plan, householdId: household.id, trigger: .open,
            window: CalendarPassOn.window(today: today, calendar: household.calendar), now: CompanionClock.now()
        )
        // The household's home calendar, and who that dinner is for.
        try database.writer.write { db in
            try HomeCalendar(id: HomeCalendar.id(householdId: household.id), householdId: household.id, title: "Home",
                             accountKind: "iCloud", chosenById: database.thisDeviceId(in: household.id), chosenAt: .now).insert(db)
        }
        try database.setEventFor(
            matchKey: "dinner-key", title: "Dinner with the Lees", start: start, itemId: "dinner",
            people: [people[1]], householdId: household.id
        )

        let journal = try database.ensureFoodJournal(householdId: household.id)
        var dinner = MealDraft(
            day: today, slot: MealSlot.defaultNames[2], sources: MealSources([.dineOut, .company]), title: "Sushi", emoji: "🍣",
            eaterIds: people, eatenAt: CompanionClock.now(), place: PlaceDraft(name: "Sakura Sushi Bar")
        )
        dinner.dishes = [DishLineDraft(name: "Salmon nigiri", rating: .again)]
        let meal = try database.addMeal(dinner, journalId: journal.id, photos: [try MealPhotoImaging.prepare(Self.image())])
        let line = try #require(try database.foodSnapshot().lines[meal.id]?.first)
        try database.setPersonFace(lineId: line.id, personId: people[1], .favorite)
        let page = SampleHandwriting.page(lines: [("Sushi night", PageInk.defaultInk(for: .blue))])
        try database.savePage(journalId: journal.id, day: today, drawing: page.dataRepresentation())
    }

    /// A small painted photo.
    private static func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
    }

    /// Row counts of every synced table.
    func counts() throws -> [String: Int] {
        try database.writer.read { db in
            var counts: [String: Int] = [:]
            for table in SyncSchema.synced {
                counts[table.name] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(table.name)\"")
            }
            return counts
        }
    }

    /// Every synced row the engine hasn't had confirmed by iCloud, as "table id", plus
    /// every change still queued for it.
    func unsynced() throws -> [String] {
        try database.writer.read { db in
            var missing: [String] = []
            for table in SyncSchema.synced {
                let key = try db.primaryKey(table.name).columns[0]
                let sent = try Set(String.fetchAll(db, sql: """
                    SELECT recordPrimaryKey FROM sqlitedata_icloud_metadata
                    WHERE recordType = ? AND lastKnownServerRecord IS NOT NULL
                    """, arguments: [table.name]))
                for id in try String.fetchAll(db, sql: "SELECT \"\(key)\" FROM \"\(table.name)\"") where !sent.contains(id) {
                    missing.append("\(table.name) \(id)")
                }
            }
            let queued = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlitedata_icloud_pendingRecordZoneChanges") ?? 0
            if queued > 0 { missing.append("\(queued) queued changes") }
            return missing
        }
    }

    /// Rows the engine has been told about at all.
    func knownRows() throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlitedata_icloud_metadata") ?? 0
        }
    }
}

/// The device, with an iCloud account the test signs in and out.
actor FakeSyncDevice: SyncDevice {
    private var status = CKAccountStatus.available
    private var name = "owner"
    /// How long checking the account takes, as on a slow network.
    private var delay: Duration?
    private nonisolated let stream: AsyncStream<SyncDeviceChange>
    private nonisolated let continuation: AsyncStream<SyncDeviceChange>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    /// True while checking the account fails outright, as offline.
    private var checkFails = false

    func accountStatus() async throws -> CKAccountStatus {
        if let delay { try? await Task.sleep(for: delay) }
        if checkFails { throw URLError(.notConnectedToInternet) }
        return status
    }

    /// The account's next answer, as iCloud gives it, announced as an account change.
    func answer(_ status: CKAccountStatus) {
        self.status = status
        checkFails = false
        continuation.yield(.account)
    }

    /// Checking the account fails until the next answer.
    func failChecks() {
        checkFails = true
        continuation.yield(.account)
    }

    func answer(after delay: Duration) {
        self.delay = delay
    }

    /// What the next probes of iCloud say, in order; none left means it can't probe.
    private var probes: [SyncProbe] = []

    func willProbe(_ probes: [SyncProbe]) {
        self.probes = probes
    }

    func probeChanges() -> SyncProbe? {
        probes.isEmpty ? nil : probes.removeFirst()
    }
    func accountName() -> String { name }
    nonisolated func changes() -> AsyncStream<SyncDeviceChange> { stream }

    func signIn(as name: String) {
        status = .available
        self.name = name
        continuation.yield(.account)
    }

    func signOut() {
        status = .noAccount
        continuation.yield(.account)
    }
}

extension CKSyncEngine.Event.AccountChange.ChangeType {
    static let ownerSignedOut = Self.signOut(previousUser: CKRecord.ID(recordName: "owner"))
    static let ownerSignedIn = Self.signIn(currentUser: CKRecord.ID(recordName: "owner"))
    static let switched = Self.switchAccounts(
        previousUser: CKRecord.ID(recordName: "owner"),
        currentUser: CKRecord.ID(recordName: "someone else")
    )
}
