import Foundation
import Observation
import PencilKit
import Testing
@testable import Porchlight

/// A plain property and a `StoredFirst` one, side by side.
@MainActor
@Observable
private final class Probe: StoredFirstObservable {
    var plain = 0
    @ObservationIgnored @StoredFirst var stored = 0
}

/// Properties set from outside a SwiftUI action (the database, iCloud, the network, a timer,
/// a system callback) are stored before observers hear of the change, so a screen SwiftUI
/// redraws as the change is announced already reads it (`StoredFirst`). Where a test can set
/// the property the way the app does, it checks what an observer reads; elsewhere it checks
/// the property is a `StoredFirst`, which a plain property is not.
@Suite("Stored before observers hear")
@MainActor
struct StoredFirstTests {
    /// What a reader saw when it heard of the next change.
    final class Seen<Value: Sendable>: @unchecked Sendable {
        var value: Value?
    }

    /// Reads again the moment a change is announced, as SwiftUI may redraw a screen then.
    private func readOnChange<Value: Sendable>(_ read: @escaping @MainActor @Sendable () -> Value) -> Seen<Value> {
        let seen = Seen<Value>()
        withObservationTracking {
            _ = read()
        } onChange: {
            MainActor.assumeIsolated { seen.value = read() }
        }
        return seen
    }

    /// The properties of `owner`, by name, that are not a `StoredFirst`.
    private func notStoredFirst(_ owner: Any, _ names: [String]) -> [String] {
        let wrapped = Set(Mirror(reflecting: owner).children.compactMap { child -> String? in
            guard let label = child.label, String(describing: type(of: child.value)).hasPrefix("StoredFirst<") else { return nil }
            return String(label.dropFirst())
        })
        return names.filter { !wrapped.contains($0) }
    }

    @Test("A plain @Observable property is read old as its change is announced; a StoredFirst one new")
    func theWrapper() {
        let probe = Probe()
        let plain = readOnChange { probe.plain }
        let stored = readOnChange { probe.stored }
        probe.plain = 1
        probe.stored = 1
        #expect(plain.value == 0, "This is the stale read StoredFirst exists for")
        #expect(stored.value == 1)
        #expect(probe.stored == 1)
    }

    @Test("A toast its timer takes away reads as gone")
    func toast() {
        let toasts = ToastCenter()
        toasts.show(UndoToast(emoji: "🔧", title: "Fix the leaky faucet done"))
        let seen = readOnChange { toasts.current == nil }
        toasts.dismiss()
        #expect(seen.value == true)
    }

