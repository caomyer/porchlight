import Foundation

/// Events and calendars held in memory, written as EventKit would: the simulator's sample
/// calendars and the tests' fake provider use it (docs/design/calendar-add-edit.md). It can
/// also hand back a new shared id for an event after it is saved, as Google and Exchange do.
struct InMemoryCalendarWrites {
    var calendars: [ExternalCalendar]
    var events: [ExternalEvent]
    private var nextItem = 1

    init(calendars: [ExternalCalendar], events: [ExternalEvent]) {
        self.calendars = calendars
        self.events = events
    }

    static func itemId(of occurrenceId: String) -> String { EventForLogic.itemId(ofOccurrence: occurrenceId) }

    /// Saves a new event, or a change for `span`, as EventKit does.
    mutating func save(_ draft: EventDraft, span: EventSpan) throws -> (occurrenceId: String, externalItemId: String?) {
        guard let calendar = calendars.first(where: { $0.id == draft.calendarId }) else { throw CalendarWriteError.gone }
        guard calendar.allowsWrites else { throw CalendarWriteError.readOnly(calendar.title) }
        let item: String
        var external: String?
        if let id = draft.occurrenceId {
            guard let old = events.first(where: { $0.id == id }) else { throw CalendarWriteError.gone }
            item = Self.itemId(of: id)
            external = old.externalItemId
            let series = events.filter { Self.itemId(of: $0.id) == item }
            switch span {
            case .thisEvent where series.count > 1:
                // This occurrence alone becomes its own event, as a detached occurrence does.
                events.removeAll { $0.id == id }
                let detached = "\(item)-\(Int(old.start.timeIntervalSince1970))"
                return insert(draft, item: detached, external: external, repeats: nil)
            case .futureEvents where series.count > 1:
                events.removeAll { Self.itemId(of: $0.id) == item && $0.start >= old.start }
            default:
                events.removeAll { Self.itemId(of: $0.id) == item }
            }
        } else {
            item = "item-\(nextItem)"
            nextItem += 1
            external = "\(item)@local"
        }
        return insert(draft, item: item, external: external, repeats: draft.repeats)
    }

    /// The occurrences of a new or changed event: weekly and every-2-weeks repeats are
    /// written out for eight occurrences, enough for a test's window.
    private mutating func insert(_ draft: EventDraft, item: String, external: String?, repeats: EventRepeat?) -> (occurrenceId: String, externalItemId: String?) {
        var steps: [Int] = [0]
        switch repeats {
        case .daily?: steps = Array(0..<8)
        case .weekly?: steps = (0..<8).map { $0 * 7 }
        case .biweekly?: steps = (0..<8).map { $0 * 14 }
        default: break
        }
        var first = ""
        for step in steps {
            let start = draft.start.addingTimeInterval(TimeInterval(step) * 86_400)
            let id = "\(item)@\(Int(start.timeIntervalSince1970))"
            if first.isEmpty { first = id }
            events.append(ExternalEvent(
                id: id, calendarId: draft.calendarId, title: draft.title,
                location: draft.location.isEmpty ? nil : draft.location, notes: draft.notes.isEmpty ? nil : draft.notes,
                start: start, end: draft.end.addingTimeInterval(TimeInterval(step) * 86_400), isAllDay: draft.isAllDay,
                externalItemId: external, repeats: repeats
            ))
        }
        return (first, external)
    }

    mutating func delete(occurrenceId: String, span: EventSpan) throws {
        guard let old = events.first(where: { $0.id == occurrenceId }) else { throw CalendarWriteError.gone }
        let item = Self.itemId(of: occurrenceId)
        switch span {
        case .thisEvent: events.removeAll { $0.id == occurrenceId }
        case .futureEvents: events.removeAll { Self.itemId(of: $0.id) == item && $0.start >= old.start }
        }
    }

    mutating func makeCalendar(title: String) -> ExternalCalendar {
        let calendar = ExternalCalendar(id: "made-\(calendars.count + 1)", title: title, account: "iCloud", colorHex: 0x5B8C5A, accountKind: "iCloud", allowsWrites: true)
        calendars.append(calendar)
        return calendar
    }

    /// The server hands back another shared id for an event, as Google and Exchange can.
    mutating func changeExternalId(ofItem item: String, to external: String) {
        for index in events.indices where Self.itemId(of: events[index].id) == item {
            events[index].externalItemId = external
        }
    }

    func events(in interval: DateInterval, calendarIds: Set<String>) -> [ExternalEvent] {
        events.filter { calendarIds.contains($0.calendarId) && $0.end > interval.start && $0.start < interval.end }
    }
}
