import EventKit
import Foundation

// MARK: - Provider values

/// Whether Porchlight may read the device's calendars.
enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    /// Denied, restricted, or write-only: either way we cannot read.
    case denied
    case granted
}

/// A calendar as the provider sees it.
struct ExternalCalendar: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case regular
        /// Contacts' birthdays.
        case birthdays
        /// A subscribed (ICS link) calendar.
        case subscribed
    }

    var id: String
    var title: String
    /// Where it comes from, e.g. "iCloud · mia@example.com" or "Subscribed link".
    var account: String
    /// 0xRRGGBB
    var colorHex: Int
    var kind: Kind = .regular
    /// A word for where it comes from, never an address: what the household is told.
    var accountKind: String = "On this device"
    /// Whether this device may add to it and change its events.
    var allowsWrites = false
}

/// One occurrence of an event. Recurring events arrive already expanded.
struct ExternalEvent: Equatable, Identifiable, Sendable {
    /// Unique per occurrence.
    var id: String
    var calendarId: String
    var title: String
    var location: String?
    var notes: String?
    var start: Date
    var end: Date
    var isAllDay: Bool
    /// The id iOS means to be the same on every device for the same event, if it has one.
    var externalItemId: String? = nil
    /// How it repeats; nil when it doesn't.
    var repeats: EventRepeat? = nil
}

/// How an event repeats: the simple rules Porchlight offers, and any other kept as it is.
enum EventRepeat: String, CaseIterable, Identifiable, Sendable {
    case daily, weekly, biweekly, monthly, yearly
    /// Made elsewhere, some other way: shown read only, and kept when the event is edited.
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Every day"
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Every month"
        case .yearly: "Every year"
        case .custom: "Custom"
        }
    }

    /// What can be picked.
    static let choices: [EventRepeat] = [.daily, .weekly, .biweekly, .monthly, .yearly]
}

/// An event as it is added or changed.
struct EventDraft: Equatable, Sendable {
    /// The occurrence being changed; nil for a new event.
    var occurrenceId: String?
    var calendarId: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String = ""
    var notes: String = ""
    var repeats: EventRepeat?
}

/// Which of a repeating event's occurrences a change or a delete is for.
enum EventSpan: Sendable {
    case thisEvent, futureEvents
}

/// Why a write didn't happen, in the words the sheet shows.
enum CalendarWriteError: Error, Equatable, LocalizedError {
    case noAccess
    case readOnly(String)
    case gone
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noAccess: "Porchlight can't use the calendars here. Allow it in Settings."
        case let .readOnly(title): "\(title) can't be added to here any more."
        case .gone: "That event isn't in the calendar any more."
        case let .failed(reason): "Couldn't save: \(reason)"
        }
    }
}

/// A source of calendars and events. EventKit is the first; a direct Google
/// provider could be added later without changing the store or the screens.
@MainActor
protocol CalendarProvider: AnyObject {
    var access: CalendarAccess { get }
    /// Asks the user for read access (no-op once decided).
    func requestAccess() async -> CalendarAccess
    func calendars() -> [ExternalCalendar]
    /// Occurrences overlapping `interval` in the given calendars.
    func events(in interval: DateInterval, calendarIds: Set<String>) -> [ExternalEvent]
    /// Called on the main actor whenever calendars or events change.
    var onChange: (@MainActor () -> Void)? { get set }

    // Writes (docs/design/calendar-add-edit.md).

    /// Saves a new event, or a change to `draft.occurrenceId` for `span`; returns the event's
    /// occurrence id ("item@start") and the id it shares across devices.
    func save(_ draft: EventDraft, span: EventSpan) throws -> (occurrenceId: String, externalItemId: String?)
    /// Deletes an occurrence, or it and those after it.
    func delete(occurrenceId: String, span: EventSpan) throws
    /// Makes a new calendar in this device's default account.
    func makeCalendar(title: String) throws -> ExternalCalendar
}

// MARK: - EventKit

