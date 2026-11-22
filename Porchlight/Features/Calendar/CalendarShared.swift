import Foundation
import GRDB

// Showing what the other devices passed on (docs/design/calendar-shared.md, "Showing"),
// beside this device's own events: each event once, quiet calendars as one block a day,
// and how fresh each device's calendars are. Pure, except for the read.

/// What every device passed on, read together.
struct SharedCalendarSnapshot: Equatable, Sendable {
    var thisDeviceId: Device.ID?
    var devices: [Device] = []
    var feeds: [CalendarFeed] = []
    var calendars: [SharedCalendar] = []
    var events: [SharedEvent] = []
    /// Who events are for (docs/design/calendar-add-edit.md, "For whom").
    var eventFors: [EventFor] = []

    static let empty = SharedCalendarSnapshot(thisDeviceId: nil)

    static func fetch(_ db: Database, householdId: Household.ID, thisDeviceId: Device.ID) throws -> SharedCalendarSnapshot {
        let devices = try Device.filter(Column("householdId") == householdId).fetchAll(db)
        let feeds = try CalendarFeed.filter(devices.map(\.id).contains(Column("deviceId"))).fetchAll(db)
        let calendars = try SharedCalendar.filter(feeds.map(\.id).contains(Column("feedId"))).fetchAll(db)
        // This device's own rows are never shown here: it has the events themselves.
        let mine = CalendarFeed.id(deviceId: thisDeviceId)
        let others = calendars.filter { $0.feedId != mine }.map(\.id)
        let events = try SharedEvent.filter(others.contains(Column("sharedCalendarId"))).order(Column("start")).fetchAll(db)
        let eventFors = try EventFor.filter(Column("householdId") == householdId).fetchAll(db)
        return SharedCalendarSnapshot(thisDeviceId: thisDeviceId, devices: devices, feeds: feeds, calendars: calendars, events: events, eventFors: eventFors)
    }

    /// The device a feed came from, and whose it is.
    func device(of feedId: CalendarFeed.ID) -> Device? {
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return nil }
        return devices.first { $0.id == feed.deviceId }
    }
}

enum SharedCalendarView {
    /// The other devices' events, resolved as this device's are: owner, Busy only, emoji.
    static func events(_ snapshot: SharedCalendarSnapshot, people: [Person]) -> [CalendarEvent] {
        let mine = snapshot.thisDeviceId.map { CalendarFeed.id(deviceId: $0) }
        let calendars = Dictionary(snapshot.calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return snapshot.events.compactMap { row in
            guard let calendar = calendars[row.sharedCalendarId], calendar.feedId != mine else { return nil }
            let external = ExternalEvent(
                id: "shared-\(row.id)", calendarId: "shared-\(calendar.id)", title: row.title ?? "",
                location: row.location, notes: row.notes, start: row.start, end: row.end, isAllDay: row.isAllDay
            )
            let kind: ExternalCalendar.Kind = calendar.accountKind == "Birthdays" ? .birthdays : .regular
            var event = CalendarEvent.resolve(external, owner: calendar.owner, isBusy: calendar.choice == .busy, calendarTitle: calendar.title, kind: kind)
            event.matchKey = row.matchKey
            event.isQuiet = calendar.choice == .quiet
            let device = snapshot.device(of: calendar.feedId)
            event.from = from(calendar, device: device, people: people)
            event.fromDevice = device.map { whoseWords($0, people: people) + " " + ($0.model ?? "phone") }
            return event
        }
    }

    /// "From Sam's Google · Mia Soccer"; "From the Hallway iPad's iCloud" for a shared device.
    static func from(_ calendar: SharedCalendar, device: Device?, people: [Person]) -> String {
        let whose = device.map { whoseWords($0, people: people) } ?? "another device's"
        let kind = calendar.accountKind == "On this device" || calendar.accountKind == "Calendar" ? "calendar" : calendar.accountKind
        let title = calendar.title.isEmpty ? "" : " · \(calendar.title)"
        return "From \(whose) \(kind)\(title)"
    }

    /// "Sam's", or "the Hallway iPad's" for a device that is nobody's.
    static func whoseWords(_ device: Device, people: [Person]) -> String {
        if let personId = device.personId, let person = people.first(where: { $0.id == personId }) {
            return "\(person.name)'s"
        }
        return "the \(device.name)'s"
    }

    // MARK: Once each

    /// This device's events and the others', each event once: two match on their match key
    /// and start, or, when either has no key, on title, start and end (Busy only events,
    /// which have no title, match only by key). A match is one event with each owner's face;
    /// this device's own copy is the one kept.
    static func merge(own: [CalendarEvent], others: [CalendarEvent]) -> [CalendarEvent] {
        func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
        var result: [CalendarEvent] = []
        var byKey: [String: Int] = [:]
        var byWords: [String: Int] = [:]
        for event in own + others {
            let key = event.matchKey.map { "\($0)|\(ms(event.start))" }
            let words = event.isBusy ? nil : "\(event.title.lowercased())|\(ms(event.start))|\(ms(event.end))"
            var found: Int?
            if let key, let index = byKey[key] {
                found = index
            } else if let words, let index = byWords[words], event.matchKey == nil || result[index].matchKey == nil {
                found = index
            }
            if let index = found {
                for owner in event.owners where !result[index].owners.contains(owner) {
                    result[index].alsoFor.append(owner)
                }
                // Shown in full if any copy of it is.
                if !event.isQuiet { result[index].isQuiet = false }
                continue
            }
            result.append(event)
            let index = result.count - 1
            if let key { byKey[key] = index }
            if let words { byWords[words] = index }
        }
        return result
    }

    // MARK: Quiet

    /// Quiet events as one block per owner per day, from the first start to the last end,
    /// standing for the events it lists on tap. All-day quiet events are listed in the day's
    /// block and don't stretch it; a day with only those is one all-day block.
    static func quietBlocks(_ events: [CalendarEvent], people: [Person], calendar: Calendar) -> [CalendarEvent] {
        var kept: [CalendarEvent] = []
        var groups: [String: [CalendarEvent]] = [:]
        var order: [String] = []
        for event in events {
            guard event.isQuiet else { kept.append(event); continue }
            let key = "\(event.owner)|\(DayKey(event.start, calendar: calendar).rawValue)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(event)
        }
        for key in order {
            let members = groups[key]!.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
            let timed = members.filter { !$0.isAllDayLike }
            let span = timed.isEmpty ? members : timed
            let first = members[0]
            let start = span.map(\.start).min()!
            let end = span.map(\.end).max()!
            kept.append(CalendarEvent(
                id: "quiet-\(key)", calendarId: first.calendarId, title: QuietWords.title(first.owner, people: people),
                emoji: nil, celebration: nil, location: nil, notes: nil,
                start: start, end: end, isAllDay: timed.isEmpty, owner: first.owner, isBusy: false,
                calendarTitle: first.calendarTitle, isFromSpecialCalendar: false,
                alsoFor: [], isQuiet: true, quietEvents: members, from: first.from
            ))
        }
        return kept.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
    }
}

/// The words of a quiet block: "Alex at work", "Until 5:30 PM · 3 meetings".
enum QuietWords {
    static func title(_ owner: Owner, people: [Person]) -> String {
        guard case let .person(id) = owner, let person = people.first(where: { $0.id == id }) else { return "At work" }
        return "\(person.name) at work"
    }

