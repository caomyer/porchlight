import Foundation

// What a time field understands: a typed time ("7", "715", "7:15p", "1930"),
// the iPad's 12 or 24-hour clock, and which half of the day a typed time
// without AM or PM most likely means. Pure and covered by TimeEntryTests.

/// The iPad's clock style, and times written in it.
struct ClockStyle: Equatable, Sendable {
    var uses24Hours: Bool

    static let current = ClockStyle(locale: .current)

    init(uses24Hours: Bool) {
        self.uses24Hours = uses24Hours
    }

    /// 24-hour when the locale's hour pattern has no AM/PM marker.
    init(locale: Locale) {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        uses24Hours = !pattern.contains("a")
    }

    /// "7:12" and "PM", or "19:12" and nil. Minutes run from midnight and may pass it.
    func parts(_ minute: Int) -> (time: String, period: String?) {
        let minute = ((minute % TimeEntry.day) + TimeEntry.day) % TimeEntry.day
        let hour = minute / 60, rest = String(format: "%02d", minute % 60)
        if uses24Hours { return (String(format: "%02d", hour) + ":" + rest, nil) }
        return ("\((hour + 11) % 12 + 1):\(rest)", hour < 12 ? "AM" : "PM")
    }

    /// "7:12 PM" or "19:12".
    func text(_ minute: Int) -> String {
        let parts = parts(minute)
        return parts.period.map { "\(parts.time) \($0)" } ?? parts.time
    }
}

/// A time as someone typed it.
struct TypedTime: Equatable, Sendable {
    enum Meridiem: Sendable { case am, pm }

    var hour: Int
    var minute: Int
    var meridiem: Meridiem?

    /// Reads "7", "715", "7:15", "7.15", "1930", "7p", "7:15 am". Nil if it isn't a time.
    static func parse(_ text: String) -> TypedTime? {
        var rest = text.lowercased().filter { !$0.isWhitespace }.replacingOccurrences(of: ".", with: ":")
        var meridiem: Meridiem?
        for (suffix, value) in [("am", Meridiem.am), ("pm", .pm), ("a", .am), ("p", .pm)] where rest.hasSuffix(suffix) {
            meridiem = value
            rest.removeLast(suffix.count)
            break
        }
        let pieces = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(pieces.count), pieces.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        let hour: Int, minute: Int
        if pieces.count == 2 {
            guard (1...2).contains(pieces[0].count), pieces[1].count == 2 else { return nil }
            hour = Int(pieces[0]) ?? -1
            minute = Int(pieces[1]) ?? -1
        } else {
            let digits = Array(pieces[0])
            switch digits.count {
            case 1, 2: hour = Int(String(digits)) ?? -1; minute = 0
            case 3: hour = Int(String(digits[0])) ?? -1; minute = Int(String(digits[1...])) ?? -1
            case 4: hour = Int(String(digits[0...1])) ?? -1; minute = Int(String(digits[2...])) ?? -1
            default: return nil
            }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if meridiem != nil, !(1...12).contains(hour) { return nil }
        return TypedTime(hour: hour, minute: minute, meridiem: meridiem)
    }

    /// Minutes from midnight this could mean: one when the half of the day is
    /// known, both when it isn't ("7" on a 12-hour clock).
    func candidates(_ clock: ClockStyle) -> [Int] {
        switch meridiem {
        case .am: return [(hour % 12) * 60 + minute]
        case .pm: return [(hour % 12 + 12) * 60 + minute]
        case nil:
            if clock.uses24Hours || hour == 0 || hour > 12 { return [hour * 60 + minute] }
            return [(hour % 12) * 60 + minute, (hour % 12 + 12) * 60 + minute]
        }
    }
}

/// Choosing among a typed time's candidates.
enum TimeEntry {
    static let day = 24 * 60

    /// For something that happened on a day: the candidate within `allowed`
    /// (minutes from that day's midnight) closest to the time already shown, so
    /// "8" on a breakfast is 8 AM and on a dinner 8 PM. If none fits, the result
    /// says which one was meant so the field can explain why it can't be used.
    static func pickLogged(_ candidates: [Int], allowed: ClosedRange<Int>, near current: Int) -> Result<Int, OutOfRange> {
        let fitting = candidates.filter(allowed.contains)
        if let closest = fitting.min(by: { abs($0 - current) < abs($1 - current) }) { return .success(closest) }
        let meant = candidates.min { distance($0, to: allowed) < distance($1, to: allowed) } ?? 0
        return .failure(OutOfRange(minute: meant, isLater: meant > allowed.upperBound))
    }

    /// The end of a stretch of hours: the first candidate after `start`, wrapping
    /// into the next day. Returns minutes from midnight (0..<1440).
    static func pickEnd(_ candidates: [Int], after start: Int) -> Int {
        candidates.map { $0 <= start ? $0 + day : $0 }.min().map { $0 % day } ?? start
    }

    /// The start of a stretch of hours: the candidate closest to where it was.
    static func pickNear(_ candidates: [Int], to current: Int) -> Int {
        candidates.min { circular($0, current) < circular($1, current) } ?? current
    }

    struct OutOfRange: Error, Equatable {
        var minute: Int
        var isLater: Bool
    }

    private static func distance(_ minute: Int, to range: ClosedRange<Int>) -> Int {
        minute < range.lowerBound ? range.lowerBound - minute : max(0, minute - range.upperBound)
    }

    private static func circular(_ a: Int, _ b: Int) -> Int {
        let delta = abs(a - b) % day
        return min(delta, day - delta)
    }
}
