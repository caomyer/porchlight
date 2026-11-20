import Foundation
import GRDB
import SwiftUI

// Value types for companions: anything the household looks after (a dog, a
// cat, a fern). Nothing here knows about one particular family or pet.

// MARK: - Species

enum Species: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case dog, cat, bird, rabbit, fish, plant, other

    var label: String {
        switch self {
        case .dog: "Dog"
        case .cat: "Cat"
        case .bird: "Bird"
        case .rabbit: "Rabbit"
        case .fish: "Fish"
        case .plant: "Plant"
        case .other: "Other"
        }
    }

    var emoji: String {
        switch self {
        case .dog: "🐕"
        case .cat: "🐈"
        case .bird: "🐦"
        case .rabbit: "🐇"
        case .fish: "🐠"
        case .plant: "🪴"
        case .other: "🐾"
        }
    }

    /// Species with a hand-drawn face; the rest show their emoji in a circle.
    var hasDrawnFace: Bool { self == .dog || self == .cat }
}

// MARK: - Look

/// A coat color preset: main fur color plus a darker shade for ears.
enum CoatPreset: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case honey, cream, cocoa, silver, ginger

    var main: Color {
        switch self {
        case .honey: Color(hex: 0xE8B477)
        case .cream: Color(hex: 0xF4EEE6)
        case .cocoa: Color(hex: 0x3B302A)
        case .silver: Color(hex: 0x9B9B9B)
        case .ginger: Color(hex: 0xC9773D)
        }
    }

    var shade: Color {
        switch self {
        case .honey: Color(hex: 0xB8763A)
        case .cream: Color(hex: 0xD8C6AE)
        case .cocoa: Color(hex: 0x231B16)
        case .silver: Color(hex: 0x6F6F6F)
        case .ginger: Color(hex: 0x8E4F22)
        }
    }

    /// The companion's accent color on cards, lanes and the celebration.
    var tint: Color {
        switch self {
        case .honey: Color(hex: 0xE1A75A)
        case .cream: Color(hex: 0xD9B98E)
        case .cocoa: Color(hex: 0xA5826A)
        case .silver: Color(hex: 0x9AA3AE)
        case .ginger: Color(hex: 0xD98A4E)
        }
    }

    var isDark: Bool { self == .cocoa }

    var label: String {
        switch self {
        case .honey: "Honey"
        case .cream: "Cream"
        case .cocoa: "Cocoa"
        case .silver: "Silver"
        case .ginger: "Ginger"
        }
    }
}

// MARK: - Captions

enum CompanionTone: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case wholesome, cheeky, dramatic, off

    var label: String {
        switch self {
        case .wholesome: "Wholesome"
        case .cheeky: "Cheeky"
        case .dramatic: "Dramatic"
        case .off: "Off"
        }
    }
}

// MARK: - Care

/// What a routine is, which decides its wording ("walked", "fed", "watered").
enum CareKind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case walk, feed, litter, water, groom, meds, play, clean, custom

    var defaultTitle: String {
        switch self {
        case .walk: "Walk"
        case .feed: "Feed"
        case .litter: "Litter"
        case .water: "Water"
        case .groom: "Groom"
        case .meds: "Meds"
        case .play: "Play"
        case .clean: "Clean"
        case .custom: "Check in"
        }
    }

    var defaultEmoji: String {
        switch self {
        case .walk: "🦮"
        case .feed: "🥣"
        case .litter: "🧹"
        case .water: "💧"
        case .groom: "🪮"
        case .meds: "💊"
        case .play: "🧶"
        case .clean: "🫧"
        case .custom: "✨"
        }
    }

    /// Past-tense sentence: "Mia walked Yo-Yo".
    func sentence(who: String, name: String, title: String) -> String {
        switch self {
        case .walk: "\(who) walked \(name)"
        case .feed: "\(who) fed \(name)"
        case .litter: "\(who) did \(name.possessive) litter"
        case .water: "\(who) watered \(name)"
        case .groom: "\(who) groomed \(name)"
        case .meds: "\(who) gave \(name) meds"
        case .play: "\(who) played with \(name)"
        case .clean: "\(who) cleaned up for \(name)"
        case .custom: "\(who) · \(title)"
        }
    }

    /// The big button: "I walked Yo-Yo".
    func buttonTitle(name: String, title: String) -> String {
        sentence(who: "I", name: name, title: title)
    }

    /// The log sheet question: "Who walked Yo-Yo?"
    func question(name: String, title: String) -> String {
        switch self {
        case .custom: "Who did \(title.lowercased())?"
        default: sentence(who: "Who", name: name, title: title) + "?"
        }
    }

    /// "Walked 1h ago".
    var pastVerb: String {
        switch self {
        case .walk: "Walked"
        case .feed: "Fed"
        case .litter: "Litter done"
        case .water: "Watered"
        case .groom: "Groomed"
        case .meds: "Meds given"
        case .play: "Played"
        case .clean: "Cleaned"
        case .custom: "Last done"
        }
    }

    /// "walk", "feeding": used in captions and headings.
    func noun(title: String) -> String {
        switch self {
        case .walk: "walk"
        case .feed: "meal"
        case .water: "watering"
        case .custom: title.lowercased()
        default: title.lowercased()
        }
    }

    /// The podium title: "Walker of the week".
    var agentNoun: String {
        switch self {
        case .walk: "Walker"
        case .feed: "Chef"
        case .water: "Gardener"
        case .litter: "Scooper"
        case .groom: "Groomer"
        case .meds: "Nurse"
        case .play: "Playmate"
        case .clean, .custom: "Helper"
        }
    }
}

