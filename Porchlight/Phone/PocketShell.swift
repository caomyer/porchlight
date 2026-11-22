import SwiftUI
import UIKit

/// The phone's five tabs. "You" is the avatar at the top right of every tab.
enum PocketTab: String, CaseIterable, Hashable {
    case today, calendar, food, lists, glow

    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .food: "Food"
        case .lists: "Lists"
        case .glow: "Glow"
        }
    }

    /// The wall's rail icons, so a place looks the same on both.
    var symbol: String {
        switch self {
        case .today: "house"
        case .calendar: "calendar"
        case .food: "fork.knife"
        case .lists: "list.bullet"
        case .glow: "sparkles"
        }
    }
}

struct PocketShell: View {
    @State private var tab: PocketTab = .today
    /// The You sheet, and the page it opens on when a tab sent someone there.
    @State private var you: YouRequest?
    @State private var toasts = ToastCenter()

    private struct YouRequest: Identifiable {
        let id = UUID()
        var page: YouPage?
    }
    @State private var reminders = ReminderSettings()

    init() {
        // The wall has no tab bar, so styling every tab bar styles only this one.
        let font = UIFont.variable(.body, size: 10.5, weight: 700)
        UITabBarItem.appearance().setTitleTextAttributes([.font: font], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: font], for: .selected)
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(PocketTab.allCases, id: \.self) { tab in
                screen(tab)
                    .toolbarBackground(Theme.surface, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .tint(Theme.accent)
        .keepsRemindersScheduled()
        .environment(\.openYou, OpenYouAction { page in
            you = YouRequest(page: page)
        })
        .environment(\.openCalendar, OpenCalendarAction { tab = .calendar })
        .hostsToasts(toasts)
        .sheet(item: $you) { request in
            YouSheet(start: request.page)
        }
        // A widget's tap: porchlight://lists opens Lists, porchlight://calendar the calendar.
        .onOpenURL { url in
            guard url.scheme == "porchlight", let opened = url.host().flatMap(PocketTab.init(rawValue:)) else { return }
            you = nil
            tab = opened
        }
        #if DEBUG
        .onAppear(perform: applyDebugStart)
        #endif
        // Last, so the tabs, the You sheet and the reminder keeper all see them.
        .environment(toasts)
        .environment(reminders)
    }

    @ViewBuilder
    private func screen(_ tab: PocketTab) -> some View {
        switch tab {
        case .today: PocketTodayScreen()
        case .calendar: PocketCalendarScreen()
        case .lists: PocketListsScreen()
        case .glow: PocketGlowScreen()
        case .food: PocketFoodScreen()
        }
    }

    #if DEBUG
    /// `-startScreen today|calendar|food|lists|glow|you` opens a tab, or the You sheet over Today.
    private func applyDebugStart() {
        guard let name = UserDefaults.standard.string(forKey: "startScreen") else { return }
        if name == "you" {
            you = YouRequest()
        } else if let start = PocketTab(rawValue: name) {
            tab = start
        }
    }
    #endif
}

/// The top of every tab: a small line, a serif title, and "You" on the right.
struct PocketHeader: View {
    var small: String?
    let title: String
    /// The household's name, tappable to switch, on a phone in more than one (journey A5,
    /// `a5today`); nil otherwise.
    var household: String?

    @Environment(\.openYou) private var openYou
    /// The switcher's chevron grows with the household's name.
    @ScaledMetric(relativeTo: .footnote) private var chevron: CGFloat = 9

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if let household {
                    // "Sunday · Grandma Rosa's ▾" on one line where it fits; at large text
                    // the household goes under the date, whole, with no dot left hanging.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 0) {
                            if let small { smallText(small + " · ") }
                            switcher(household)
                        }
                        .lineLimit(1)
                        VStack(alignment: .leading, spacing: 0) {
                            if let small { smallText(small).fixedSize(horizontal: false, vertical: true) }
                            switcher(household)
                        }
                    }
                } else if let small {
                    Text(small)
                        .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                }
                Text(title)
                    .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PocketYouButton()
        }
    }

    private func smallText(_ text: String) -> some View {
        Text(text)
            .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
            .foregroundStyle(Theme.muted)
    }

    private func switcher(_ household: String) -> some View {
        Button { openYou?() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(household)
                    .phoneFont(.body, 12.5, weight: 800, relativeTo: .footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.system(size: chevron, weight: .heavy))
            }
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(household)
        .accessibilityHint("Shows your households, to switch")
        .accessibilityIdentifier("household-switcher")
    }
}

/// "You": my avatar, at the top right of every tab and every page under it.
struct PocketYouButton: View {
    @Environment(\.me) private var me
    @Environment(\.openYou) private var openYou

    var body: some View {
        Button { openYou?() } label: {
            Group {
                if let me {
                    PersonAvatar(me)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("You")
        .accessibilityValue(me?.name ?? "")
        .accessibilityHint("Who you are, your household and this \(DeviceWords.this)")
        .accessibilityIdentifier("you")
    }
}
