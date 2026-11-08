import Foundation

/// Picks an emoji (and, for celebrations, a month-view sticker) from an event
/// title. Matching is case-insensitive, by whole words, and deterministic: the
/// first rule in table order wins, so more specific rules come first.
enum EventDecoration {
    /// Special days that get a countdown and a sticker.
    enum Celebration: Equatable, Sendable {
        case birthday, anniversary, holiday
    }

    struct Rule: Sendable {
        /// Words or short phrases ("book club"). A trailing "s"/"es" also matches.
        var keywords: [String]
        var emoji: String
        var celebration: Celebration? = nil
    }

    struct Match: Equatable, Sendable {
        var emoji: String
        var celebration: Celebration?
    }

    /// Checked first, so "Birthday dinner" is a birthday, not a dinner.
    static let celebrationRules: [Rule] = [
        Rule(keywords: ["birthday", "bday", "b-day"], emoji: "🎂", celebration: .birthday),
        Rule(keywords: ["anniversary"], emoji: "🥂", celebration: .anniversary),
        Rule(keywords: ["thanksgiving"], emoji: "🦃", celebration: .holiday),
        Rule(keywords: ["christmas", "xmas"], emoji: "🎄", celebration: .holiday),
        Rule(keywords: ["halloween"], emoji: "🎃", celebration: .holiday),
        Rule(keywords: ["new year's eve", "new years eve", "new year's day", "new year"], emoji: "🎆", celebration: .holiday),
        Rule(keywords: ["valentine", "valentine's day"], emoji: "💝", celebration: .holiday),
        Rule(keywords: ["easter"], emoji: "🐣", celebration: .holiday),
        Rule(keywords: ["hanukkah", "chanukah"], emoji: "🕎", celebration: .holiday),
        Rule(keywords: ["diwali"], emoji: "🪔", celebration: .holiday),
        Rule(keywords: ["lunar new year", "chinese new year"], emoji: "🧧", celebration: .holiday),
        Rule(keywords: ["independence day", "fourth of july", "4th of july"], emoji: "🎆", celebration: .holiday),
        Rule(keywords: ["mother's day", "father's day"], emoji: "💐", celebration: .holiday),
        Rule(keywords: ["wedding"], emoji: "💒", celebration: .anniversary),
        Rule(keywords: ["graduation"], emoji: "🎓", celebration: .holiday),
    ]

    static let everydayRules: [Rule] = [
        Rule(keywords: ["book club"], emoji: "📚"),
        Rule(keywords: ["taco", "tacos"], emoji: "🌮"),
        Rule(keywords: ["sushi"], emoji: "🍣"),
        Rule(keywords: ["pizza"], emoji: "🍕"),
        Rule(keywords: ["bbq", "barbecue", "cookout"], emoji: "🍖"),
        Rule(keywords: ["brunch", "pancake"], emoji: "🥞"),
        Rule(keywords: ["meal prep", "salad"], emoji: "🥗"),
        Rule(keywords: ["bake sale", "cupcake"], emoji: "🧁"),
        Rule(keywords: ["coffee"], emoji: "☕️"),
        Rule(keywords: ["lunch", "noodle", "ramen", "pho"], emoji: "🍜"),
        Rule(keywords: ["dinner", "supper"], emoji: "🍽️"),
        Rule(keywords: ["soccer", "football"], emoji: "⚽️"),
        Rule(keywords: ["tennis"], emoji: "🎾"),
        Rule(keywords: ["basketball"], emoji: "🏀"),
        Rule(keywords: ["baseball", "softball"], emoji: "⚾️"),
        Rule(keywords: ["golf"], emoji: "⛳️"),
        Rule(keywords: ["swim", "swimming", "pool"], emoji: "🏊"),
        Rule(keywords: ["climbing", "climb", "bouldering"], emoji: "🧗"),
        Rule(keywords: ["yoga", "pilates"], emoji: "🧘"),
        Rule(keywords: ["gym", "workout", "crossfit", "lift", "lifting"], emoji: "🏋️"),
        Rule(keywords: ["run", "running", "jog", "marathon"], emoji: "🏃"),
        Rule(keywords: ["bike", "cycling", "spin"], emoji: "🚴"),
        Rule(keywords: ["hike", "hiking"], emoji: "🥾"),
        Rule(keywords: ["ski", "skiing", "snowboard"], emoji: "⛷️"),
        Rule(keywords: ["dentist", "dental", "orthodontist"], emoji: "🦷"),
        Rule(keywords: ["doctor", "checkup", "check-up", "appointment", "physio", "clinic"], emoji: "🩺"),
        Rule(keywords: ["vet"], emoji: "🐾"),
        Rule(keywords: ["haircut", "hair", "barber", "salon"], emoji: "✂️"),
        Rule(keywords: ["flight", "fly", "airport"], emoji: "✈️"),
        Rule(keywords: ["trip", "vacation", "holiday", "getaway"], emoji: "✈️"),
        Rule(keywords: ["train"], emoji: "🚆"),
        Rule(keywords: ["visit", "visiting", "staying"], emoji: "🧳"),
        Rule(keywords: ["movie", "movies", "cinema", "film"], emoji: "🎬"),
        Rule(keywords: ["concert", "gig", "show"], emoji: "🎵"),
        Rule(keywords: ["theater", "theatre", "musical"], emoji: "🎭"),
        Rule(keywords: ["pottery", "ceramics", "clay"], emoji: "🏺"),
        Rule(keywords: ["painting", "art"], emoji: "🎨"),
        Rule(keywords: ["piano", "guitar", "music lesson"], emoji: "🎹"),
        Rule(keywords: ["party"], emoji: "🎉"),
        Rule(keywords: ["market", "groceries", "grocery", "shopping"], emoji: "🛒"),
        Rule(keywords: ["call", "phone"], emoji: "📞"),
        Rule(keywords: ["school", "class", "lesson"], emoji: "🎒"),
        Rule(keywords: ["tree"], emoji: "🎄"),
        Rule(keywords: ["day off", "pto"], emoji: "🛋️"),
        Rule(keywords: ["cleaning", "cleaner"], emoji: "🧹"),
        Rule(keywords: ["garden", "gardening"], emoji: "🌱"),
        Rule(keywords: ["dog", "walk"], emoji: "🐕"),
        Rule(keywords: ["date night"], emoji: "💕"),
    ]

