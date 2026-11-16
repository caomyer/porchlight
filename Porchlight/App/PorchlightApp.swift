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

    init(database: AppDatabase, sync: SyncController) {
        app = AppModel(database: database)
        calendar = CalendarStore(database: database)
        companions = CompanionStore(database: database)
        food = FoodStore(database: database)
        home = HomeStore(database: database)
        weather = WeatherStore()
        self.sync = sync
    }
}

/// Picks onboarding or the wall, and applies the kiosk behavior everywhere.
struct RootView: View {
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
        #if DEBUG
        .task { await DebugSnapshot.captureIfRequested() }
        #endif
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
