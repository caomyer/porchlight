#if DEBUG
import Foundation
import GRDB

/// Sample companion for `-sampleHousehold`: Yo-Yo, a toy poodle walked twice a day.
/// Dates are relative to now so screenshots always look lived-in.
enum CompanionSamples {
    static func seed(_ database: AppDatabase, household: Household, people: [Person], now: Date = CompanionClock.now()) throws {
        let householdId = household.id
        let ids = people.map(\.id)
        guard !ids.isEmpty else { return }
        let calendar = household.calendar

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
        // `-sampleWater YES`: Yo-Yo's water bowl too, so a page has walks, meals and water.
        let withWater = UserDefaults.standard.bool(forKey: "sampleWater")
        if withWater {
            draft.routines.append(CareRoutineDraft(kind: .water, windows: [.hours("Morning", 7, 11)], stars: 1))
        }
        // `-samplePhoto YES`: a photo of Yo-Yo, drawn in code; `-sampleSticker YES` also the
        // sticker cut from it (docs/design/companion-characters.md).
        let withSticker = UserDefaults.standard.bool(forKey: "sampleSticker")
        if withSticker || UserDefaults.standard.bool(forKey: "samplePhoto") {
            draft.photo = CharacterPlaceholders.photo()
        }
        // The routines started with the 34 days of history below.
        let started = DayKey(now, calendar: calendar).adding(days: -34, calendar: calendar)
        for index in draft.routines.indices { draft.routines[index].startDay = started }
        let companionId = try database.saveCompanion(draft, householdId: householdId, now: now)
        let routines = try database.writer.read { db in
            try CareRoutine.filter(Column("companionId") == companionId).order(Column("sortOrder")).fetchAll(db)
        }
        if withSticker, let sticker = CharacterPlaceholders.sticker() {
            try database.saveSticker(sticker, companionId: companionId, by: nil, now: now)
        }
        // `-sampleCharacter YES`: a character drawn in code, every mood with its movement, shown.
        if UserDefaults.standard.bool(forKey: "sampleCharacter") {
            var stills: [CharacterMood: Data] = [:]
            var strips: [CharacterMood: (Data, Int)] = [:]
            for mood in CharacterMood.allCases {
                stills[mood] = CharacterPlaceholders.sprite(species: .dog, variant: 0, mood: mood)
                if let gif = CharacterPlaceholders.animation(species: .dog, variant: 0, mood: mood),
                   let strip = CharacterAnimationCodec.strip(fromGIF: gif) {
                    strips[mood] = (strip.image, strip.frameCount)
                }
            }
            try database.saveCharacter(stills: stills, strips: strips, companionId: companionId, by: nil, now: now)
            // Drawn with one round of three: two left, as the relay would have said.
            CharacterOffer.remember(roundsLeft: 2, for: companionId)
        }
        guard let walk = routines.first(where: { $0.kind == .walk }) else { return }
        let walkId = walk.id
        let feed = routines.first(where: { $0.kind == .feed })

        var random = SampleRandom(seed: 7)
        let today = DayKey(now, calendar: calendar)
        let notes = ["Squirrel situation handled", "Met the neighbor's golden again", "Refused to walk past the mailbox", nil, nil, nil, nil]
        // 34 days of history: 2 walks a day, a missed evening 25 days ago ends the older streak,
        // and this week a missed morning walk (4 days ago) and yesterday's dinner, to catch up on.
        for back in stride(from: 34, through: 0, by: -1) {
            let day = today.adding(days: -back, calendar: calendar)
            for (slot, window) in walk.windows.enumerated() {
                if back == 25 && slot == 1 || back == 4 && slot == 0 { continue }
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
            if let feed {
                let feedId = feed.id
                for (slot, window) in feed.windows.enumerated() where back > 0 || CareLogic.minuteOfDay(now, calendar: calendar) > window.start + 60 {
                    if back == 1 && slot == 1 { continue }
                    let start = CareLogic.date(day, minute: window.start + 15, calendar: calendar)
                    try database.logCare(routineId: feedId, CareLogDraft(people: [ids[random.next(in: 0...ids.count - 1)]], occurredAt: start), now: now)
                }
            }
            // The bowl is filled every morning but two days ago's.
            if withWater, let water = routines.first(where: { $0.kind == .water }), back != 2 {
                let start = CareLogic.date(day, minute: 8 * 60 + 10, calendar: calendar)
                if start <= now {
                    try database.logCare(routineId: water.id, CareLogDraft(people: [ids[(back + 1) % ids.count]], occurredAt: start), now: now)
                }
            }
        }
        let extra = UserDefaults.standard.integer(forKey: "sampleCompanions")
        if extra >= 2 { try seedCat(database, householdId: householdId, people: ids, calendar: calendar, now: now) }
        if extra >= 3 { try seedPlant(database, householdId: householdId, people: ids, calendar: calendar, now: now) }
        if extra >= 4 { try seedNewcomer(database, householdId: householdId, now: now) }
    }

    /// `-sampleCompanions 4`: Pip the rabbit, added just now, with nothing logged yet.
    private static func seedNewcomer(_ database: AppDatabase, householdId: Household.ID, now: Date) throws {
        var draft = CompanionDraft.new(species: .rabbit)
        draft.name = "Pip"
        draft.about = "Lionhead"
        _ = try database.saveCompanion(draft, householdId: householdId, now: now)
    }

    /// `-sampleCompanions 2`: Miso the cat, fed twice a day, with a week of meals and litter.
    private static func seedCat(_ database: AppDatabase, householdId: Household.ID, people: [Person.ID], calendar: Calendar, now: Date) throws {
        var draft = CompanionDraft.new(species: .cat)
        draft.name = "Miso"
        draft.coat = .silver
        draft.about = "Tabby"
        let today = DayKey(now, calendar: calendar)
        for index in draft.routines.indices { draft.routines[index].startDay = today.adding(days: -7, calendar: calendar) }
        let id = try database.saveCompanion(draft, householdId: householdId, now: now)
        let routines = try database.writer.read { db in
            try CareRoutine.filter(Column("companionId") == id).order(Column("sortOrder")).fetchAll(db)
        }
        for back in stride(from: 7, through: 0, by: -1) {
            let day = today.adding(days: -back, calendar: calendar)
            for (index, routine) in routines.enumerated() {
                for window in routine.windows {
                    let start = CareLogic.date(day, minute: window.start + 20, calendar: calendar)
                    guard start <= now else { continue }
                    let who = people[(back + index) % people.count]
                    try database.logCare(routineId: routine.id, CareLogDraft(people: [who], occurredAt: start), now: now)
                }
            }
        }
    }

    /// `-sampleCompanions 3`: a fiddle fig watered every three days, due today.
    private static func seedPlant(_ database: AppDatabase, householdId: Household.ID, people: [Person.ID], calendar: Calendar, now: Date) throws {
        var draft = CompanionDraft.new(species: .plant)
        draft.name = "Fiddle fig"
        draft.about = "By the window"
        let today = DayKey(now, calendar: calendar)
        for index in draft.routines.indices { draft.routines[index].startDay = today.adding(days: -9, calendar: calendar) }
        let id = try database.saveCompanion(draft, householdId: householdId, now: now)
        guard let water = try database.writer.read({ db in try CareRoutine.filter(Column("companionId") == id).fetchOne(db) }) else { return }
        for back in [9, 6, 3] {
            let day = today.adding(days: -back, calendar: calendar)
            try database.logCare(routineId: water.id, CareLogDraft(people: [people[back % people.count]], occurredAt: CareLogic.date(day, minute: 10 * 60, calendar: calendar)), now: now)
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
