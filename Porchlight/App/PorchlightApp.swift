import SwiftUI

@main
struct PorchlightApp: App {
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
            case let .failed(message):
                StartupErrorView(message: message)
            }
        }
    }
}

/// Opening the database is the only thing that can fail at launch.
private enum Launch {
    case ready(Stores)
    case failed(String)

    @MainActor
    static func start() -> Launch {
        do {
            let database = try AppDatabase.openOnDisk()
            #if DEBUG
            try DebugLaunch.apply(ProcessInfo.processInfo.arguments, to: database)
            #endif
            // Before any store: the engine records every write from the moment it exists.
            let sync = SyncController.live(database: database)
            // Rows written by migrations once sync has been on must be recorded by the engine.
            try database.migrateData()
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

    var body: some View {
        Group {
            if sizeClass == .compact {
                PocketRoot()
            } else {
                WallRoot()
            }
        }
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
                OnboardingView()
                    .transition(.opacity)
            case .wall:
                WallView()
                    .task { weather.start() }
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
