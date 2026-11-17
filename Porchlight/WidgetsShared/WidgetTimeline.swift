import Foundation

/// What a widget shows at one moment, worked out from the summary alone, so a widget is
/// right at every slot's start and end without the app running. Pure, and covered by
/// `WidgetTimelineTests`.
struct WidgetMoment: Equatable, Sendable {
    /// Why a widget can't show the household, or `.ready`.
    enum Availability: Equatable, Sendable {
        /// No summary, or one this widget can't read.
        case missing
        /// The summary is from a shared screen, which has no widgets of its own.
        case sharedScreen
        case noHousehold
        case noMe
        /// The moment is past the days the summary covers.
        case beyondSummary
        case ready
    }

    /// One companion as a widget shows it.
    struct CompanionCard: Equatable, Sendable {
        enum Care: Equatable, Sendable {
            /// A slot is open and nobody has logged it: the log button.
            case open(routineId: String, slot: Int, day: String, name: String, emoji: String, doneWord: String, start: Int, end: Int)
            /// The latest slot done today.
            case done(name: String, by: String?, at: Date)
            /// What opens next today.
            case next(name: String, start: Int)
            /// Nothing more today.
            case allSet
        }

        var id: String
        var name: String
        var face: String
        var care: Care
        /// Minutes since its main routine was last done, if ever.
        var minutesSinceCare: Int?
        /// The next slot still to open today, shown under what was done.
        var upcoming: Upcoming?

        struct Upcoming: Equatable, Sendable {
            var name: String
            var start: Int
        }
    }

    var date: Date
    var availability: Availability
    /// Set when the summary was written long enough before this moment that another device
    /// may have logged meanwhile ("As of 5:40 pm").
    var asOf: Date?
    var day: String
    var companions: [CompanionCard] = []
    var chores: [WidgetSummary.Chore] = []
    var meName: String?
    var meColor: UInt32?
    var glow: WidgetSummary.Glow?
    var groceries: WidgetSummary.Groceries?
    var householdName: String?

    /// How long a summary is trusted before a widget says when it is from.
    static let staleAfter: TimeInterval = 6 * 3600

    var choresLeft: Int { chores.filter { !$0.done }.count }
    var starsToday: Int { chores.filter(\.done).reduce(0) { $0 + $1.stars } }

    func companion(_ id: String?) -> CompanionCard? {
        guard let id else { return companions.first }
        return companions.first { $0.id == id } ?? companions.first
    }

    /// The moment `date` from `summary`.
    static func at(_ date: Date, summary: WidgetSummary?) -> WidgetMoment {
        guard let summary else { return WidgetMoment(date: date, availability: .missing, day: "") }
        if summary.isSharedScreen { return WidgetMoment(date: date, availability: .sharedScreen, day: "") }
        guard let household = summary.household else { return WidgetMoment(date: date, availability: .noHousehold, day: "") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: household.timeZone) ?? .current
        let day = dayKey(date, calendar: calendar)
        var moment = WidgetMoment(date: date, availability: .ready, day: day, householdName: household.name)
        guard let me = summary.me else {
            moment.availability = .noMe
            return moment
        }
        guard summary.days.contains(day) else {
            moment.availability = .beyondSummary
            return moment
        }
        moment.meName = me.name
        moment.meColor = me.color
        if date.timeIntervalSince(summary.writtenAt) > staleAfter { moment.asOf = summary.writtenAt }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        moment.companions = summary.companions.map { card($0, day: day, minute: minute, date: date) }
        moment.chores = summary.chores.filter { $0.day == day }
        moment.glow = summary.glow
        moment.groceries = summary.groceries
        return moment
    }