    /// Ordinal birthdays like "Grandma's 80th" or "Sam turns 40".
    private static let ordinalSuffixes = ["st", "nd", "rd", "th"]

    /// The decoration for a title, or nil when nothing matches.
    static func match(_ title: String) -> Match? {
        let words = tokens(title)
        guard !words.isEmpty else { return nil }
        if let rule = firstMatch(in: celebrationRules, words) {
            return Match(emoji: rule.emoji, celebration: rule.celebration)
        }
        if words.contains(where: isOrdinalAge) || containsTurnsAge(words) {
            return Match(emoji: "🎂", celebration: .birthday)
        }
        return firstMatch(in: everydayRules, words).map { Match(emoji: $0.emoji, celebration: nil) }
    }

    /// A leading emoji the user typed into the title ("🎾 Tennis"), and the rest of the title.
    static func leadingEmoji(of title: String) -> (emoji: String, rest: String)? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first.isEmojiLike else { return nil }
        let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (String(first), rest)
    }

    /// The sticker a celebration gets in the month view.
    static func sticker(for match: Match?) -> String? {
        guard let match, match.celebration != nil else { return nil }
        return match.emoji
    }

    // MARK: Matching

    private static func firstMatch(in rules: [Rule], _ words: [String]) -> Rule? {
        rules.first { rule in rule.keywords.contains { contains(words, phrase: tokens($0)) } }
    }

    /// Lowercased words. Possessives are dropped ("Mia's" -> "mia") and other
    /// apostrophes removed ("don't" -> "dont").
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "'", with: "")
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    private static func contains(_ words: [String], phrase: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        for start in 0...(words.count - phrase.count) {
            var matched = true
            for (offset, keyword) in phrase.enumerated() where !wordMatches(words[start + offset], keyword) {
                matched = false
                break
            }
            if matched { return true }
        }
        return false
    }

    private static func wordMatches(_ word: String, _ keyword: String) -> Bool {
        word == keyword || word == keyword + "s" || word == keyword + "es"
    }

    private static func isOrdinalAge(_ word: String) -> Bool {
        for suffix in ordinalSuffixes where word.hasSuffix(suffix) {
            let number = word.dropLast(suffix.count)
            if let age = Int(number), (1...120).contains(age) { return true }
        }
        return false
    }

    /// "turns 40"
    private static func containsTurnsAge(_ words: [String]) -> Bool {
        zip(words, words.dropFirst()).contains { $0 == "turns" && Int($1) != nil }
    }
}

private extension Character {
    /// True for pictographic emoji (not digits or # which are technically emoji too).
    var isEmojiLike: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x238C) }
    }
}