    static func detail(_ block: CalendarEvent, calendar: Calendar) -> String {
        guard !block.isAllDay else { return count(block) }
        return "Until \(EventText.format(block.end, calendar, "jmm")) · \(count(block))"
    }

    /// "3 meetings"
    static func count(_ block: CalendarEvent) -> String {
        block.quietEvents.count == 1 ? "1 meeting" : "\(block.quietEvents.count) meetings"
    }

    /// The wall grid's line under the name, in the grid's own time style: "until 5:30p" in
    /// the week, "until 5:30 PM · 3 meetings" in the day.
    static func gridUntil(_ block: CalendarEvent, calendar: Calendar, detailed: Bool) -> String {
        guard !block.isAllDay else { return count(block) }
        if detailed { return "until \(EventText.format(block.end, calendar, "jmm")) · \(count(block))" }
        return "until \(EventText.shortTime(block.end, calendar: calendar))"
    }
}

// MARK: - How fresh

/// A device whose calendars haven't been passed on for over a day.
struct StaleCalendarSource: Equatable, Identifiable, Sendable {
    var deviceId: Device.ID
    /// "Sam's calendar, updated Tuesday"
    var words: String
    var id: Device.ID { deviceId }
}

enum CalendarFreshness {
    /// How long before a device's calendars are said to be old.
    static let staleAfter: TimeInterval = 24 * 3600

    /// The other devices whose calendars are over a day old, in the household's words.
    static func stale(_ snapshot: SharedCalendarSnapshot, people: [Person], now: Date, calendar: Calendar) -> [StaleCalendarSource] {
        snapshot.feeds.compactMap { feed in
            guard feed.deviceId != snapshot.thisDeviceId, now.timeIntervalSince(feed.passedOnAt) > staleAfter,
                  let device = snapshot.devices.first(where: { $0.id == feed.deviceId }),
                  snapshot.calendars.contains(where: { $0.feedId == feed.id })
            else { return nil }
            let whose = SharedCalendarView.whoseWords(device, people: people)
            let name = whose.hasPrefix("the ") ? "The" + whose.dropFirst(3) : whose
            return StaleCalendarSource(deviceId: device.id, words: "\(name) calendar, updated \(day(feed.passedOnAt, now: now, calendar: calendar))")
        }
        .sorted { $0.words < $1.words }
    }

    /// "yesterday", "Tuesday" within the week, "Nov 12" before.
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        case 2..<7: return EventText.format(date, calendar, "EEEE")
        default: return EventText.format(date, calendar, "MMM d")
        }
    }

    /// One line per device that passes calendars on, for Sync details: "Sam's iPhone:
    /// 312 events, passed on 2:14 PM today, opened".
    static func detailLines(_ snapshot: SharedCalendarSnapshot, now: Date, calendar: Calendar) -> [(device: String, line: String)] {
        snapshot.feeds.compactMap { feed in
            guard let device = snapshot.devices.first(where: { $0.id == feed.deviceId }) else { return nil }
            let calendars = snapshot.calendars.filter { $0.feedId == feed.id }.count
            let events = feed.eventCount == 1 ? "1 event" : "\(feed.eventCount) events"
            let cals = calendars == 1 ? "1 calendar" : "\(calendars) calendars"
            let when = "\(EventText.format(feed.passedOnAt, calendar, "jmm")) \(day(feed.passedOnAt, now: now, calendar: calendar))"
            let name = device.id == snapshot.thisDeviceId ? "\(device.name) (this one)" : device.name
            return (name, "\(cals), \(events), passed on \(when), \(feed.passedOnBy.words)")
        }
        .sorted { $0.device < $1.device }
    }
}
