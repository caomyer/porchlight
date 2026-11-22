import Foundation

/// One typed line read into an event ("Leo dentist thu 4pm"), on the device, with no network
/// and no model (docs/design/calendar-add-edit.md, "Adding"). Pure: the clock, the household's
/// calendar and its people are handed in.
///
/// It reads, in this order: a person's first name at the start or after "for"; a day (today,
/// tonight, tomorrow, a weekday, "next" a weekday, a date like "Nov 26", "26 Nov" or "11/26");
/// a time ("4pm", "4:30", "16:00", "noon", "lunch", "dinner"), a range ("4-5pm", "4 to 6")
/// or a duration ("for 2 hours"); "all day". What is left is the title.
enum EventLine {
    struct Reading: Equatable {
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        /// Who it is for, from a first name in the line; empty is no one named.
        var forIds: [Person.ID]
        /// Whether the line named a day or a time, so the sheet says what it read.
        var foundDay: Bool
        var foundTime: Bool
    }

    /// Lunch and dinner, as a family means them.
    static let lunch = (hour: 12, minute: 30)
    static let dinner = (hour: 18, minute: 30)
    /// "Tonight" with no time.
    static let tonight = (hour: 19, minute: 0)
    /// An event with a start and no end lasts this long.
    static let defaultLength: TimeInterval = 3600

    /// `device` is the locale the line was typed in, for "3/4": the household's calendar
    /// carries no region, so the order dates are written in is the person's own (`monthFirst`).
    static func read(_ line: String, now: Date, calendar: Calendar, people: [Person], device: Locale = .current) -> Reading {
        var words = tokens(line)
        var used = Set<Int>()
        let today = DayKey(now, calendar: calendar)

        // Who: a first name at the start, or after "for".
        var forIds: [Person.ID] = []
        let names = Dictionary(people.map { (firstName($0), $0.id) }, uniquingKeysWith: { first, _ in first })
        if let first = words.first, let id = names[first.lower] { forIds = [id] }
        for index in words.indices where words[index].lower == "for" && index + 1 < words.count {
            if let id = names[words[index + 1].lower], !forIds.contains(id) {
                forIds.append(id)
                used.formUnion([index, index + 1])
            }
        }

        // The day.
        var day: DayKey?
        var dayWasWeekday = false
        for index in words.indices where !used.contains(index) {
            let word = words[index].lower
            switch word {
            case "today": day = today; used.insert(index)
            case "tonight": day = today; used.insert(index)
            case "tomorrow", "tmrw", "tmr": day = today.adding(days: 1, calendar: calendar); used.insert(index)
            default:
                if let weekday = weekday(word) {
                    let isNext = index > 0 && words[index - 1].lower == "next" && !used.contains(index - 1)
                    let isThis = index > 0 && words[index - 1].lower == "this" && !used.contains(index - 1)
                    day = upcoming(weekday, from: today, calendar: calendar, nextWeek: isNext)
                    dayWasWeekday = !isNext && !isThis
                    used.insert(index)
                    if isNext || isThis { used.insert(index - 1) }
                    if index > 0, words[index - 1].lower == "on" { used.insert(index - 1) }
                } else if let found = date(at: index, in: words, today: today, calendar: calendar, monthFirst: monthFirst(device: device)) {
                    day = found.day
                    used.formUnion(found.indices)
                    if let before = found.indices.min(), before > 0, words[before - 1].lower == "on" { used.insert(before - 1) }
                }
            }
            if day != nil { break }
        }
        let hasTonight = words.contains { $0.lower == "tonight" }

        // All day.
        var isAllDay = false
        for index in words.indices.dropLast() where words[index].lower == "all" && words[index + 1].lower == "day" {
            isAllDay = true
            used.formUnion([index, index + 1])
        }

        // The time, a range or a duration.
        var start: (hour: Int, minute: Int)?
        var end: (hour: Int, minute: Int)?
        var length: TimeInterval?
        if !isAllDay {
            for index in words.indices where !used.contains(index) {
                if let range = timeRange(at: index, in: words, used: used) {
                    start = range.start
                    end = range.end
                    used.formUnion(range.indices)
                    break
                }
                if let time = time(at: index, in: words, used: used, allowBare: true) {
                    start = time.value
                    used.formUnion(time.indices)
                    if time.indices.min().map({ $0 > 0 && ["at", "@"].contains(words[$0 - 1].lower) }) == true {
                        used.insert(time.indices.min()! - 1)
                    }
                    break
                }
            }
            if start == nil, hasTonight { start = tonight }
            if let found = duration(in: words, used: used) {
                length = found.length
                used.formUnion(found.indices)
            }
        }

        // A weekday alone is the next one, today included if its time is still ahead.
        var resolvedDay = day ?? today
        if dayWasWeekday, resolvedDay == today.adding(days: 7, calendar: calendar) {
            let startToday = start.map { at($0, on: today, calendar: calendar) }
            if let startToday, startToday > now { resolvedDay = today }
        }
        // No day named and the time already gone today: tomorrow.
        if day == nil, let start, at(start, on: today, calendar: calendar) <= now {
            resolvedDay = today.adding(days: 1, calendar: calendar)
        }

        let title = titleWords(words, used: used)
        if isAllDay || (start == nil && day != nil) {
            let begin = resolvedDay.startDate(in: calendar)
            return Reading(title: title, start: begin, end: resolvedDay.adding(days: 1, calendar: calendar).startDate(in: calendar),
                           isAllDay: true, forIds: forIds, foundDay: day != nil, foundTime: false)
        }
        guard let start else {
            // Nothing said when: the next whole hour today.
            let next = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
            return Reading(title: title, start: next, end: next.addingTimeInterval(defaultLength), isAllDay: false,
                           forIds: forIds, foundDay: false, foundTime: false)
        }
        let begin = at(start, on: resolvedDay, calendar: calendar)
        var finish = begin.addingTimeInterval(length ?? defaultLength)
        if let end {
            finish = at(end, on: resolvedDay, calendar: calendar)
            if finish <= begin { finish = calendar.date(byAdding: .day, value: 1, to: finish) ?? finish }
        }
        return Reading(title: title, start: begin, end: finish, isAllDay: false, forIds: forIds, foundDay: day != nil, foundTime: true)
    }

