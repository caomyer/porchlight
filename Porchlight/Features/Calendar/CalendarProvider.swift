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
}

// MARK: - EventKit

/// Reads the calendars the iPad already knows (iCloud, Google, Exchange,
/// subscribed links...) through the system calendar store. Read-only.
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
                    kind: calendar.type == .birthday ? .birthdays : (calendar.type == .subscription ? .subscribed : .regular)
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
                isAllDay: event.isAllDay
            )
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
