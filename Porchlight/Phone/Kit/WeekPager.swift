import SwiftUI

/// Which week a page shows, and how to show another: Food's diary and a companion's week.
struct WeekPage {
    let weeksBack: Int
    /// The furthest back it goes: the week of the first thing there is to show.
    let limit: Int
    /// What VoiceOver reads for it: "Last week, Nov 8 to 14, 18 meals".
    let spoken: String
    let go: (Int) -> Void
}

/// A week's top row: "‹ Last week ›", with "Back to this week" when away from it. Back
/// stops at the first week there is; forward isn't there on this week, which ends today.
struct WeekPager: View {
    let page: WeekPage

    @PhoneMetric(upTo: 1.4) private var chevron: CGFloat = 36

    var body: some View {
        // The arrows and the week's name share one row and one centre line, at every text
        // size. Away from this week, "Back to this week" sits under the name, the two
        // centred on the arrows together. The row is always as tall as the name and the link
        // need, shown or not, so the week below never moves when stepping away, at any text
        // size; at the usual sizes that is about the arrows' own height, so no row of its own
        // is kept for the link.
        let away = page.weeksBack > 0
        HStack(alignment: .center, spacing: 6) {
            arrow("chevron.left", label: "Previous week", id: "week-back", shown: page.weeksBack < page.limit) {
                page.go(page.weeksBack + 1)
            }
            ZStack {
                VStack(spacing: 0) {
                    name
                    backToThisWeek
                }
                .hidden()
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    name
                        .accessibilityLabel(page.spoken)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("week-name")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: if page.weeksBack > 0 { page.go(page.weeksBack - 1) }
                            case .decrement: if page.weeksBack < page.limit { page.go(page.weeksBack + 1) }
                            @unknown default: break
                            }
                        }
                    if away {
                        backToThisWeek
                            .accessibilityIdentifier("week-this")
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            arrow("chevron.right", label: "Next week", id: "week-forward", shown: away) {
                page.go(page.weeksBack - 1)
            }
        }
    }

    private var name: some View {
        Text(WeekPaging.weekName(weeksBack: page.weeksBack))
            .phoneFont(.display, 17, weight: 600, relativeTo: .headline)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            // Grown to the largest sizes, the words would crowd out the week they name.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var backToThisWeek: some View {
        Button("Back to this week") { page.go(0) }
            .phoneFont(.body, 12.5, weight: 800, relativeTo: .footnote)
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 24)
            .contentShape(Rectangle())
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// A round chevron, or the room for one so the name stays centered.
    @ViewBuilder
    private func arrow(_ symbol: String, label: String, id: String, shown: Bool, action: @escaping () -> Void) -> some View {
        if shown {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: chevron * 0.42, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: chevron, height: chevron)
                    .background(Theme.surface2, in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
        } else {
            Color.clear.frame(width: max(chevron, 44), height: 44).accessibilityHidden(true)
        }
    }
}
