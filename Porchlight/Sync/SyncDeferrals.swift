import Foundation

/// Records iCloud refused that this device kept and sent again instead of losing them
/// (docs/design/sync-icloud.md, "A record sent before its parent"): a child whose parent
/// hadn't reached iCloud yet, and a record iCloud turned down. Counted for Sync details, in
/// words a person can read aloud, and kept across launches.
struct SyncDeferrals: Equatable, Sendable {
    struct Last: Equatable, Sendable {
        var recordType: String
        var at: Date
    }

    /// What the lines say while nothing was kept, as the other details say it.
    static let none = "none"

    var held = 0
    var lastHeld: Last?
    var resent = 0
    var lastResent: Last?

    init() {}

    init(defaults: UserDefaults) {
        held = defaults.integer(forKey: Keys.held)
        resent = defaults.integer(forKey: Keys.resent)
        lastHeld = Self.last(defaults, Keys.lastHeld)
        lastResent = Self.last(defaults, Keys.lastResent)
    }

    mutating func note(recordType: String, waitingForParent: Bool, at date: Date) {
        if waitingForParent {
            held += 1
            lastHeld = Last(recordType: recordType, at: date)
        } else {
            resent += 1
            lastResent = Last(recordType: recordType, at: date)
        }
    }

    func save(to defaults: UserDefaults) {
        defaults.set(held, forKey: Keys.held)
        defaults.set(resent, forKey: Keys.resent)
        for (key, last) in [(Keys.lastHeld, lastHeld), (Keys.lastResent, lastResent)] {
            defaults.set(last.map { [$0.recordType, String($0.at.timeIntervalSince1970)] }, forKey: key)
        }
    }

    /// "Held 3 records until their parent arrived. Last: who walked or fed, Nov 23 at 6:41 PM."
    func heldLine(calendar: Calendar = .current) -> String {
        guard held > 0, let last = lastHeld else { return Self.none }
        return "Held \(Self.records(held)) until their parent arrived. Last: \(Self.words(last.recordType)), \(Self.when(last.at, calendar: calendar))."
    }

    /// "Sent again 1 record iCloud turned down. Last: a walk or meal, Nov 23 at 6:41 PM."
    func resentLine(calendar: Calendar = .current) -> String {
        guard resent > 0, let last = lastResent else { return Self.none }
        return "Sent again \(Self.records(resent)) iCloud turned down. Last: \(Self.words(last.recordType)), \(Self.when(last.at, calendar: calendar))."
    }

    /// What a record is, in words, never a table's name.
    static func words(_ recordType: String) -> String {
        switch recordType {
        case "careLogPerson": "who walked or fed"
        case "careLog": "a walk or meal"
        case "journalEntryEater": "who ate"
        case "journalEntry": "a meal"
        case "choreCompletion": "a chore done"
        case "rewardRedemption": "a reward cashed in"
        case "listItem": "a list item"
        case "mealDish", "mealDishRating": "a dish"
        case "sharedEvent", "sharedCalendar", "calendarFeed": "a calendar"
        case "eventFor": "who an event is for"
        default: "a change"
        }
    }

    private static func records(_ count: Int) -> String { count == 1 ? "1 record" : "\(count) records" }

    private static func when(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day().hour().minute())
    }

    private static func last(_ defaults: UserDefaults, _ key: String) -> Last? {
        guard let parts = defaults.stringArray(forKey: key), parts.count == 2, let seconds = Double(parts[1]) else { return nil }
        return Last(recordType: parts[0], at: Date(timeIntervalSince1970: seconds))
    }

    private enum Keys {
        static let held = "sync.deferrals.held"
        static let resent = "sync.deferrals.resent"
        static let lastHeld = "sync.deferrals.lastHeld"
        static let lastResent = "sync.deferrals.lastResent"
    }
}
