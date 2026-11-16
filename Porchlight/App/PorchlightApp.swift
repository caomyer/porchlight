import SwiftUI

@main
struct PorchlightApp: App {
    @State private var launch = Launch.start()
    /// Handles reminder actions, also with the app in the background.
    @UIApplicationDelegateAdaptor(ReminderAppDelegate.self) private var reminders

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
            #if DEBUG
            DebugLaunch.clearSandbox(ProcessInfo.processInfo.arguments)
            #endif
            let database = try AppDatabase.sharedOnDisk()
            #if DEBUG
            try DebugLaunch.apply(ProcessInfo.processInfo.arguments, to: database)
            #endif
            return .ready(Stores(database: database))
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
    let device: DeviceSettings

    init(database: AppDatabase) {
        app = AppModel(database: database)
        calendar = CalendarStore(database: database)
        companions = CompanionStore(database: database)
        food = FoodStore(database: database)
        home = HomeStore(database: database)
        weather = WeatherStore()
        device = DeviceSettings()
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

    var body: some View {
        Group {
            if model.household?.setupCompleted != true || DebugLaunch.onboardingStep != nil {
                OnboardingView()
            } else {
                WallView()
                    .task { weather.start() }
            }
        }
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
