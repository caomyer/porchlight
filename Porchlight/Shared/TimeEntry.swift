import Foundation

// What a time field knows: the iPad's 12 or 24-hour clock, and typing into a
// time's hour or minutes one digit at a time. Pure and covered by TimeEntryTests.

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

    /// The hour and minutes as shown in their own boxes: "7" and "05", or "07" and "05".
    func fields(_ minute: Int) -> (hour: String, minute: String) {
        let minute = ((minute % TimeEntry.day) + TimeEntry.day) % TimeEntry.day
        let hour = minute / 60
        return (uses24Hours ? String(format: "%02d", hour) : "\((hour + 11) % 12 + 1)", String(format: "%02d", minute % 60))
    }
}

/// Typing into a time's hour or minutes. Every digit counts the moment it is
/// typed, so changing the hour from 2 to 1 is one tap. A digit that could start
/// a two-digit value ("1" for 10, 11 or 12) stays open for one more; a digit
/// that can't follow it goes on to the minutes, so 7 1 5 is 7:15. Once the hour
/// can't take another digit, the minutes are next. Typing an hour keeps the
/// half of the day shown.
struct TimeTyping: Equatable, Sendable {
    enum Part: Sendable { case hour, minute }

    private(set) var part: Part = .hour
    /// The digit still open for a second one, if any.
    private(set) var open: Int?

    mutating func select(_ part: Part) {
        self.part = part
        open = nil
    }

    /// Ends an open digit; with none, steps back from the minutes to the hour.
    mutating func delete() {
        if open != nil { open = nil } else { part = .hour }
    }

    /// `minute` (from midnight) with `digit` typed into the selected part.
    mutating func type(_ digit: Int, into minute: Int, clock: ClockStyle) -> Int {
        let minute = ((minute % TimeEntry.day) + TimeEntry.day) % TimeEntry.day
        switch part {
        case .hour:
            if let first = open {
                open = nil
                part = .minute
                let hour = first * 10 + digit
                if clock.uses24Hours ? hour <= 23 : (1...12).contains(hour) {
                    return Self.setting(hour: hour, of: minute, clock: clock)
                }
                return type(digit, into: minute, clock: clock)
            }
            if digit <= (clock.uses24Hours ? 2 : 1) {
                open = digit
                // A lone 0 isn't an hour on a 12-hour clock; it waits for the next digit.
                return digit == 0 && !clock.uses24Hours ? minute : Self.setting(hour: digit, of: minute, clock: clock)
            }
            part = .minute
            return Self.setting(hour: digit, of: minute, clock: clock)
        case .minute:
            let hourStart = minute - minute % 60
            if let first = open {
                open = nil
                return hourStart + first * 10 + digit
            }
            if digit <= 5 { open = digit }
            return hourStart + digit
        }
    }

    /// `minute` with its hour set as shown on `clock`, keeping AM or PM on a 12-hour clock.
    static func setting(hour: Int, of minute: Int, clock: ClockStyle) -> Int {
        let rest = minute % 60
        if clock.uses24Hours { return hour * 60 + rest }
        return (hour % 12 + (minute >= 12 * 60 ? 12 : 0)) * 60 + rest
    }

    /// The other half of the day.
    static func flipping(_ minute: Int, toPM pm: Bool) -> Int {
        let minute = ((minute % TimeEntry.day) + TimeEntry.day) % TimeEntry.day
        guard (minute >= 12 * 60) != pm else { return minute }
        return pm ? minute + 12 * 60 : minute - 12 * 60
    }

    /// One step up or down: an hour, or a minute within the hour.
    func nudging(_ minute: Int, by step: Int) -> Int {
        let minute = ((minute % TimeEntry.day) + TimeEntry.day) % TimeEntry.day
        switch part {
        case .hour: return ((minute + step * 60) % TimeEntry.day + TimeEntry.day) % TimeEntry.day
        case .minute: return minute - minute % 60 + ((minute % 60 + step) % 60 + 60) % 60
        }
    }

    /// What typing does next, shown under the time.
    func hint(_ clock: ClockStyle) -> String {
        guard let open else { return part == .hour ? "Type to replace the hour" : "Type to replace the minutes" }
        if part == .minute { return "Another digit makes it \(open)0 to \(open)9" }
        if clock.uses24Hours { return open == 2 ? "Another digit makes it 20 to 23" : "Another digit makes it \(open)0 to \(open)9" }
        return open == 1 ? "Another 0, 1 or 2 makes it 10, 11 or 12" : "Type the hour"
    }
}

enum TimeEntry {
    static let day = 24 * 60
}