/// Details a routine asks for when someone logs it.
enum CareField: String, Codable, CaseIterable, Sendable {
    case duration, pee, poo, vibe

    var label: String {
        switch self {
        case .duration: "⏱ duration"
        case .pee: "💧 pee"
        case .poo: "💩 poo"
        case .vibe: "😎 vibe"
        }
    }
}

/// How an outing went. Stored as a stable token.
enum CareVibe: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case smooth, squirrel, soggy, friend

    var label: String {
        switch self {
        case .smooth: "Smooth"
        case .squirrel: "Squirrel chaos"
        case .soggy: "Soggy"
        case .friend: "Made a friend"
        }
    }

    var emoji: String {
        switch self {
        case .smooth: "😎"
        case .squirrel: "🐿️"
        case .soggy: "🌧️"
        case .friend: "🐕"
        }
    }
}

/// A daily time window for one slot, e.g. Morning 6-10am. Minutes from midnight.
struct CareWindow: Codable, Equatable, Hashable, Sendable {
    var label: String
    var start: Int
    var end: Int

    init(_ label: String, start: Int, end: Int) {
        self.label = label
        self.start = start
        self.end = end
    }

    static func hours(_ label: String, _ startHour: Int, _ endHour: Int) -> CareWindow {
        CareWindow(label, start: startHour * 60, end: endHour * 60)
    }

    static let anyTime = CareWindow("Any time", start: 0, end: 24 * 60)

    var isAllDay: Bool { start <= 0 && end >= 24 * 60 }

    var midpoint: Int { (start + end) / 2 }

    func contains(minute: Int) -> Bool { minute >= start && minute <= end }

    /// Minutes between `minute` and this window (0 when inside).
    func distance(to minute: Int) -> Int {
        if minute < start { return start - minute }
        if minute > end { return minute - end }
        return 0
    }

    /// "6-10am", "11am-1pm", "Any time".
    var rangeText: String {
        if isAllDay { return "Any time" }
        return CareTime.range(start, end)
    }
}

/// Compact wall-style times: "6", "6:30", "6am", "5-8pm" (or "17-20" on a 24-hour clock).
enum CareTime {
    static func hour(_ minutes: Int, withPeriod: Bool = true, twelveHour: Bool = ClockFormat.usesTwelveHourClock) -> String {
        let minutes = ((minutes % 1440) + 1440) % 1440
        let h = minutes / 60, m = minutes % 60
        guard twelveHour else { return m == 0 ? "\(h)" : String(format: "%d:%02d", h, m) }
        let h12 = (h + 11) % 12 + 1
        let base = m == 0 ? "\(h12)" : String(format: "%d:%02d", h12, m)
        return withPeriod ? base + (h < 12 ? "am" : "pm") : base
    }

    static func range(_ start: Int, _ end: Int, twelveHour: Bool = ClockFormat.usesTwelveHourClock) -> String {
        guard twelveHour else {
            return hour(start, twelveHour: false) + "-" + (end >= 1440 ? "24" : hour(end, twelveHour: false))
        }
        let samePeriod = end < 1440 && (start / 720) == (end / 720)
        let endText = end >= 1440 ? "midnight" : hour(end, twelveHour: true)
        return (samePeriod ? hour(start, withPeriod: false, twelveHour: true) : hour(start, twelveHour: true)) + "-" + endText
    }
}
