import SwiftUI

/// When something happened, as picked on a log sheet. Relative choices stay
/// relative until saved, so a sheet left open a while still means "just now".
enum LogTime: Equatable {
    /// Just now. For something with a length (a walk), it just ended.
    case justNow
    /// Started this many minutes ago.
    case minutesAgo(Int)
    /// Started at an exact time.
    case at(Date)

    /// When it started, given the current time and how many minutes it lasted.
    func start(now: Date, lasting minutes: Int = 0) -> Date {
        switch self {
        case .justNow: now.addingTimeInterval(-Double(minutes) * 60)
        case let .minutesAgo(ago): now.addingTimeInterval(-Double(ago) * 60)
        case let .at(date): date
        }
    }
}

/// "When?" on a log sheet: quick choices for the usual cases and an exact time
/// field that always shows the resolved time and takes any other one. The range
/// stays within one day, so only the time is shown.
struct WhenPicker: View {
    @Binding var time: LogTime
    let now: Date
    /// How long it lasted, so "just now" means it just ended.
    var lasting = 0
    var justNowTitle = "Just now"
    /// Hides the relative choices, e.g. for a meal on another day.
    var showsChoices = true
    /// Earliest time allowed.
    let earliest: Date
    /// Latest time allowed; nil means now.
    var latest: Date?
    var calendar: Calendar = .current

    private static let offsets = [30, 60, 120]

    var body: some View {
        FlowLayout(spacing: 8) {
            if showsChoices {
                ChoicePill(title: justNowTitle, isSelected: time == .justNow) { time = .justNow }
                ForEach(Self.offsets, id: \.self) { minutes in
                    ChoicePill(title: Self.agoText(minutes), isSelected: time == .minutesAgo(minutes)) { time = .minutesAgo(minutes) }
                }
            }
            DatePicker(
                "Time",
                selection: Binding(get: { resolved }, set: { time = .at($0) }),
                in: earliest...max(earliest, upper),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .environment(\.calendar, calendar)
            .accessibilityLabel("Exact time")
            .accessibilityIdentifier("exact-time")
        }
    }

    private var upper: Date { latest ?? now }

    private var resolved: Date {
        min(max(time.start(now: now, lasting: lasting), earliest), upper)
    }

    /// "30 min ago", "1 hr ago".
    nonisolated static func agoText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) hr ago"
    }
}

/// "at 6:40 PM": a compact exact-time field for something on a known day.
struct AtTimeField: View {
    @Binding var time: LogTime
    let range: ClosedRange<Date>
    var calendar: Calendar = .current

    var body: some View {
        HStack(spacing: 6) {
            Text("at")
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
            DatePicker(
                "Time",
                selection: Binding(
                    get: { min(max(time.start(now: .now), range.lowerBound), range.upperBound) },
                    set: { time = .at($0) }
                ),
                in: range,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .environment(\.calendar, calendar)
            .accessibilityLabel("Time eaten")
            .accessibilityIdentifier("time-eaten")
        }
        .fixedSize()
    }
}
