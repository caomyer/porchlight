import CloudKit
import Foundation
import GRDB
import Testing
@testable import Porchlight

/// Where a meal came from, one kind or several, and how that stays readable by older builds
/// (docs/design/sync-icloud.md, "A new column, and older builds").
@Suite("Food: a meal from several places")
struct MealSourcesTests {
    // MARK: The kinds

    @Test("Kinds keep the pills' order, each once, and none at all is home-cooked")
    func order() {
        #expect(MealSources([.company, .delivery, .company]).kinds == [.delivery, .company])
        #expect(MealSources([]).kinds == [.home])
        #expect(MealSources(.dineOut).kinds == [.dineOut])
        #expect(MealSources([.company, .home]) == MealSources([.home, .company]))
    }

    @Test("The primary kind is the first with a restaurant, else the first")
    func primary() {
        #expect(MealSources([.delivery, .company]).primary == .delivery)
        #expect(MealSources([.home, .company]).primary == .home)
        #expect(MealSources([.home, .dineOut]).primary == .dineOut, "an older build keeps showing the restaurant")
        #expect(MealSources([.company]).primary == .company)
        #expect(MealSources([.home, .delivery, .dineOut, .company]).primary == .delivery)
    }

    @Test("The others are stored comma-separated in the pills' order, nil when there is one kind")
    func others() {
        #expect(MealSources(.delivery).others == nil)
        #expect(MealSources([.delivery, .company]).others == "company")
        #expect(MealSources([.home, .dineOut, .company]).others == "home,company")
        #expect(MealSources(primary: .dineOut, others: "home,company").kinds == [.home, .dineOut, .company])
    }

    @Test("Stored others read back whatever they hold: unknown kinds, repeats, spaces and nothing")
    func readingStored() {
        #expect(MealSources(primary: .home, others: nil) == MealSources(.home))
        #expect(MealSources(primary: .home, others: "") == MealSources(.home))
        // A later build's kind this build doesn't know is skipped, not an error.
        #expect(MealSources(primary: .delivery, others: "company,picnic").kinds == [.delivery, .company])
        #expect(MealSources(primary: .delivery, others: "delivery,company,company").kinds == [.delivery, .company])
        #expect(MealSources(primary: .delivery, others: ",,company,").kinds == [.delivery, .company])
    }

    @Test("A tap adds a kind or takes it off, but never the last one")
    func toggling() {
        let delivery = MealSources(.delivery)
        #expect(delivery.toggled(.delivery) == delivery, "the last kind stays")
        let both = delivery.toggled(.company)
        #expect(both.kinds == [.delivery, .company])
        #expect(both.toggled(.delivery).kinds == [.company])
        #expect(both.toggled(.company).kinds == [.delivery])
        #expect(MealSources(.company).toggled(.home).kinds == [.home, .company])
    }

    @Test("On a new meal the first tap replaces the home-cooked guess; after that taps add")
    func guess() {
        let guess = MealSources(.home)
        #expect(guess.tapped(.delivery, replacingGuess: true).kinds == [.delivery], "Delivery is one tap")
        #expect(guess.tapped(.home, replacingGuess: true) == guess, "the guess itself stays")
        #expect(guess.tapped(.company, replacingGuess: false).kinds == [.home, .company], "lunch from home, at work")
        #expect(MealSources(.delivery).tapped(.company, replacingGuess: false).kinds == [.delivery, .company])
        #expect(guess.tapHint(.home, guessed: true) == "At least one stays picked")
        #expect(guess.tapHint(.delivery, guessed: true) == "Picks it instead")
        #expect(guess.tapHint(.delivery, guessed: false) == "Adds it")
        #expect(MealSources([.home, .delivery]).tapHint(.home, guessed: false) == "Takes it off")
    }

    @Test("Words and emoji are joined with a dot, in the pills' order")
    func wording() {
        let sources = MealSources([.company, .delivery])
        #expect(sources.label == "Delivery · Company")
        #expect(sources.emoji == "🛵 · 🏢")
        #expect(sources.emojiLabel == "🛵 Delivery · 🏢 Company")
        #expect(MealSources(.home).label == "Home-cooked")
        #expect(MealSources(.home).emoji == MealSource.home.emoji)
    }

    @Test("A restaurant can be named when any kind has one")
    func places() {
        #expect(MealSources([.home, .company]).hasPlace == false)
        #expect(MealSources([.company, .delivery]).hasPlace)
        #expect(MealSources([.delivery, .company]).placePrompt == "From where? Search restaurants")
        #expect(MealSources([.delivery, .dineOut]).placePrompt == "Where? Search restaurants")
    }

