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

    init(database: AppDatabase) {
        app = AppModel(database: database)
        calendar = CalendarStore(database: database)
        companions = CompanionStore(database: database)
        food = FoodStore(database: database)
        home = HomeStore(database: database)
    }
}

/// Picks onboarding or the wall, and applies the kiosk behavior everywhere.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.household?.setupCompleted != true {
                OnboardingView()
            } else {
                WallView()
            }
        }
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