    @Test("The household's share, read again from iCloud, reads new")
    func sharing() async throws {
        let db = try AppDatabase.inMemory(installId: "james-phone")
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "Sam", color: .blue)])
        let fake = FakeHouseholdSharing(members: HouseholdMembers(participants: [
            HouseholdParticipant(id: "owner", name: "Sam", role: .owner, status: .joined, isCurrentUser: true),
            HouseholdParticipant(id: "riley", name: "Riley", role: .member, status: .joined, isCurrentUser: false),
        ]))
        let sharing = HouseholdSharingModel(service: fake, database: db)
        let seen = readOnChange { sharing.members.participants.count }
        await sharing.refresh(household)
        #expect(seen.value == 2)
        #expect(notStoredFirst(sharing, ["members", "linkJoiners", "userName"]).isEmpty)
    }

    @Test("Sync details read what sync just did")
    func trace() {
        let trace = SyncTrace(log: SyncLog(file: nil))
        let seen = readOnChange { trace.pushes }
        trace.pushes = 3
        #expect(seen.value == 3)
        #expect(notStoredFirst(trace, [
            "role", "isActive", "activitySource", "isOnline", "engineRunning", "account", "lastCheck", "lastTrigger",
            "received", "lastProbe", "restarts", "tokenRequests", "pushes", "lastPush", "pushToken", "registeredForPushes",
            "backgroundRefresh", "lowPowerMode", "checks", "failuresInRow", "lastError", "nextCheckAt",
        ]).isEmpty)
    }

    @Test("Reminder choices a notification action changed read new")
    func reminders() throws {
        let defaults = try #require(UserDefaults(suiteName: "stored-first-\(UUID().uuidString)"))
        let settings = ReminderSettings(defaults: defaults)
        var changed = settings.choices
        changed.chores.toggle()
        ReminderSettings.save(changed, to: defaults)
        let seen = readOnChange { settings.choices.chores }
        settings.reload()
        #expect(seen.value == changed.chores)
    }

    @Test("A page drawn on reads as changed")
    func drawing() {
        let editor = PageEditor(day: DayKey(rawValue: "2026-11-17"), drawing: PKDrawing())
        let seen = readOnChange { editor.hasChanges }
        let stroke = PKStroke(ink: PKInk(.pen), path: PKStrokePath(controlPoints: [
            PKStrokePoint(location: .zero, timeOffset: 0, size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: 0),
            PKStrokePoint(location: CGPoint(x: 10, y: 10), timeOffset: 0.1, size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: 0),
        ], creationDate: .now))
        editor.userChanged(to: PKDrawing(strokes: [stroke]))
        #expect(seen.value == true)
        #expect(notStoredFirst(editor, ["drawing", "hasChanges"]).isEmpty)
    }

    @Test("Today, the forecast, restaurant suggestions, joining, arrivals, the inbox, meal photos, sync and the schema seed are stored first")
    func everyOther() throws {
        let db = try AppDatabase.inMemory(installId: "james-phone")
        #expect(notStoredFirst(HomeStore(database: db), ["today"]).isEmpty)
        #expect(notStoredFirst(WeatherStore(), ["now", "days", "unitSymbol"]).isEmpty)
        #expect(notStoredFirst(RestaurantSearch(near: nil), ["suggestions", "isSearching", "isOffline"]).isEmpty)
        #expect(notStoredFirst(WallArrivals(), ["fresh", "toast"]).isEmpty)
        #expect(notStoredFirst(ShareInbox(), ["invitation"]).isEmpty)
        let food = FoodStore(database: db)
        let form = CaptureForm(request: CaptureRequest(day: DayKey(rawValue: "2026-11-17")), store: food, now: CompanionClock.now())
        #expect(notStoredFirst(form, ["photos", "savingPhotos"]).isEmpty)
        let sync = SyncController(.unavailable(.sampleData), preferences: SyncPreferences(defaults: try #require(UserDefaults(suiteName: "stored-first-\(UUID().uuidString)"))), hasHousehold: true, removeFiles: {})
        #expect(notStoredFirst(sync, [
            "isEnabled", "accountDecision", "restoredCopy", "lastSynced", "userName", "unavailable", "startFailure",
            "account", "isOnline", "isFull", "isSynchronizing", "isLookingForHousehold", "needsAttention",
            "unsentCount", "checksFailing", "checkedRecently",
        ]).isEmpty)
        #expect(notStoredFirst(SchemaSeeder(deleteZone: { _ in }), ["phase"]).isEmpty)
    }

    @Test("A store's error from its database observation is stored first")
    func storeErrors() throws {
        let db = try AppDatabase.inMemory(installId: "james-phone")
        #expect(notStoredFirst(AppModel(database: db), ["lastError"]).isEmpty)
        #expect(notStoredFirst(HomeStore(database: db), ["lastError"]).isEmpty)
        #expect(notStoredFirst(FoodStore(database: db), ["lastError"]).isEmpty)
        #expect(notStoredFirst(CompanionStore(database: db), ["lastError"]).isEmpty)
        #expect(notStoredFirst(CalendarStore(database: db), ["lastError"]).isEmpty)
    }

    @Test("Joining reads where it got to")
    func joining() throws {
        let db = try AppDatabase.inMemory(installId: "james-phone")
        let flow = JoinFlow(
            invitation: HouseholdInvitation(householdId: nil, householdName: "Home", ownerName: "Sam"), database: db, sharing: FakeHouseholdSharing(),
            device: DeviceSettings(defaults: try #require(UserDefaults(suiteName: "stored-first-\(UUID().uuidString)")))
        )
        #expect(notStoredFirst(flow, ["step", "failure"]).isEmpty)
    }
}
