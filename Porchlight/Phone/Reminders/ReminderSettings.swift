import Foundation
import Observation

/// When a care slot reminds this person, if at all.
enum CareReminderTiming: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    /// When its window opens, unless someone already did it.
    case opens
    /// When its window closes, only if nobody did it.
    case missed

    var id: String { rawValue }
}

/// What this person asked to be reminded of on this phone. Device-local, like the
/// device's role: kept in `UserDefaults`, never in the database, never synced.
struct ReminderChoices: Codable, Equatable, Sendable {
    /// Care slots someone looks after, keyed by `ReminderChoices.slotKey`. Nothing is on
    /// until chosen: routines belong to the household, not to one person, so the phone
    /// can't know which are "yours" until you say.
    var care: [String: CareReminderTiming] = [:]
    /// My chores, the evening before they are due.
    var chores = true
    /// "Remind me in an hour": slot-day keys and when to remind again.
    var snoozes: [String: Date] = [:]
    /// "Someone else is on it": slot-day keys not to remind about again.
    var handedOff: Set<String> = []

    static func slotKey(_ routine: CareRoutine.ID, slot: Int) -> String {
        "\(routine)-\(slot)"
    }

    static func dayKey(_ routine: CareRoutine.ID, slot: Int, day: DayKey) -> String {
        "\(slotKey(routine, slot: slot))-\(day.rawValue)"
    }

    func timing(_ routine: CareRoutine.ID, slot: Int) -> CareReminderTiming {
        care[Self.slotKey(routine, slot: slot)] ?? .off
    }

    /// Drops snoozes and hand-offs for days that are over.
    mutating func prune(before day: DayKey) {
        snoozes = snoozes.filter { key, _ in String(key.suffix(10)) >= day.rawValue }
        handedOff = handedOff.filter { String($0.suffix(10)) >= day.rawValue }
    }
}

/// This phone's reminder choices, observed by the Notifications page and the scheduler.
@MainActor
@Observable
final class ReminderSettings {
    static let key = "reminders.choices"

    private(set) var choices: ReminderChoices
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choices = Self.load(defaults)
    }

    static func load(_ defaults: UserDefaults = .standard) -> ReminderChoices {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ReminderChoices.self, from: $0) } ?? ReminderChoices()
    }

    static func save(_ choices: ReminderChoices, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(choices) { defaults.set(data, forKey: key) }
    }

    func update(_ change: (inout ReminderChoices) -> Void) {
        var next = choices
        change(&next)
        choices = next
        Self.save(next, to: defaults)
    }

    /// Picks up changes made outside this object, by a notification action.
    func reload() {
        choices = Self.load(defaults)
    }
}