    // MARK: Words

    struct Word: Equatable {
        var text: String
        var lower: String
    }

    static func tokens(_ line: String) -> [Word] {
        // "4-5pm" and "4pm-6pm" stay one word, to be read as a range.
        line.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".!?;")) }
            .filter { !$0.isEmpty }
            .map { Word(text: $0, lower: $0.lowercased()) }
    }

    private static func firstName(_ person: Person) -> String {
        person.name.split(separator: " ").first.map { $0.lowercased() } ?? person.name.lowercased()
    }

    private static func titleWords(_ words: [Word], used: Set<Int>) -> String {
        var kept = words.indices.filter { !used.contains($0) }.map { words[$0].text }
        // Joining words left hanging at the end ("dentist at", "party on").
        while let last = kept.last, ["at", "on", "from", "for", "@", "-", "to"].contains(last.lowercased()) { kept.removeLast() }
        let title = kept.joined(separator: " ")
        guard let first = title.first else { return "" }
        return first.uppercased() + title.dropFirst()
    }

    // MARK: Days

    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]

    static func weekday(_ word: String) -> Int? { weekdays[word] }

    /// The next day that is `weekday` after today (a week on if today is that weekday); with
    /// `nextWeek`, the one in the household's following week.
    static func upcoming(_ weekday: Int, from today: DayKey, calendar: Calendar, nextWeek: Bool) -> DayKey {
        if nextWeek {
            let start = PocketCalendarLogic.weekStart(of: today, calendar: calendar).adding(days: 7, calendar: calendar)
            return (0..<7).map { start.adding(days: $0, calendar: calendar) }
                .first { calendar.component(.weekday, from: $0.startDate(in: calendar)) == weekday } ?? start
        }
        let todayWeekday = calendar.component(.weekday, from: today.startDate(in: calendar))
        let ahead = (weekday - todayWeekday + 7) % 7
        return today.adding(days: ahead == 0 ? 7 : ahead, calendar: calendar)
    }

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4, "may": 5,
        "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    /// Whether "3/4" is March 4: as the phone the line is typed on writes a short date. The
    /// household stores no region, and its calendar's locale is no help: made from an
    /// identifier, it is the device's on iOS and the empty root locale on a Mac. Read from the
    /// locale's own short date ("M/d", "dd/MM", "d.M."), so every region, not only the US, is
    /// month first or day first as it writes; before this, Japan was read day first.
    static func monthFirst(device: Locale = .current) -> Bool {
        let locale = device
        let pattern = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d"
        guard let month = pattern.firstIndex(of: "M"), let day = pattern.firstIndex(of: "d") else { return true }
        return month < day
    }

    /// "Nov 26", "26 Nov", "November 26th", "11/26": the next such date, this year or next.
    private static func date(at index: Int, in words: [Word], today: DayKey, calendar: Calendar, monthFirst: Bool) -> (day: DayKey, indices: [Int])? {
        let word = words[index].lower
        func dayNumber(_ text: String) -> Int? {
            let digits = text.replacingOccurrences(of: "st", with: "").replacingOccurrences(of: "nd", with: "")
                .replacingOccurrences(of: "rd", with: "").replacingOccurrences(of: "th", with: "")
            guard let n = Int(digits), (1...31).contains(n) else { return nil }
            return n
        }
        var month: Int?, dayOfMonth: Int?, indices: [Int] = []
        if let m = months[word], index + 1 < words.count, let d = dayNumber(words[index + 1].lower) {
            month = m; dayOfMonth = d; indices = [index, index + 1]
        } else if let d = dayNumber(word), index + 1 < words.count, let m = months[words[index + 1].lower] {
            month = m; dayOfMonth = d; indices = [index, index + 1]
        } else {
            let parts = word.split(separator: "/").compactMap { Int($0) }
            if word.contains("/"), parts.count == 2 || parts.count == 3 {
                let (m, d) = monthFirst ? (parts[0], parts[1]) : (parts[1], parts[0])
                if (1...12).contains(m), (1...31).contains(d) { month = m; dayOfMonth = d; indices = [index] }
            }
        }
        guard let month, let dayOfMonth else { return nil }
        let thisYear = calendar.component(.year, from: today.startDate(in: calendar))
        for year in [thisYear, thisYear + 1] {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)),
                  calendar.component(.day, from: date) == dayOfMonth else { continue }
            let key = DayKey(date, calendar: calendar)
            if key >= today { return (key, indices) }
        }
        return nil
    }

    // MARK: Times

    private static func at(_ time: (hour: Int, minute: Int), on day: DayKey, calendar: Calendar) -> Date {
        let start = day.startDate(in: calendar)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: start) ?? start
    }

    /// One written time: "4pm", "4:30pm", "4 pm", "16:00", "noon", "midnight", "lunch",
    /// "dinner", and, with `allowBare`, an hour alone after "at" or anywhere ("soccer 4"),
    /// morning from 7 to 11 and afternoon from 1 to 6.
    private static func time(at index: Int, in words: [Word], used: Set<Int>, allowBare: Bool, meridiem: String? = nil) -> (value: (hour: Int, minute: Int), indices: [Int])? {
        guard !used.contains(index) else { return nil }
        let word = words[index].lower
        switch word {
        case "noon", "midday": return ((12, 0), [index])
        case "midnight": return ((0, 0), [index])
        default: break
        }
        // A meal is a time only after "at" ("at lunch"); "lunch with Sam" is the title.
        let afterAtWord = index > 0 && words[index - 1].lower == "at"
        if afterAtWord, ["lunch", "lunchtime"].contains(word) { return (lunch, [index]) }
        if afterAtWord, ["dinner", "dinnertime"].contains(word) { return (dinner, [index]) }
        var text = word
        var suffix: String?
        for marker in ["am", "pm", "a", "p"] where text.hasSuffix(marker) && text.count > marker.count {
            let rest = String(text.dropLast(marker.count))
            if rest.last?.isNumber == true { text = rest; suffix = marker.hasPrefix("a") ? "am" : "pm"; break }
        }
        var indices = [index]
        if suffix == nil, index + 1 < words.count, !used.contains(index + 1), ["am", "pm", "a.m", "p.m", "a.m.", "p.m."].contains(words[index + 1].lower) {
            suffix = words[index + 1].lower.hasPrefix("a") ? "am" : "pm"
            indices.append(index + 1)
        }
        let suffixOrShared = suffix ?? meridiem
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let hour = Int(parts[0]), parts[0].count <= 2,
              parts.count == 1 || (parts[1].count == 2 && Int(parts[1]) != nil) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1])! : 0
        guard (0...59).contains(minute) else { return nil }
        if let suffixOrShared {
            guard (1...12).contains(hour) else { return nil }
            let h = hour % 12 + (suffixOrShared == "pm" ? 12 : 0)
            return ((h, minute), indices)
        }
        // 24-hour time: "16:00", "09:30".
        if parts.count == 2, (0...23).contains(hour), hour >= 13 || parts[0].hasPrefix("0") { return ((hour, minute), indices) }
        // A bare hour: only after "at" or with minutes, or when told it is fine.
        let afterAt = index > 0 && ["at", "@"].contains(words[index - 1].lower)
        guard allowBare, afterAt || parts.count == 2 || isLikelyBareHour(index, in: words), (1...12).contains(hour) else { return nil }
        return ((bareHour(hour), minute), indices)
    }

    /// A number that is the line's time ("soccer 4"), not a count ("2 tickets") or a date.
    private static func isLikelyBareHour(_ index: Int, in words: [Word]) -> Bool {
        guard index + 1 < words.count else { return true }
        let next = words[index + 1].lower
        return weekday(next) != nil || ["today", "tonight", "tomorrow", "on", "-", "to"].contains(next)
    }

    /// 7 to 11 is morning, 12 is noon, 1 to 6 is afternoon.
    static func bareHour(_ hour: Int) -> Int {
        switch hour {
        case 7...11: hour
        case 12: 12
        default: hour + 12
        }
    }

    /// "4-5pm", "4pm-6pm", "4 - 6pm", "4 to 6", "from 4 to 6", "4pm to 5:30".
    private static func timeRange(at index: Int, in words: [Word], used: Set<Int>) -> (start: (hour: Int, minute: Int), end: (hour: Int, minute: Int), indices: [Int])? {
        let word = words[index].lower
        // In one word: "4-5pm".
        if word.contains("-") {
            let halves = word.split(separator: "-").map(String.init)
            guard halves.count == 2 else { return nil }
            let pair = [Word(text: halves[0], lower: halves[0]), Word(text: halves[1], lower: halves[1])]
            guard let second = time(at: 1, in: pair, used: [], allowBare: true) else { return nil }
            let shared = halves[1].hasSuffix("am") || halves[1].hasSuffix("a") ? "am" : (halves[1].hasSuffix("pm") || halves[1].hasSuffix("p") ? "pm" : nil)
            guard let first = time(at: 0, in: pair, used: [], allowBare: true, meridiem: shared) else { return nil }
            let end = fixEnd(second.value, after: first.value)
            return (fixStart(first.value, before: end), end, [index])
        }
        // Across words: "4 to 6", "4 - 6pm", "from 4 to 6".
        var at = index
        var indices: [Int] = []
        if word == "from" { indices.append(index); at += 1 }
        guard at + 2 < words.count, ["to", "-", "until", "till", "til"].contains(words[at + 1].lower) else { return nil }
        guard let second = time(at: at + 2, in: words, used: used, allowBare: true) else { return nil }
        let endWord = words[second.indices.last!].lower
        let shared = endWord.hasSuffix("am") ? "am" : (endWord.hasSuffix("pm") ? "pm" : nil)
        guard let first = time(at: at, in: words, used: used, allowBare: true, meridiem: shared) else { return nil }
        indices += first.indices + [at + 1] + second.indices
        let end = fixEnd(second.value, after: first.value)
        return (fixStart(first.value, before: end), end, indices)
    }

    /// "11-1pm": the start's own half of the day when the shared one would put it after the end.
    private static func fixStart(_ start: (hour: Int, minute: Int), before end: (hour: Int, minute: Int)) -> (hour: Int, minute: Int) {
        if start.hour * 60 + start.minute > end.hour * 60 + end.minute, start.hour >= 12 {
            return (start.hour - 12, start.minute)
        }
        return start
    }

    /// "7pm to 10": a bare end before an afternoon start is in the evening too.
    private static func fixEnd(_ end: (hour: Int, minute: Int), after start: (hour: Int, minute: Int)) -> (hour: Int, minute: Int) {
        if end.hour * 60 + end.minute <= start.hour * 60 + start.minute, end.hour < 12, end.hour + 12 > start.hour {
            return (end.hour + 12, end.minute)
        }
        return end
    }

    /// "for 2 hours", "for 30 min", "for 1h", "for an hour", "for 90 minutes".
    private static func duration(in words: [Word], used: Set<Int>) -> (length: TimeInterval, indices: [Int])? {
        for index in words.indices.dropLast() where words[index].lower == "for" && !used.contains(index) {
            var at = index + 1
            var amount: Double?
            var text = words[at].lower
            if ["an", "a"].contains(text) { amount = 1; at += 1; guard at < words.count else { return nil }; text = words[at].lower }
            // "1h", "90m", "2hrs" in one word.
            let digits = text.prefix { $0.isNumber || $0 == "." }
            var unit = String(text.dropFirst(digits.count))
            if !digits.isEmpty { amount = Double(digits) }
            var indices = Array(index...at)
            if unit.isEmpty, at + 1 < words.count, amount != nil, !digits.isEmpty {
                unit = words[at + 1].lower
                indices.append(at + 1)
            } else if amount == 1, digits.isEmpty {
                unit = text
            }
            guard let amount else { continue }
            if ["h", "hr", "hrs", "hour", "hours"].contains(unit) { return (amount * 3600, indices) }
            if ["m", "min", "mins", "minute", "minutes"].contains(unit) { return (amount * 60, indices) }
        }
        return nil
    }
}