/// Reads the calendars the iPad already knows (iCloud, Google, Exchange,
/// subscribed links...) through the system calendar store, and writes the events the
/// household adds or changes (docs/design/calendar-add-edit.md).
@MainActor
final class EventKitProvider: CalendarProvider {
    private let store = EKEventStore()
    var onChange: (@MainActor () -> Void)?
    /// Lives as long as the app, so the observer is never removed.
    private var observer: (any NSObjectProtocol)?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        default: .denied
        }
    }

    func requestAccess() async -> CalendarAccess {
        guard access == .notDetermined else { return access }
        let store = store
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.requestFullAccessToEvents { _, _ in continuation.resume() }
        }
        // Pick up the calendars that just became visible.
        store.reset()
        onChange?()
        return access
    }

    func calendars() -> [ExternalCalendar] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .map { calendar in
                ExternalCalendar(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    account: Self.account(of: calendar),
                    colorHex: calendar.cgColor.map(Self.hex) ?? 0x9AA0A6,
                    kind: calendar.type == .birthday ? .birthdays : (calendar.type == .subscription ? .subscribed : .regular),
                    accountKind: Self.accountKind(of: calendar),
                    allowsWrites: calendar.allowsContentModifications
                )
            }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func events(in interval: DateInterval, calendarIds: Set<String>) -> [ExternalEvent] {
        guard access == .granted, !calendarIds.isEmpty else { return [] }
        let calendars = store.calendars(for: .event).filter { calendarIds.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            guard let start = event.startDate, let end = event.endDate, let calendar = event.calendar else { return nil }
            return ExternalEvent(
                // Occurrences of a recurring event share an identifier; the start makes it unique.
                id: "\(event.calendarItemIdentifier)@\(Int(start.timeIntervalSince1970))",
                calendarId: calendar.calendarIdentifier,
                title: event.title ?? "",
                location: event.location?.nilIfBlank,
                notes: event.notes?.nilIfBlank,
                start: start,
                end: max(end, start),
                isAllDay: event.isAllDay,
                externalItemId: event.calendarItemExternalIdentifier,
                repeats: Self.repeats(event.recurrenceRules?.first)
            )
        }
    }

    // MARK: Writes

    func save(_ draft: EventDraft, span: EventSpan) throws -> (occurrenceId: String, externalItemId: String?) {
        guard access == .granted else { throw CalendarWriteError.noAccess }
        guard let calendar = store.calendar(withIdentifier: draft.calendarId) else { throw CalendarWriteError.gone }
        guard calendar.allowsContentModifications else { throw CalendarWriteError.readOnly(calendar.title) }
        let event: EKEvent
        if let id = draft.occurrenceId {
            guard let found = occurrence(id) else { throw CalendarWriteError.gone }
            event = found
        } else {
            event = EKEvent(eventStore: store)
        }
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        // A repeat made elsewhere some other way is kept as it is.
        if draft.repeats != .custom {
            event.recurrenceRules = draft.repeats.flatMap(Self.rule).map { [$0] }
        }
        do {
            try store.save(event, span: span == .futureEvents ? .futureEvents : .thisEvent, commit: true)
        } catch {
            throw CalendarWriteError.failed(error.localizedDescription)
        }
        let start = event.startDate ?? draft.start
        return ("\(event.calendarItemIdentifier)@\(Int(start.timeIntervalSince1970))", event.calendarItemExternalIdentifier)
    }

    func delete(occurrenceId: String, span: EventSpan) throws {
        guard access == .granted else { throw CalendarWriteError.noAccess }
        guard let event = occurrence(occurrenceId) else { throw CalendarWriteError.gone }
        guard event.calendar?.allowsContentModifications == true else { throw CalendarWriteError.readOnly(event.calendar?.title ?? "") }
        do {
            try store.remove(event, span: span == .futureEvents ? .futureEvents : .thisEvent, commit: true)
        } catch {
            throw CalendarWriteError.failed(error.localizedDescription)
        }
    }

    func makeCalendar(title: String) throws -> ExternalCalendar {
        guard access == .granted else { throw CalendarWriteError.noAccess }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        // iCloud where the device is signed in to it, else the device's default.
        calendar.source = store.sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw CalendarWriteError.failed(error.localizedDescription)
        }
        return calendars().first { $0.id == calendar.calendarIdentifier }
            ?? ExternalCalendar(id: calendar.calendarIdentifier, title: title, account: "", colorHex: 0x9AA0A6, allowsWrites: true)
    }

    /// The occurrence named "item@start".
    private func occurrence(_ id: String) -> EKEvent? {
        let parts = id.split(separator: "@", maxSplits: 1)
        guard let item = parts.first.map(String.init) else { return nil }
        guard let master = store.calendarItem(withIdentifier: item) as? EKEvent else { return nil }
        guard parts.count == 2, let seconds = TimeInterval(parts[1]), master.hasRecurrenceRules else { return master }
        let start = Date(timeIntervalSince1970: seconds)
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-1), end: start.addingTimeInterval(1), calendars: master.calendar.map { [$0] })
        return store.events(matching: predicate).first { $0.calendarItemIdentifier == item } ?? master
    }

    private static func rule(_ repeats: EventRepeat) -> EKRecurrenceRule? {
        switch repeats {
        case .daily: EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .biweekly: EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        case .monthly: EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        case .custom: nil
        }
    }

    /// One of the simple rules, or `.custom` for any other.
    private static func repeats(_ rule: EKRecurrenceRule?) -> EventRepeat? {
        guard let rule else { return nil }
        let simple = rule.daysOfTheWeek == nil && rule.daysOfTheMonth == nil && rule.monthsOfTheYear == nil
            && rule.weeksOfTheYear == nil && rule.daysOfTheYear == nil && rule.setPositions == nil && rule.recurrenceEnd == nil
        guard simple else { return .custom }
        switch (rule.frequency, rule.interval) {
        case (.daily, 1): return .daily
        case (.weekly, 1): return .weekly
        case (.weekly, 2): return .biweekly
        case (.monthly, 1): return .monthly
        case (.yearly, 1): return .yearly
        default: return .custom
        }
    }

    /// Where a calendar comes from, in a word: never the account's address.
    private static func accountKind(of calendar: EKCalendar) -> String {
        switch calendar.type {
        case .birthday: return "Birthdays"
        case .subscription: return "Subscribed"
        case .exchange: return "Exchange"
        case .local: return "On this device"
        default: break
        }
        guard let source = calendar.source else { return "On this device" }
        switch source.sourceType {
        case .local: return "On this device"
        case .exchange: return "Exchange"
        case .calDAV:
            if source.title.localizedCaseInsensitiveContains("icloud") { return "iCloud" }
            if source.title.localizedCaseInsensitiveContains("gmail") || source.title.localizedCaseInsensitiveContains("google") { return "Google" }
            return "Calendar"
        default: return "Calendar"
        }
    }

    private static func account(of calendar: EKCalendar) -> String {
        switch calendar.type {
        case .birthday: return "From Contacts"
        case .subscription: return "Subscribed link"
        default: break
        }
        guard let source = calendar.source else { return "On this iPad" }
        switch source.sourceType {
        case .local: return "On this iPad"
        case .exchange: return "Exchange · \(source.title)"
        case .calDAV:
            // iCloud shows up as CalDAV named "iCloud"; Google as CalDAV named after the address.
            return source.title.localizedCaseInsensitiveContains("icloud") ? "iCloud" : source.title
        default: return source.title
        }
    }

    private static func hex(_ color: CGColor) -> Int {
        guard let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 3 else { return 0x9AA0A6 }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return byte(c[0]) << 16 | byte(c[1]) << 8 | byte(c[2])
    }
}

fileprivate extension String {
    /// nil when the string is empty or only whitespace.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
