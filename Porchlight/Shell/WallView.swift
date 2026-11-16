import SwiftUI

/// A top-level place on the wall.
enum Destination: Hashable, Identifiable {
    case today
    case calendar
    case companion(Companion.ID)
    case food
    case chores
    case glow
    case lists
    case photos
    case settings

    var id: String {
        switch self {
        case let .companion(id): "companion-\(id)"
        default: String(describing: self)
        }
    }

    /// Debug `-startScreen` names. `companion-N` is the N-th companion on the rail.
    init?(debugName: String, companions: [Companion.ID]) {
        switch debugName {
        case "today": self = .today
        case "calendar": self = .calendar
        case "food": self = .food
        case "chores": self = .chores
        case "glow": self = .glow
        case "lists": self = .lists
        case "photos": self = .photos
        case "settings": self = .settings
        default:
            guard debugName.hasPrefix("companion-"), let index = Int(debugName.dropFirst("companion-".count)),
                  companions.indices.contains(index - 1) else { return nil }
            self = .companion(companions[index - 1])
        }
    }
}

/// The wall display: the side rail plus the selected screen, and Ambient mode when idle.
struct WallView: View {
    @Environment(CompanionStore.self) private var companions
    @Environment(FoodStore.self) private var food
    @Environment(HomeStore.self) private var home
    @AppStorage(DisplaySettings.ambientMinutesKey) private var ambientMinutes = DisplaySettings.defaultAmbientMinutes

    @State private var selection: Destination = .today
    @State private var lastInteraction = Date.now
    @State private var showAmbient = false

    #if DEBUG
    /// The `-startScreen` destination, e.g. `-startScreen settings` for screenshots.
    /// Companions are only known once their store has loaded, so it is read on appear.
    private var debugStartScreen: Destination? {
        UserDefaults.standard.string(forKey: "startScreen").flatMap {
            Destination(debugName: $0, companions: companions.companions.map(\.id))
        }
    }
    #endif

    private var destinations: [RailItem] {
        var items: [RailItem] = [
            RailItem(destination: .today, title: "Today", icon: .symbol("house")),
            RailItem(destination: .calendar, title: "Calendar", icon: .symbol("calendar")),
        ]
        items += companions.companions.map {
            RailItem(destination: .companion($0.id), title: $0.name, icon: .companion($0.id))
        }
        if food.isEnabled {
            items.append(RailItem(destination: .food, title: "Food", icon: .symbol("fork.knife")))
        }
        items += [
            RailItem(destination: .chores, title: "Pitch in", icon: .symbol("checkmark.square")),
            RailItem(destination: .glow, title: "Glow", icon: .symbol("sparkles")),
            RailItem(destination: .lists, title: "Lists", icon: .symbol("list.bullet")),
            RailItem(destination: .photos, title: "Photos", icon: .symbol("photo")),
        ]
        return items
    }

    var body: some View {
        HStack(spacing: 0) {
            // The rail never sets the wall's height: with many destinations it is taller
            // than the space left by the keyboard, which would keep sheets from moving up.
            // It stays full height behind the keyboard instead.
            Color.clear
                .frame(width: Theme.railWidth)
                .overlay(alignment: .top) {
                    Rail(items: destinations, selection: $selection)
                        .ignoresSafeArea(.keyboard)
                }
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opensTimelineTargets()
        }
        .background(Theme.background)
        .ignoresSafeArea(.container, edges: .vertical)
        .overlay {
            if showAmbient {
                AmbientView(extraPhotoURLs: food.recentPhotoURLs(limit: 40), onWake: { wake() }, glance: AnyView(AmbientGlance()))
                    .transition(.opacity)
                    .ignoresSafeArea()
            }
        }
        // Any touch counts as activity, observed outside SwiftUI gestures so scrolling is untouched.
        .onAnyTouch { lastInteraction = .now }
        .environment(\.openCompanion, OpenCompanionAction { selection = .companion($0) })
        .task(id: ambientMinutes) { await watchForIdle() }
        .onAppear {
            #if DEBUG
            if let start = debugStartScreen { selection = start }
            #endif
            // Starting on Photos (debug start screen) opens Ambient directly.
            if selection == .photos {
                showAmbient = true
                selection = .today
            }
        }
        .onChange(of: selection) { _, newValue in
            lastInteraction = .now
            if newValue == .photos {
                withAnimation(.easeInOut(duration: 0.6)) { showAmbient = true }
                selection = .today
            }
        }
        .onChange(of: destinations.map(\.destination)) { _, available in
            if !available.contains(selection) && selection != .settings { selection = .today }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch selection {
        case .today: TodayView()
        case .calendar:
            CalendarScreen(
                lanes: home.calendarLanes() + companions.calendarLanes() + food.calendarLanes(),
                moments: { companions.timelineItems(for: $0) + food.timelineItems(for: $0) },
                onShowFrom: { home.include(from: $0) }
            )
        case let .companion(id): CompanionScreen(companionId: id)
        case .food: FoodScreen()
        case .chores: ChoresScreen()
        case .glow: GlowScreen()
        case .lists: ListsScreen()
        case .photos: TodayView()
        case .settings: SettingsView()
        }
    }

    private func wake() {
        lastInteraction = .now
        withAnimation(.easeInOut(duration: 0.4)) { showAmbient = false }
    }

    /// Switches to Ambient mode after `ambientMinutes` without a touch (0 = never).
    private func watchForIdle() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            guard ambientMinutes > 0, !showAmbient, selection != .settings else { continue }
            if Date.now.timeIntervalSince(lastInteraction) >= Double(ambientMinutes) * 60 {
                withAnimation(.easeInOut(duration: 1.2)) { showAmbient = true }
            }
        }
    }
}

struct RailItem: Identifiable {
    enum Icon {
        case symbol(String)
        case companion(Companion.ID)
    }

    var destination: Destination
    var title: String
    var icon: Icon
    var id: String { destination.id }
}

private struct Rail: View {
    let items: [RailItem]
    @Binding var selection: Destination

    var body: some View {
        VStack(spacing: 4) {
            Logo()
                .padding(.bottom, 14)
            ForEach(items) { item($0) }
            Spacer()
            item(RailItem(destination: .settings, title: "Settings", icon: .symbol("gearshape")))
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: Theme.railWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.rail)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.line).frame(width: 1)
        }
    }

    private func item(_ item: RailItem) -> some View {
        let isSelected = selection == item.destination
        return Button {
            selection = item.destination
        } label: {
            VStack(spacing: 4) {
                Group {
                    switch item.icon {
                    case let .symbol(name):
                        Image(systemName: name).font(.system(size: 21, weight: .medium))
                    case let .companion(id):
                        CompanionRailIcon(companionId: id)
                    }
                }
                .frame(width: 30, height: 26)
                Text(item.title)
                    .font(.body(11, weight: 600))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Theme.ink : Theme.muted)
            .frame(width: 68)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    SurfaceShape(cornerRadius: 14, elevation: 0.7)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The house mark used on the rail and in onboarding.
struct Logo: View {
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "house.fill")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
            }
            .accessibilityLabel("Porchlight")
    }
}
