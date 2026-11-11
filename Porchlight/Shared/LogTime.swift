import Foundation

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

    /// "Just now", "30 min ago", "1 hr ago", "2 hr ago": a log's usual times.
    static func recentSuggestions(justNow: String = "Just now") -> [(title: String, time: LogTime)] {
        [(justNow, .justNow)] + [30, 60, 120].map { (agoText($0), .minutesAgo($0)) }
    }

    /// "30 min ago", "1 hr ago".
    static func agoText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) hr ago"
    }
}
