import SwiftUI

/// A top-level place on the wall. New features add a case here and a view in `WallView`.
enum Destination: String, CaseIterable, Identifiable {
    case today
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: "house"
        case .settings: "gearshape"
        }
    }

    /// Settings sits at the bottom of the rail, everything else at the top.
    var isPinnedToBottom: Bool { self == .settings }
}

/// The wall display: the side rail plus the selected screen.
struct WallView: View {
    @State private var selection: Destination = WallView.initialDestination

    private static var initialDestination: Destination {
        #if DEBUG
        // e.g. launch with `-startScreen settings` for screenshots
        if let name = UserDefaults.standard.string(forKey: "startScreen"), let destination = Destination(rawValue: name) {
            return destination
        }
        #endif
        return .today
    }

    var body: some View {
        HStack(spacing: 0) {
            Rail(selection: $selection)
            Group {
                switch selection {
                case .today: TodayView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .ignoresSafeArea(.container, edges: .vertical)
    }
}

private struct Rail: View {
    @Binding var selection: Destination

    var body: some View {
        VStack(spacing: 4) {
            Logo()
                .padding(.bottom, 14)
            ForEach(Destination.allCases.filter { !$0.isPinnedToBottom }) { item($0) }
            Spacer()
            ForEach(Destination.allCases.filter(\.isPinnedToBottom)) { item($0) }
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

    private func item(_ destination: Destination) -> some View {
        let isSelected = selection == destination
        return Button {
            selection = destination
        } label: {
            VStack(spacing: 4) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 21, weight: .medium))
                    .frame(height: 26)
                Text(destination.title)
                    .font(.body(11, weight: 600))
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
