import Foundation

/// Playful one-line captions for care logs, in the companion's tone.
///
/// Captions are deterministic (the same log always reads the same) and two
/// consecutive logs never share a template.
enum CaptionEngine {
    /// Everything a template may mention.
    struct Context: Sendable {
        var name: String
        var kind: CareKind
        var noun: String
        var who: String
        var together: Bool
        /// This is the walker's n-th log of this routine in the household week.
        var nthThisWeek: Int
        var minutes: Int?
        var vibe: CareVibe?
    }

    struct Template: Sendable {
        var key: String
        var walkOnly = false
        var make: @Sendable (Context) -> String?
    }

    /// Captions for every entry of one routine, keyed by log id.
    /// `entries` may be in any order; the sequence is decided by time.
    static func captions(
        for entries: [CareEntry],
        tone: CompanionTone,
        name: String,
        routine: CareRoutine,
        names: [Int64: String],
        calendar: Calendar
    ) -> [Int64: String] {
        guard tone != .off else { return [:] }
        let counts = weeklyCounts(entries, calendar: calendar)
        var result: [Int64: String] = [:]
        var previousKey: String?
        for entry in entries.sorted(by: { $0.time < $1.time }) {
            let context = Context(
                name: name,
                kind: routine.kind,
                noun: routine.kind.noun(title: routine.title),
                who: whoText(entry.people, names: names),
                together: entry.isTogether,
                nthThisWeek: counts[entry.id] ?? 1,
                minutes: entry.log.durationMinutes,
                vibe: entry.log.vibe
            )
            if let (key, text) = caption(for: context, tone: tone, seed: entry.id, avoiding: previousKey) {
                result[entry.id] = text
                previousKey = key
            }
        }
        return result
    }

    /// For each log, how many logs its lead person has done so far in that household week (1-based).
    static func weeklyCounts(_ entries: [CareEntry], calendar: Calendar) -> [Int64: Int] {
        var running: [String: Int] = [:]
        var result: [Int64: Int] = [:]
        for entry in entries.sorted(by: { $0.time < $1.time }) {
            let week = calendar.dateInterval(of: .weekOfYear, for: entry.time)?.start ?? entry.time
            let key = "\(week.timeIntervalSince1970)-\(entry.people.first ?? -1)"
            running[key, default: 0] += 1
            result[entry.id] = running[key]
        }
        return result
    }

    /// Picks a template by a stable hash of `seed`, skipping `avoiding`.
    static func caption(for context: Context, tone: CompanionTone, seed: Int64, avoiding: String?) -> (String, String)? {
        let candidates = templates(for: tone).compactMap { template -> (String, String)? in
            if template.walkOnly && context.kind != .walk { return nil }
            return template.make(context).map { (template.key, $0) }
        }
        guard !candidates.isEmpty else { return nil }
        // Situational captions (vibe, together, long walks) come first and win when they apply.
        let start = Int(stableHash(seed) % UInt64(candidates.count))
        let preferred = candidates.firstIndex { $0.0.hasPrefix("!") && $0.0 != avoiding }
        if let preferred, stableHash(seed &+ 7) % 3 != 0 { return candidates[preferred] }
        for offset in 0..<candidates.count {
            let pick = candidates[(start + offset) % candidates.count]
            if pick.0 != avoiding { return pick }
        }
        return candidates[start]
    }

