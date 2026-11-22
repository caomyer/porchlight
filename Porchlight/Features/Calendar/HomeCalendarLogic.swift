import Foundation
import GRDB

// The household's home calendar as one device finds it among its own
// (docs/design/calendar-add-edit.md, "The home calendar").

enum HomeCalendarLogic {
    enum Resolution: Equatable {
        /// The household hasn't chosen one.
        case notChosen
        /// This device's own copy, which it can write.
        case found(ExternalCalendar)
        /// This device doesn't have it.
        case notHere(HomeCalendar)
        /// It has it, but may not write to it (any more).
        case readOnly(ExternalCalendar)
        /// More than one of its calendars could be it: asked once, then remembered.
        case ambiguous([ExternalCalendar])

        var calendar: ExternalCalendar? {
            if case let .found(calendar) = self { return calendar }
            return nil
        }
    }

    static func resolve(home: HomeCalendar?, calendars: [ExternalCalendar], sources: [CalendarSource]) -> Resolution {
        guard let home else { return .notChosen }
        let candidates = calendars.filter { $0.title == home.title && $0.accountKind == home.accountKind }
        // The one this device was told is it, while it is still a candidate.
        if let chosen = sources.first(where: \.isHome), let calendar = candidates.first(where: { $0.id == chosen.externalId }) {
            return calendar.allowsWrites ? .found(calendar) : .readOnly(calendar)
        }
        let writable = candidates.filter(\.allowsWrites)
        switch writable.count {
        case 1: return .found(writable[0])
        case 0: return candidates.first.map(Resolution.readOnly) ?? .notHere(home)
        default: return .ambiguous(writable)
        }
    }

    /// "Family (Google)"
    static func name(_ home: HomeCalendar) -> String { "\(home.title) (\(home.accountKind))" }
}

extension AppDatabase {
    /// Chooses the household's home calendar from this device's own: the household's half
    /// names it, this device's half remembers which of its calendars it is.
    func chooseHomeCalendar(_ calendar: ExternalCalendar, householdId: Household.ID, now: Date = .now) throws {
        try writer.write { db in
            try HomeCalendar(
                id: HomeCalendar.id(householdId: householdId), householdId: householdId, title: calendar.title,
                accountKind: calendar.accountKind, chosenById: thisDeviceId(in: householdId), chosenAt: now
            ).save(db)
            try db.execute(sql: "UPDATE calendarSource SET isHome = (externalId = ?) WHERE householdId = ?", arguments: [calendar.id, householdId])
            // The household's calendar is everyone's, unless someone here said whose it is.
            try db.execute(
                sql: "UPDATE calendarSource SET ownerId = NULL WHERE householdId = ? AND externalId = ? AND ownerChosen = 0",
                arguments: [householdId, calendar.id]
            )
        }
    }

    /// Remembers which of this device's calendars is the home calendar, when more than one could be.
    func markHomeCalendar(externalId: String, householdId: Household.ID) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE calendarSource SET isHome = (externalId = ?) WHERE householdId = ?", arguments: [externalId, householdId])
        }
    }
}