    private static func card(_ companion: WidgetSummary.CompanionInfo, day: String, minute: Int, date: Date) -> CompanionCard {
        let slots = companion.routines.flatMap { routine in
            routine.slots.filter { $0.day == day }.map { (routine, $0) }
        }
        let care: CompanionCard.Care
        if let (routine, slot) = slots.first(where: { !$1.isDone && $1.start <= minute && minute < $1.end }) {
            care = .open(
                routineId: routine.id, slot: slot.index, day: day, name: slot.name, emoji: routine.emoji,
                doneWord: routine.doneWord, start: slot.start, end: slot.end
            )
        } else if let (_, slot) = slots.filter({ $1.isDone && ($1.doneAt ?? .distantFuture) <= date })
            .max(by: { ($0.1.doneAt ?? .distantPast) < ($1.1.doneAt ?? .distantPast) }),
            let at = slot.doneAt {
            care = .done(name: slot.name, by: slot.doneBy, at: at)
        } else if let (_, slot) = slots.filter({ !$1.isDone && $1.start > minute }).min(by: { $0.1.start < $1.1.start }) {
            care = .next(name: slot.name, start: slot.start)
        } else {
            care = .allSet
        }
        let since = companion.lastCare.flatMap { last in last <= date ? Int(date.timeIntervalSince(last) / 60) : nil }
        let upcoming = slots.filter { !$1.isDone && $1.start > minute }.min { $0.1.start < $1.1.start }
            .map { CompanionCard.Upcoming(name: $0.1.name, start: $0.1.start) }
        return CompanionCard(id: companion.id, name: companion.name, face: companion.face, care: care, minutesSinceCare: since, upcoming: upcoming)
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// When a widget's timeline needs a new entry: now, every slot window's start and end, each
/// midnight the summary covers, and every hour for the counts that grow. Pure.
enum WidgetTimeline {
    static let maxEntries = 48

    static func dates(for summary: WidgetSummary?, from now: Date) -> [Date] {
        var dates: Set<Date> = [now]
        // Every hour on the hour, for "9h since the last walk".
        let hour = Calendar(identifier: .gregorian).dateInterval(of: .hour, for: now)?.start ?? now
        for step in 1...24 { dates.insert(hour.addingTimeInterval(Double(step) * 3600)) }
        if let summary, let household = summary.household {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: household.timeZone) ?? .current
            for day in summary.days {
                guard let start = startOfDay(day, calendar: calendar) else { continue }
                dates.insert(start)
                for slot in summary.companions.flatMap({ $0.routines.flatMap(\.slots) }) where slot.day == day {
                    dates.insert(start.addingTimeInterval(Double(slot.start) * 60))
                    dates.insert(start.addingTimeInterval(Double(slot.end) * 60))
                }
            }
            // The moment the summary turns stale, so "As of" appears on time.
            dates.insert(summary.writtenAt.addingTimeInterval(WidgetMoment.staleAfter + 1))
        }
        return Array(dates.filter { $0 >= now }.sorted().prefix(maxEntries))
    }

    private static func startOfDay(_ day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// The words widgets use, shared so they read the same in every family.
enum WidgetWords {
    /// Whether this device shows a 12-hour clock, as the app's `ClockFormat` decides.
    static var twelveHour: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
    }

    /// "5 to 8pm", "8:30 to 10am", "17 to 20": a window, in the app's words.
    static func window(_ start: Int, _ end: Int, twelveHour: Bool = WidgetWords.twelveHour) -> String {
        if start <= 0 && end >= 1440 { return "Any time today" }
        let samePeriod = end < 1440 && (start < 720) == (end < 720)
        return "\(time(start, withPeriod: !samePeriod, twelveHour: twelveHour)) to \(time(end, twelveHour: twelveHour))"
    }

    /// "5pm", "8:30am" (or "17", "8:30"), like the app's `CareTime.hour`.
    static func time(_ minute: Int, withPeriod: Bool = true, twelveHour: Bool = WidgetWords.twelveHour) -> String {
        let minutes = ((minute % 1440) + 1440) % 1440
        let hour24 = minutes / 60, minute = minutes % 60
        guard twelveHour else { return minute == 0 ? "\(hour24)" : String(format: "%d:%02d", hour24, minute) }
        let hour = (hour24 + 11) % 12 + 1
        let clock = minute == 0 ? "\(hour)" : String(format: "%d:%02d", hour, minute)
        return withPeriod ? clock + (hour24 < 12 ? "am" : "pm") : clock
    }

    /// "45m", "9h", "2d".
    static func since(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(minutes, 0))m" }
        if minutes < 48 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }

    /// "5:40pm" for a moment, in the household's time zone.
    static func clock(_ date: Date, timeZone: TimeZone, twelveHour: Bool = WidgetWords.twelveHour) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return time((parts.hour ?? 0) * 60 + (parts.minute ?? 0), twelveHour: twelveHour)
    }
}