    @Test("A meal's sources are its two columns")
    func entryColumns() {
        var entry = JournalEntry(
            journalId: 1, day: "2026-11-07", slot: "Dinner", source: .home, title: "Bento",
            eatenAt: Date(timeIntervalSince1970: 0), createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(entry.sources == MealSources(.home))
        entry.sources = MealSources([.company, .delivery])
        #expect(entry.source == .delivery)
        #expect(entry.otherSources == "company")
        entry.sources = MealSources(.company)
        #expect(entry.source == .company)
        #expect(entry.otherSources == nil)
    }

    // MARK: Stats

    private func entry(_ title: String, _ sources: MealSources) -> JournalEntry {
        var entry = JournalEntry(
            journalId: 1, day: "2026-11-05", slot: "Dinner", source: .home, title: title,
            eatenAt: Date(timeIntervalSince1970: 0), createdAt: Date(timeIntervalSince1970: 0)
        )
        entry.sources = sources
        return entry
    }

    @Test("A meal counts once under each of its kinds, and the total is meals, not kinds")
    func stats() {
        let week = [
            entry("Bento", MealSources([.delivery, .company])),
            entry("Pho", MealSources(.delivery)),
            entry("Tacos", MealSources(.home)),
            entry("Leftovers at the desk", MealSources([.home, .company])),
        ]
        let stats = WeekStats.make(week: week, history: [])
        #expect(stats.total == 4)
        #expect(stats.delivery == 2)
        #expect(stats.company == 2)
        #expect(stats.homeCooked == 2)
        #expect(stats.dineOut == 0)
        #expect(stats.kindCount == 6)
    }

    // MARK: Storage

    @Test("Two kinds and a restaurant are saved and read back, and an edit to one kind clears the rest")
    func roundTrip() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        let journal = try db.ensureFoodJournal(householdId: household.id)
        let people = try db.snapshot().people.map(\.id)
        var meal = MealDraft(day: DayKey(rawValue: "2026-11-07"), slot: "Dinner", sources: MealSources([.company, .delivery]),
                             title: "Bento", eaterIds: people, eatenAt: Date(timeIntervalSince1970: 1_000))
        meal.place = PlaceDraft(name: "Sakura")
        let saved = try db.addMeal(meal, journalId: journal.id)
        #expect(saved.placeId != nil)

        let stored = try #require(try db.foodSnapshot().entries.first)
        #expect(stored.sources.kinds == [.delivery, .company])
        let columns = try db.writer.read { db in
            try Row.fetchOne(db, sql: #"SELECT "source", "otherSources" FROM "journalEntry""#)
        }
        #expect(columns?["source"] == "delivery")
        #expect(columns?["otherSources"] == "company")

        // Company alone names no restaurant, so the meal drops it.
        meal.sources = MealSources(.company)
        let edited = try db.updateMeal(id: saved.id, meal)
        #expect(edited.sources == MealSources(.company))
        #expect(edited.otherSources == nil)
        #expect(edited.placeId == nil)
    }

    @Test("Meals logged before several kinds read as their one kind")
    func migration() throws {
        let queue = try DatabaseQueue(configuration: AppDatabase.configuration)
        try AppDatabase.migrator(files: nil).migrate(queue, upTo: "calendar v2: just me")
        let household = UUID().uuidString.lowercased(), journal = UUID().uuidString.lowercased(), meal = UUID().uuidString.lowercased()
        try queue.write { db in
            #expect(try !db.columns(in: "journalEntry").map(\.name).contains("otherSources"))
            try db.execute(sql: """
                INSERT INTO household (id, name, timeZoneIdentifier, firstWeekday, createdAt) VALUES (?, 'Home', 'UTC', 1, '2026-01-01 00:00:00.000');
                INSERT INTO journal (id, householdId, kind, title, enabled, slots, createdAt) VALUES (?, ?, 'food', 'Food diary', 1, '["Lunch"]', '2026-01-01 00:00:00.000');
                INSERT INTO journalEntry (id, journalId, day, slot, source, title, eatenAt, createdAt)
                VALUES (?, ?, '2026-01-02', 'Lunch', 'delivery', 'Pho', '2026-01-02 12:00:00.000', '2026-01-02 12:00:00.000');
                """, arguments: [household, journal, household, meal, journal])
        }
        let db = try AppDatabase(queue)
        let column = try db.writer.read { db in try db.columns(in: "journalEntry").first { $0.name == "otherSources" } }
        #expect(column?.type == "TEXT")
        #expect(column?.isNotNull == false)
        let entry = try #require(try db.foodSnapshot().entries.first)
        #expect(entry.otherSources == nil)
        #expect(entry.sources == MealSources(.delivery))
    }

    @Test("An older build sees the primary kind, and its edit to that kind keeps the others")
    func olderBuild() throws {
        let db = try AppDatabase.inMemory()
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        let journal = try db.ensureFoodJournal(householdId: household.id)
        let meal = MealDraft(day: DayKey(rawValue: "2026-11-07"), slot: "Dinner", sources: MealSources([.delivery, .company]),
                             title: "Bento", eaterIds: try db.snapshot().people.map(\.id), eatenAt: Date(timeIntervalSince1970: 1_000))
        let saved = try db.addMeal(meal, journalId: journal.id)

        // What an older build decodes: the columns it knows, so "Delivery".
        let source = try db.writer.read { db in
            try String.fetchOne(db, sql: #"SELECT "source" FROM "journalEntry" WHERE "id" = ?"#, arguments: [saved.id])
        }
        #expect(source.flatMap(MealSource.init(rawValue:)) == .delivery)

        // An older build changes the kind it can see; the column it doesn't know stays as iCloud
        // had it, so the meal is the new kind and the others.
        try db.writer.write { db in
            try db.execute(sql: #"UPDATE "journalEntry" SET "source" = 'dineOut' WHERE "id" = ?"#, arguments: [saved.id])
        }
        #expect(try db.foodSnapshot().entries.first?.sources.kinds == [.dineOut, .company])

        // And changing it to one of the others leaves that kind once.
        try db.writer.write { db in
            try db.execute(sql: #"UPDATE "journalEntry" SET "source" = 'company' WHERE "id" = ?"#, arguments: [saved.id])
        }
        #expect(try db.foodSnapshot().entries.first?.sources.kinds == [.company])
    }
}

/// The same through SQLiteData's stand-in for iCloud.
@Suite("Food: several places through iCloud")
@MainActor
struct MealSourcesSyncTests {
    /// The journal entry's last record from iCloud, as the engine keeps it.
    private func serverRecord(_ harness: SyncHarness) throws -> (data: Data, record: CKRecord, coder: NSKeyedUnarchiver) {
        try harness.database.writer.read { db in
            let data = try #require(try Data.fetchOne(db, sql: """
                SELECT _lastKnownServerRecordAllFields FROM sqlitedata_icloud_metadata WHERE recordType = 'journalEntry'
                """))
            let coder = try NSKeyedUnarchiver(forReadingFrom: data)
            coder.requiresSecureCoding = true
            return (data, try #require(CKRecord(coder: coder)), coder)
        }
    }

    @Test("A meal's other kinds go up as their own field, beside the primary kind")
    func fields() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try harness.fill()
        try await engine.syncChanges()
        let (_, record, _) = try serverRecord(harness)
        #expect(record.encryptedValues["source"] as? String == "dineOut")
        #expect(record.encryptedValues["otherSources"] as? String == "company")
        #expect(record.encryptedValues["sqlitedata_icloud_userModificationTime_otherSources"] != nil)
    }

    @Test("A field this build doesn't know survives its edit, as the other kinds survive an older build's")
    func unknownFieldSurvives() async throws {
        let harness = try SyncHarness()
        let controller = await harness.controller()
        let engine = try #require(controller.engine)
        try harness.fill()
        try await engine.syncChanges()

        // As if a later build had written a field this one has no column for.
        let (_, record, coder) = try serverRecord(harness)
        record.encryptedValues["laterField"] = "from a later build"
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encode(with: archiver)
        for key in ["_recordChangeTag", "_modificationDate"] {
            archiver.encode(coder.decodeObject(of: [NSNumber.self, NSDate.self], forKey: key), forKey: key)
        }
        let archived = archiver.encodedData
        try await harness.database.writer.write { db in
            try db.execute(sql: "UPDATE sqlitedata_icloud_metadata SET _lastKnownServerRecordAllFields = ? WHERE recordType = 'journalEntry'",
                           arguments: [archived])
        }

        let entry = try #require(try harness.database.foodSnapshot().entries.first)
        var edit = MealDraft(day: entry.dayKey, slot: entry.slot, sources: MealSources(.home), title: "Sushi at home",
                             eaterIds: try harness.database.snapshot().people.map(\.id), eatenAt: entry.eatenAt)
        edit.emoji = entry.emoji
        _ = try harness.database.updateMeal(id: entry.id, edit)
        try await engine.syncChanges()
        #expect(try harness.unsynced() == [])

        let (_, saved, _) = try serverRecord(harness)
        #expect(saved.encryptedValues["title"] as? String == "Sushi at home")
        #expect(saved.encryptedValues["source"] as? String == "home")
        #expect(saved.encryptedValues["laterField"] as? String == "from a later build")
    }
}
