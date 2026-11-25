import SwiftUI

@main
struct PorchlightApp: App {
    /// Only so invite links reach the app (`SceneDelegate`); everything else stays SwiftUI's.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var launch = Launch.start()

    var body: some Scene {
        WindowGroup {
            switch launch {
            case let .ready(stores):
                RootView()
                    .environment(stores.app)
                    .environment(stores.calendar)
                    .environment(stores.companions)
                    .environment(stores.food)
                    .environment(stores.home)
                    .environment(stores.weather)
                    .environment(stores.sync)
                    .environment(stores.photos)
                    .environment(stores.device)
                    .environment(stores.sharing)
                    .environment(ShareInbox.shared)
            case let .failed(message):
                StartupErrorView(message: message)
            #if DEBUG
            case .seedingSchema:
                SchemaSeedView()
            #endif
            }
        }
    }
}

/// Opening the database is the only thing that can fail at launch.
private enum Launch {
    case ready(Stores)
    case failed(String)
    #if DEBUG
    /// `-seedCloudSchema`: nothing of the household is opened (`SchemaSeed`).
    case seedingSchema
    #endif

    @MainActor
    static func start() -> Launch {
        // Only reads the build's settings: nothing of Firebase starts until a character is asked for.
        CharacterRelay.install()
        #if DEBUG
        if SchemaSeed.isRequested { return .seedingSchema }
        #endif
        do {
            #if DEBUG
            DebugLaunch.clearSandbox(ProcessInfo.processInfo.arguments)
            #endif
            // Before opening: opening the database creates the engine's metadata database.
            let metadataExisted = FileManager.default.fileExists(atPath: DatabaseIdentity.metadataURL(in: AppFiles.root).path)
            let database = try AppDatabase.openOnDisk()
            #if DEBUG
            try DebugLaunch.apply(ProcessInfo.processInfo.arguments, to: database)
            #endif
            // Sample data never syncs, so only the household's real database is checked.
            if !AppFiles.isSandboxed {
                try DatabaseIdentity.check(database, metadataExisted: metadataExisted, preferences: SyncPreferences(defaults: .standard))
            }
            // Before any store: the engine records every write from the moment it exists.
            let sync = SyncController.live(database: database)
            // Rows written by migrations once sync has been on must be recorded by the engine.
            try database.migrateData()
            // Reminder actions, widget buttons and Siri, handled with the app in the
            // background, use this same instance, and `SyncController.current`.
            AppDatabase.launched = database
            return .ready(Stores(database: database, sync: sync))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Every live store, created once at launch and shared through the environment.
@MainActor
private struct Stores {
    let app: AppModel
    let calendar: CalendarStore
    let companions: CompanionStore
    let food: FoodStore
    let home: HomeStore
    let weather: WeatherStore
    let sync: SyncController
    let photos: PhotoImages
    let device: DeviceSettings
    let sharing: HouseholdSharingModel

    init(database: AppDatabase, sync: SyncController) {
        app = AppModel(database: database)
        calendar = CalendarStore(database: database)
        companions = CompanionStore(database: database)
        food = FoodStore(database: database)
        home = HomeStore(database: database)
        weather = WeatherStore()
        self.sync = sync
        photos = PhotoImages(database: database)
        device = DeviceSettings()
        sharing = HouseholdSharingModel(service: Self.sharingService(database: database, sync: sync), database: database)
        // Also in a background launch, where no view runs: a widget's button or a change
        // from sync then still reaches the widgets.
        WidgetSummaryKeeper.start(database: database, companions: companions, home: home, device: device)
        #if DEBUG
        DebugArrivals.start(ProcessInfo.processInfo.arguments, database: database)
        #endif
    }

    /// The live sharing, or in a DEBUG launch with `-debugSharing` or `-debugJoin` the fake.
    private static func sharingService(database: AppDatabase, sync: SyncController) -> any HouseholdSharing {
        #if DEBUG
        if let fake = DebugSharing.fake(ProcessInfo.processInfo.arguments, database: database) { return fake }
        #endif
        return LiveHouseholdSharing(sync: sync, database: database)
    }
}

/// What the app shows.
enum RootScreen: Equatable {
    case householdSearch
    case onboarding
    case wall

    /// A household that is set up opens the wall, wherever it came from: a household that
    /// arrives from iCloud while the search or onboarding's first steps are showing opens
    /// right away. Before any household exists, the search comes first while it runs.
    static func pick(household: Household?, isLookingForHousehold: Bool, debugOnboarding: Bool = false) -> RootScreen {
        if household == nil && isLookingForHousehold { return .householdSearch }
        if household?.setupCompleted != true || debugOnboarding { return .onboarding }
        return .wall
    }
}

/// Picks the wall or the phone by the space there is: a regular width gets the wall
/// (an iPad, landscape), a compact one the pocket shell (an iPhone). Neither looks at
/// the kind of device, so an iPad used as someone's own still gets the wall.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppModel.self) private var model
    @Environment(HouseholdSharingModel.self) private var sharing

    var body: some View {
        Group {
            if sizeClass == .compact {
                // Nil (always, in a release build) follows the phone's own look.
                PocketRoot().preferredColorScheme(DebugLaunch.look)
            } else {
                WallRoot()
            }
        }
        .keepsThisDeviceRow()
        // Who is on the share, read once the household is here and again when it changes.
        .task(id: model.household?.id) { await sharing.refresh(model.household) }
        #if DEBUG
        .task { await DebugSnapshot.captureIfRequested() }
        #endif
    }
}

/// Onboarding or the wall, with the kiosk behavior and the wall's single light look.
private struct WallRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(WeatherStore.self) private var weather
    @Environment(SyncController.self) private var sync
    @Environment(ShareInbox.self) private var inbox
    /// Setup ended with "Invite phones now": the wall opens on Family & devices.
    @State private var invitesNext = false

    private var screen: RootScreen {
        .pick(household: model.household, isLookingForHousehold: sync.isLookingForHousehold, debugOnboarding: DebugLaunch.onboardingStep != nil)
    }

    var body: some View {
        Group {
            switch screen {
            case .householdSearch:
                HouseholdSearchView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingView(onInvite: { invitesNext = true })
                    .transition(.opacity)
            case .wall:
                WallView(startsInFamily: invitesNext)
                    .task { weather.start() }
                    .transition(.opacity)
            }
        }
        // An invite link, or the household leaving, takes the whole screen until answered.
        .overlay {
            if let invitation = inbox.invitation {
                JoinFlowView(invitation: invitation)
                    .transition(.opacity)
            } else if let removed = model.removedHousehold {
                RemovedHouseholdView(removed: removed)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: screen)
        .hostsWallLayers()
        .kioskMode()
        .preferredColorScheme(.light)
    }
}

private struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Porchlight couldn't open its data")
                .font(.display(30))
            Text(message)
                .font(.body(16))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
