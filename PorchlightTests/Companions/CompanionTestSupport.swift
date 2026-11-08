import Foundation
@testable import Porchlight

/// Fixtures for companion tests: a fixed calendar and compact log builders.
enum CareFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        return calendar
    }()

    static let james: Int64 = 1
    static let mia: Int64 = 2
    static let ava: Int64 = 3

    /// Saturday, November 7 2026 at `hour:minute` (or `day` of November).
    static func date(day: Int = 7, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    static func key(_ day: Int) -> DayKey {
        DayKey(date(day: day, 12), calendar: calendar)
    }

    static let walk = CareRoutine(
        id: 10, companionId: 1, kind: .walk, title: "Walk", emoji: "🦮", everyDays: 1,
        windows: [.hours("Morning", 6, 10), .hours("Evening", 17, 20)],
        rotation: [james, mia], trackedFields: CareField.allCases, stars: 2, nudgeAfterMinutes: 60, sortOrder: 0
    )

    static let water = CareRoutine(
        id: 11, companionId: 2, kind: .water, title: "Water", emoji: "💧", everyDays: 3,
        windows: [.anyTime], rotation: [], trackedFields: [], stars: 1, nudgeAfterMinutes: nil, sortOrder: 0
    )

    static func entry(
        _ id: Int64,
        day: Int = 7,
        _ hour: Int,
        _ minute: Int = 0,
        by people: [Int64] = [james],
        minutes: Int? = nil,
        pee: Bool? = nil,
        poo: Bool? = nil,
        vibe: CareVibe? = nil,
        routine: Int64 = 10
    ) -> CareEntry {
        CareEntry(
            log: CareLog(
                id: id, careRoutineId: routine, occurredAt: date(day: day, hour, minute), durationMinutes: minutes,
                pee: pee, poo: poo, vibe: vibe, note: nil, stars: 2, createdAt: date(day: day, hour, minute)
            ),
            people: people
        )
    }

    /// Two on-time walks a day for `days` days ending on November `last`.
    static func fullDays(_ days: ClosedRange<Int>, startId: Int64 = 1000) -> [CareEntry] {
        var id = startId
        var result: [CareEntry] = []
        for day in days {
            result.append(entry(id, day: day, 7, by: [james], minutes: 20))
            result.append(entry(id + 1, day: day, 18, by: [mia], minutes: 30))
            id += 2
        }
        return result
    }
}
