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

/// "When?" on a log sheet: quick choices for the usual cases and a time pill
/// that always shows the resolved time; tapping it opens a ruler of the day to
/// take any other one. The range stays within one day, so only the time is shown.
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
    /// The usual times shaded on the ruler.
    var bands: [TimeBand] = []
    var rulerLabel = "Time"
    var calendar: Calendar = .current

    @State private var rulerOpen = false

    private static let offsets = [30, 60, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                if showsChoices {
                    ChoicePill(title: justNowTitle, isSelected: time == .justNow) { time = .justNow }
                    ForEach(Self.offsets, id: \.self) { minutes in
                        ChoicePill(title: Self.agoText(minutes), isSelected: time == .minutesAgo(minutes)) { time = .minutesAgo(minutes) }
                    }
                }
                TimePill(date: resolved, isOpen: $rulerOpen, calendar: calendar, accessibilityLabel: "Exact time", identifier: "exact-time")
            }
            if rulerOpen {
                LogTimeRuler(time: $time, range: range, now: now, lasting: lasting, bands: bands, calendar: calendar, accessibilityLabel: rulerLabel, isOpen: $rulerOpen)
            }
        }
    }

    private var range: ClosedRange<Date> { earliest...max(earliest, latest ?? now) }

    private var resolved: Date {
        min(max(time.start(now: now, lasting: lasting), range.lowerBound), range.upperBound)
    }

    /// "30 min ago", "1 hr ago".
    nonisolated static func agoText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) hr ago"
    }
}

/// The time something happened as a pill, e.g. a meal's time on its label line.
/// The ruler it opens is placed by the form, under the choices it relates to.
struct AtTimeField: View {
    @Binding var time: LogTime
    let range: ClosedRange<Date>
    @Binding var isOpen: Bool
    var calendar: Calendar = .current

    var body: some View {
        TimePill(
            date: min(max(time.start(now: .now), range.lowerBound), range.upperBound),
            isOpen: $isOpen,
            calendar: calendar,
            accessibilityLabel: "Time eaten",
            identifier: "time-eaten"
        )
    }
}

/// A day ruler that picks an exact `LogTime` within `range`.
struct LogTimeRuler: View {
    @Binding var time: LogTime
    let range: ClosedRange<Date>
    var now: Date = .now
    var lasting = 0
    var bands: [TimeBand] = []
    var calendar: Calendar = .current
    var accessibilityLabel = "Time"
    @Binding var isOpen: Bool

    var body: some View {
        DayRuler(
            date: Binding(
                get: { min(max(time.start(now: now, lasting: lasting), range.lowerBound), range.upperBound) },
                set: { time = .at($0) }
            ),
            range: range,
            bands: bands,
            calendar: calendar,
            accessibilityLabel: accessibilityLabel,
            onDone: { isOpen = false }
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