    static func whoText(_ people: [Int64], names: [Int64: String]) -> String {
        let list = people.compactMap { names[$0] }
        switch list.count {
        case 0: return "Someone"
        case 1: return list[0]
        case 2: return "\(list[0]) & \(list[1])"
        default: return list.dropLast().joined(separator: ", ") + " & " + list.last!
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    /// Knuth multiplicative hash: stable across launches, unlike `Hasher`.
    static func stableHash(_ value: Int64) -> UInt64 {
        (UInt64(bitPattern: value) &* 2_654_435_761) >> 7
    }

    // MARK: Templates
    // Keys starting with "!" are situational and only apply when their condition holds.

    static func templates(for tone: CompanionTone) -> [Template] {
        switch tone {
        case .off: []
        case .wholesome: wholesome
        case .cheeky: cheeky
        case .dramatic: dramatic
        }
    }

    private static func possessive(_ who: String) -> String {
        who.hasSuffix("s") ? "\(who)'" : "\(who)'s"
    }

    private static let wholesome: [Template] = [
        Template(key: "w.nth") { c in c.together ? nil : "\(possessive(c.who)) \(ordinal(c.nthThisWeek)) \(c.noun) this week. \(c.name) feels very loved." },
        Template(key: "w.home", walkOnly: true) { c in "\(c.name) came home happy. Thank you, \(c.who)." },
        Template(key: "w.lovely") { c in "Another lovely \(c.noun) with \(c.who)." },
        Template(key: "w.cared") { c in "\(c.name) is looking very well cared for." },
        Template(key: "!w.smooth") { c in c.vibe == .smooth ? "Smooth sailing. \(c.name) enjoyed every minute." : nil },
        Template(key: "!w.squirrel") { c in c.vibe == .squirrel ? "\(c.name) spotted a squirrel and kept it together. Mostly." : nil },
        Template(key: "!w.soggy") { c in c.vibe == .soggy ? "A soggy one, but \(c.who) made it cozy." : nil },
        Template(key: "!w.friend") { c in c.vibe == .friend ? "\(c.name) made a new friend today." : nil },
        Template(key: "!w.together") { c in c.together ? "A family \(c.noun). \(c.name) had everyone together." : nil },
        Template(key: "!w.long", walkOnly: true) { c in (c.minutes ?? 0) >= 45 ? "\(c.minutes!) minutes of good sniffs. \(c.name) is happily tuckered out." : nil },
    ]

    private static let cheeky: [Template] = [
        Template(key: "c.nth") { c in c.together || c.kind == .walk ? nil : "\(possessive(c.who)) \(ordinal(c.nthThisWeek)) \(c.noun) this week. \(c.name) has notes about the technique." },
        Template(key: "c.pace", walkOnly: true) { c in c.together ? nil : "\(possessive(c.who)) \(ordinal(c.nthThisWeek)) walk this week. \(c.name) has notes about the pace." },
        Template(key: "c.rate") { c in "\(c.name) rates this \(c.noun) a solid 7/10. Points off for no snacks." },
        Template(key: "c.gracious") { c in "\(c.who) showed up. \(c.name) is choosing to be gracious about the timing." },
        Template(key: "c.service") { c in "\(c.name) acknowledges your service. Barely." },
        Template(key: "!c.squirrel") { c in c.vibe == .squirrel ? "Squirrel situation handled. \(c.name) would like it noted that bravery occurred." : nil },
        Template(key: "!c.soggy") { c in c.vibe == .soggy ? "Soggy \(c.noun). \(c.name) is filing a complaint with the sky." : nil },
        Template(key: "!c.friend") { c in c.vibe == .friend ? "Made a new friend. \(c.name) is now insufferable about it." : nil },
        Template(key: "!c.together") { c in c.together ? "A rare joint \(c.noun). \(c.name) supervised everyone like a tiny boss." : nil },
        Template(key: "!c.short", walkOnly: true) { c in (c.minutes ?? 99) <= 12 ? "A brisk \(c.minutes!) minutes. \(c.name) expected the extended edition." : nil },
        Template(key: "!c.long", walkOnly: true) { c in (c.minutes ?? 0) >= 45 ? "\(c.minutes!) minutes. \(c.name) will be napping this one off." : nil },
    ]

    private static let dramatic: [Template] = [
        Template(key: "d.rescued") { c in "Rescued from certain boredom by \(c.who). \(c.name) will never forget this." },
        Template(key: "d.saga") { c in "The \(ordinal(c.nthThisWeek)) \(c.noun) of the week. The saga continues." },
        Template(key: "d.hope") { c in "\(c.name) had given up all hope. Then \(c.who) appeared." },
        Template(key: "d.saved") { c in "Saved, once again, by \(c.who). Songs will be sung." },
        Template(key: "!d.squirrel") { c in c.vibe == .squirrel ? "The squirrel escaped. The war is not over." : nil },
        Template(key: "!d.soggy") { c in c.vibe == .soggy ? "Rain. Wind. Despair. \(c.name) endured it all." : nil },
        Template(key: "!d.friend") { c in c.vibe == .friend ? "A new alliance has been forged." : nil },
        Template(key: "!d.together") { c in c.together ? "The whole family, united for one glorious \(c.noun)." : nil },
        Template(key: "!d.long", walkOnly: true) { c in (c.minutes ?? 0) >= 45 ? "\(c.minutes!) minutes. An odyssey for the ages." : nil },
    ]
}
