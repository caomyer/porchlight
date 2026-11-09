#if DEBUG
import Foundation
import GRDB

/// Sample companion for `-sampleHousehold`: Yo-Yo, a toy poodle walked twice a day.
/// Dates are relative to now so screenshots always look lived-in.
enum CompanionSamples {
    static func seed(_ database: AppDatabase, household: Household, people: [Person]) throws {
        guard let householdId = household.id else { return }
        let ids = people.compactMap(\.id)
        guard !ids.isEmpty else { return }
        let calendar = household.calendar
        let now = CompanionClock.now()

        // Restart ids on a fresh seed so `-startScreen companion-1` always works.
        try database.writer.write { db in
            if try Companion.fetchCount(db) == 0 {
                try db.execute(sql: "DELETE FROM sqlite_sequence WHERE name IN ('companion', 'careRoutine', 'careLog')")
            }
        }
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        draft.about = "Toy poodle"
        draft.birthDate = calendar.date(byAdding: .month, value: -51, to: now)
        draft.tone = .cheeky
        // The routines started with the 34 days of history below.
        let started = DayKey(now, calendar: calendar).adding(days: -34, calendar: calendar)
        for index in draft.routines.indices { draft.routines[index].startDay = started }
        let companionId = try database.saveCompanion(draft, householdId: householdId, now: now)
        let routines = try database.writer.read { db in
            try CareRoutine.filter(Column("companionId") == companionId).order(Column("sortOrder")).fetchAll(db)
        }
        guard let walk = routines.first(where: { $0.kind == .walk }), let walkId = walk.id else { return }
        let feed = routines.first(where: { $0.kind == .feed })

        var random = SampleRandom(seed: 7)
        let today = DayKey(now, calendar: calendar)
        let notes = ["Squirrel situation handled", "Met the neighbor's golden again", "Refused to walk past the mailbox", nil, nil, nil, nil]
        // 34 days of history: 2 walks a day, a missed evening 25 days ago ends the older streak.
        for back in stride(from: 34, through: 0, by: -1) {
            let day = today.adding(days: -back, calendar: calendar)
            for (slot, window) in walk.windows.enumerated() {
                if back == 25 && slot == 1 { continue }
                let minute = window.start + 25 + random.next(in: 0...(window.end - window.start - 40))
                let start = CareLogic.date(day, minute: minute, calendar: calendar)
                let duration = [12, 18, 22, 25, 27, 31, 35, 40, 52][random.next(in: 0...8)]
                guard start.addingTimeInterval(Double(duration) * 60) <= now else { continue }
                let together = random.next(in: 0...9) == 0
                let walker = ids[(slot + back) % ids.count]
                let vibe = [CareVibe.smooth, .smooth, .smooth, .squirrel, .soggy, .friend][random.next(in: 0...5)]
                try database.logCare(routineId: walkId, CareLogDraft(
                    people: together ? ids : [walker],
                    occurredAt: start,
                    durationMinutes: duration,
                    pee: random.next(in: 0...5) > 0,
                    poo: random.next(in: 0...2) > 0,
                    vibe: vibe,
                    note: back < 3 ? notes[random.next(in: 0...notes.count - 1)] : nil
                ), now: now)
            }
            if let feed, let feedId = feed.id {
                for window in feed.windows where back > 0 || CareLogic.minuteOfDay(now, calendar: calendar) > window.start + 60 {
                    let start = CareLogic.date(day, minute: window.start + 15, calendar: calendar)
                    try database.logCare(routineId: feedId, CareLogDraft(people: [ids[random.next(in: 0...ids.count - 1)]], occurredAt: start), now: now)
                }
            }
        }
    }
}

/// A tiny deterministic generator so the sample data is the same every launch.
private struct SampleRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int((state >> 33) % span)
    }
}
#endif
