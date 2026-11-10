import Foundation
import GRDB
import PencilKit
import Testing
import UIKit
@testable import Porchlight

@Suite("Food: persistence and photo files")
struct FoodDatabaseTests {
    let db: AppDatabase
    let photos: FoodPhotoStore
    let householdId: Int64
    let people: [Person]
    let journal: Journal

    init() throws {
        db = try AppDatabase.inMemory()
        photos = FoodPhotoStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("food-tests-\(UUID().uuidString)", isDirectory: true))
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)])
        householdId = household.id!
        people = try db.snapshot().people
        journal = try db.ensureFoodJournal(householdId: householdId)
    }

    private func draft(_ title: String = "Pho", slot: String = "Lunch", eaters: [Int64]? = nil, day: String = "2026-11-07") -> MealDraft {
        MealDraft(day: DayKey(rawValue: day), slot: slot, title: title, eaterIds: eaters ?? people.compactMap(\.id), eatenAt: Date(timeIntervalSince1970: 1_000))
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: photos.directory.path)) ?? []).sorted()
    }

    @Test("The food journal is created once with the default meals")
    func journalCreation() throws {
        #expect(journal.kind == "food")
        #expect(journal.enabled)
        #expect(journal.slots == ["Breakfast", "Lunch", "Dinner"])
        let again = try db.ensureFoodJournal(householdId: householdId, enabled: false)
        #expect(again.id == journal.id)
        #expect(try db.foodSnapshot().journal?.id == journal.id)
        #expect(try db.foodSnapshot().journal?.slots == journal.slots)
    }

    @Test("Slots are validated, de-duplicated and kept in meal order")
    func slots() throws {
        try db.setJournalSlots(id: journal.id!, ["Snack", "Breakfast", "breakfast", " Dinner "])
        #expect(try db.foodSnapshot().journal?.slots == ["Breakfast", "Dinner", "Snack"])
        #expect(throws: ValidationError.emptyName) { try db.setJournalSlots(id: journal.id!, ["  "]) }
        try db.setJournalEnabled(id: journal.id!, false)
        #expect(try db.foodSnapshot().journal?.enabled == false)
    }

    @Test("A meal is stored with who ate it, an auto emoji and a tint")
    func addMeal() throws {
        let james = people[0].id!
        let entry = try db.addMeal(draft("  Dan dan noodles ", eaters: [james, james]), journalId: journal.id!)
        let snapshot = try db.foodSnapshot()
        #expect(snapshot.entries.count == 1)
        let stored = try #require(snapshot.entries.first)
        #expect(stored.id == entry.id)
        #expect(stored.title == "Dan dan noodles")
        #expect(stored.emoji == "🍜")
        #expect(stored.tint == DishIllustration.suggestTint(for: "Dan dan noodles"))
        #expect(stored.rating == .again)
        #expect(stored.source == .home)
        #expect(stored.dayKey == DayKey(rawValue: "2026-11-07"))
        #expect(snapshot.eaters[entry.id!] == [james])
    }

    @Test("Editing a meal changes its details and eaters, keeping photo and day")
    func updateMeal() throws {
        let james = people[0].id!, mia = people[1].id!
        let stored = try photos.save(image())
        let original = draft("Pho", eaters: [james])
        _ = try db.addMeal(original, journalId: journal.id!, photos: [stored])
        let entry = try #require(try db.foodSnapshot().entries.first)

        var edit = draft("Dan dan noodles", slot: "Dinner", eaters: [mia, james], day: "2026-01-01")
        edit.source = .delivery
        edit.rating = .fine
        let updated = try db.updateMeal(id: entry.id!, edit)

        let snapshot = try db.foodSnapshot()
        let row = try #require(snapshot.entries.first)
        #expect(snapshot.entries.count == 1)
        #expect(row == updated)
        #expect(row.title == "Dan dan noodles")
        #expect(row.emoji == "🍜")
        #expect(row.slot == "Dinner")
        #expect(row.source == .delivery)
        #expect(row.rating == .fine)
        #expect(row.dayKey == entry.dayKey)
        #expect(snapshot.photos[entry.id!]?.map(\.photoFile) == [stored.photoFile], "photos stay unless the edit names them")
        #expect(row.createdAt == entry.createdAt)
        #expect(Set(snapshot.eaters[entry.id!] ?? []) == [james, mia])
        #expect(files() == [stored.photoFile, stored.thumbnailFile].sorted())
    }

    @Test("Editing keeps a hand-picked illustration while the title stays the same")
    func updateKeepsIllustration() throws {
        var original = draft("Grandma's special")
        original.emoji = "🥘"
        original.tint = 3
        let entry = try db.addMeal(original, journalId: journal.id!)
        var edit = draft("Grandma's special")
        edit.rating = .meh
        let updated = try db.updateMeal(id: entry.id!, edit)
        #expect(updated.emoji == "🥘")
        #expect(updated.tint == 3)
        #expect(updated.rating == .meh)
    }

    @Test("Invalid edits are rejected and leave the meal as it was")
    func invalidUpdate() throws {
        _ = try db.addMeal(draft(), journalId: journal.id!)
        let entry = try #require(try db.foodSnapshot().entries.first)
        #expect(throws: FoodError.nobodyAte) { try db.updateMeal(id: entry.id!, draft(eaters: [])) }
        #expect(throws: FoodError.unknownSlot("Snack")) { try db.updateMeal(id: entry.id!, draft(slot: "Snack")) }
        #expect(throws: FoodError.mealNotFound) { try db.updateMeal(id: 9_999, draft()) }
        #expect(try db.foodSnapshot().entries == [entry])
        #expect(try db.foodSnapshot().eaters[entry.id!] == people.compactMap(\.id))
    }

    @Test("A blank title falls back to the meal name")
    func blankTitle() throws {
        let entry = try db.addMeal(draft("   "), journalId: journal.id!)
        #expect(entry.title == "Lunch")
        #expect(entry.emoji == DishIllustration.fallbackEmoji)
    }

    @Test("Invalid meals are rejected")
    func validation() throws {
        #expect(throws: FoodError.unknownSlot("Snack")) { try db.addMeal(draft(slot: "Snack"), journalId: journal.id!) }
        #expect(throws: FoodError.nobodyAte) { try db.addMeal(draft(eaters: []), journalId: journal.id!) }
        #expect(throws: FoodError.nobodyAte) { try db.addMeal(draft(eaters: [9_999]), journalId: journal.id!) }
        #expect(throws: FoodError.titleTooLong(limit: AppDatabase.dishTitleLimit)) {
            try db.addMeal(draft(String(repeating: "a", count: 61)), journalId: journal.id!)
        }
        #expect(throws: FoodError.noJournal) { try db.addMeal(draft(), journalId: 9_999) }
        #expect(try db.foodSnapshot().entries.isEmpty)
    }

    @Test("Ratings outside 1-4 are refused by the schema")
    func ratingCheck() throws {
        #expect(throws: (any Error).self) {
            try db.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO journalEntry (journalId, day, slot, source, title, rating, eatenAt, createdAt)
                    VALUES (?, '2026-11-07', 'Lunch', 'home', 'x', 7, 0, 0)
                    """, arguments: [journal.id])
            }
        }
    }

    @Test("Photos are saved with a thumbnail and deleted with their meal")
    func photoLifecycle() throws {
        let stored = try photos.save(image())
        #expect(files() == [stored.photoFile, stored.thumbnailFile].sorted())
        #expect(stored.photoFile.hasPrefix("meal-") && stored.thumbnailFile.hasSuffix("-thumb.jpg"))
        let thumbnail = try #require(UIImage(contentsOfFile: photos.url(for: stored.thumbnailFile).path))
        #expect(thumbnail.size.width == thumbnail.size.height)

        let entry = try db.addMeal(draft(), journalId: journal.id!, photos: [stored])
        #expect(try db.referencedPhotoFiles() == [stored.photoFile, stored.thumbnailFile])
        try db.deleteMeal(id: entry.id!, files: photos)
        #expect(files().isEmpty)
        #expect(try db.foodSnapshot().entries.isEmpty)
    }

    @Test("A failed save leaves its photos for the next try")
    func failedSaveKeepsPhotos() throws {
        let stored = try photos.save(image())
        #expect(throws: FoodError.nobodyAte) {
            try db.addMeal(draft(eaters: []), journalId: journal.id!, photos: [stored])
        }
        #expect(files() == [stored.photoFile, stored.thumbnailFile].sorted(), "the capture sheet still shows them")
        #expect(try db.foodSnapshot().entries.isEmpty)
        let saved = try db.addMeal(draft(), journalId: journal.id!, photos: [stored])
        #expect(try db.foodSnapshot().photos[saved.id!]?.count == 1)
    }

    @Test("A meal keeps several photos in order, the first as its cover")
    func severalPhotos() throws {
        let shots = try (0..<3).map { _ in try photos.save(image()) }
        let entry = try db.addMeal(draft(), journalId: journal.id!, photos: shots)
        let stored = try #require(try db.foodSnapshot().photos[entry.id!])
        #expect(stored.map(\.photoFile) == shots.map(\.photoFile))
        #expect(stored.map(\.sortOrder) == [0, 1, 2])
        #expect(try db.referencedPhotoFiles().count == 6)
    }

    @Test("Photos can be added to a saved meal, up to the limit")
    func addPhotosLater() throws {
        let entry = try db.addMeal(draft(), journalId: journal.id!)
        let first = try photos.save(image())
        try db.addMealPhotos(entryId: entry.id!, [first])
        let more = try (0..<(AppDatabase.photoLimit - 1)).map { _ in try photos.save(image()) }
        try db.addMealPhotos(entryId: entry.id!, more)
        let all = try #require(try db.foodSnapshot().photos[entry.id!])
        #expect(all.count == AppDatabase.photoLimit)
        #expect(all.first?.photoFile == first.photoFile, "new photos go after the cover")

        let extra = try photos.save(image())
        #expect(throws: FoodError.tooManyPhotos(limit: AppDatabase.photoLimit)) {
            try db.addMealPhotos(entryId: entry.id!, [extra])
        }
        #expect(throws: FoodError.mealNotFound) {
            try db.addMealPhotos(entryId: 999, [extra])
        }
        #expect(throws: FoodError.tooManyPhotos(limit: AppDatabase.photoLimit)) {
            try db.addMeal(draft(), journalId: journal.id!, photos: Array(repeating: extra, count: AppDatabase.photoLimit + 1))
        }
        #expect(try db.foodSnapshot().photos[entry.id!]?.count == AppDatabase.photoLimit)
    }

    @Test("Editing photos re-orders, removes and adds them on save")
    func editPhotos() throws {
        let shots = try (0..<3).map { _ in try photos.save(image()) }
        let entry = try db.addMeal(draft(), journalId: journal.id!, photos: shots)
        let saved = try #require(try db.foodSnapshot().photos[entry.id!])
        let added = try photos.save(image())

        // The third becomes the cover, the first goes, a new one joins at the end.
        let items: [MealPhotoItem] = [.kept(saved[2]), .kept(saved[1]), .added(added)]
        try db.updateMeal(id: entry.id!, draft(), photos: items, files: photos)

        let after = try #require(try db.foodSnapshot().photos[entry.id!])
        #expect(after.map(\.photoFile) == [shots[2].photoFile, shots[1].photoFile, added.photoFile])
        #expect(after.map(\.sortOrder) == [0, 1, 2])
        #expect(!files().contains(shots[0].photoFile), "a removed photo's files go once saved")
        #expect(files().contains(added.photoFile))
    }

    @Test("A rejected photo edit changes nothing and touches no file")
    func invalidPhotoEdit() throws {
        let shot = try photos.save(image())
        let entry = try db.addMeal(draft(), journalId: journal.id!, photos: [shot])
        let other = try db.addMeal(draft("Rice"), journalId: journal.id!, photos: [try photos.save(image())])
        let foreign = try #require(try db.foodSnapshot().photos[other.id!]?.first)
        #expect(throws: FoodError.mealNotFound) {
            try db.updateMeal(id: entry.id!, draft(), photos: [.kept(foreign)], files: photos)
        }
        #expect(throws: FoodError.nobodyAte) {
            try db.updateMeal(id: entry.id!, draft(eaters: []), photos: [], files: photos)
        }
        #expect(try db.foodSnapshot().photos[entry.id!]?.map(\.photoFile) == [shot.photoFile])
        #expect(files().contains(shot.photoFile))
    }

    @Test("Upgrading moves each meal's one photo into its photos, as the cover")
    func photoMigration() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "food v3: notes belong to the day's page, not a meal")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO household (id, name, timeZoneIdentifier, firstWeekday, createdAt) VALUES (1, 'Home', 'UTC', 1, '2026-01-01 00:00:00')")
            try db.execute(sql: "INSERT INTO journal (id, householdId, kind, title, enabled, slots, createdAt) VALUES (1, 1, 'food', 'Food diary', 1, '[\"Lunch\"]', '2026-01-01 00:00:00')")
            for (id, photo) in [(1, "'meal-a.jpg'"), (2, "NULL")] {
                try db.execute(sql: """
                    INSERT INTO journalEntry (id, journalId, day, slot, source, title, photoFile, thumbnailFile, eatenAt, createdAt)
                    VALUES (\(id), 1, '2026-01-02', 'Lunch', 'home', 'Pho', \(photo), \(photo == "NULL" ? "NULL" : "'meal-a-thumb.jpg'"), '2026-01-02 12:00:00', '2026-01-02 12:00:00')
                    """)
            }
        }
        let upgraded = try AppDatabase(queue)
        let snapshot = try upgraded.foodSnapshot()
        #expect(snapshot.entries.count == 2)
        #expect(snapshot.photos[1]?.map(\.photoFile) == ["meal-a.jpg"])
        #expect(snapshot.photos[1]?.first?.thumbnailFile == "meal-a-thumb.jpg")
        #expect(snapshot.photos[2] == nil)
        let columns = try queue.read { db in try db.columns(in: "journalEntry").map(\.name) }
        #expect(!columns.contains("photoFile") && !columns.contains("thumbnailFile"))
    }

    @Test("Sweeping removes only unreferenced meal photos")
    func sweep() throws {
        let kept = try photos.save(image())
        let orphan = try photos.save(image())
        let other = photos.directory.appendingPathComponent("someone-elses.jpg")
        try Data([1]).write(to: other)
        photos.sweep(keeping: [kept.photoFile, kept.thumbnailFile])
        #expect(files() == [kept.photoFile, kept.thumbnailFile, "someone-elses.jpg"].sorted())
        #expect(!files().contains(orphan.photoFile))
        // Never touches paths outside the folder.
        #expect(!FoodPhotoStore.isOwnFile("meal-../../x"))
        #expect(!FoodPhotoStore.isOwnFile("other.jpg"))
    }

    @Test("Pages are upserted per day and removed when blank")
    func pages() throws {
        let day = DayKey(rawValue: "2026-11-07")
        let ink = PKDrawing(strokes: [FoodPageTests.stroke(from: CGPoint(x: 10, y: 40), to: CGPoint(x: 80, y: 40), width: 1.3)])
        try db.savePage(journalId: journal.id!, day: day, drawing: ink.dataRepresentation(), now: Date(timeIntervalSince1970: 10))
        #expect(try db.foodSnapshot().pages[day.rawValue] == Date(timeIntervalSince1970: 10))
        let twice = PKDrawing(strokes: ink.strokes + ink.strokes)
        try db.savePage(journalId: journal.id!, day: day, drawing: twice.dataRepresentation(), now: Date(timeIntervalSince1970: 20))
        let stored = try #require(try db.pageDrawing(journalId: journal.id!, day: day))
        #expect(try PKDrawing(data: stored).strokes.count == 2)
        #expect(try db.foodSnapshot().pages.count == 1)
        try db.savePage(journalId: journal.id!, day: day, drawing: PKDrawing().dataRepresentation())
        #expect(try db.foodSnapshot().pages.isEmpty)
        #expect(try db.pageDrawing(journalId: journal.id!, day: day) == nil)
    }

    @Test("Notes live on the day's page; meals no longer carry a note line")
    func notesBelongToTheDay() throws {
        let columns = try db.writer.read { db in try db.columns(in: "journalEntry").map(\.name) }
        #expect(!columns.contains("noteLine"))
        let day = DayKey(rawValue: "2026-11-07")
        let ink = PKDrawing(strokes: [FoodPageTests.stroke(from: CGPoint(x: 10, y: 60), to: CGPoint(x: 80, y: 60), width: 1.3)])
        try db.addMeal(draft(), journalId: journal.id!)
        try db.savePage(journalId: journal.id!, day: day, drawing: ink.dataRepresentation())
        try db.addMeal(draft("Banh mi"), journalId: journal.id!)
        // A second meal leaves the day's shared page as it was.
        #expect(try db.pageDrawing(journalId: journal.id!, day: day) != nil)
        #expect(try db.foodSnapshot().pages.count == 1)
    }

    @Test("Deleting a person or the household cascades")
    func cascades() throws {
        let mia = people[1].id!
        let entry = try db.addMeal(draft(), journalId: journal.id!)
        try db.deletePerson(id: mia)
        #expect(try db.foodSnapshot().eaters[entry.id!] == [people[0].id!])
        try db.writer.write { db in _ = try Household.deleteAll(db) }
        let counts = try db.writer.read { db in
            try ["journal", "journalEntry", "journalEntryEater", "journalPage"].map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? -1 }
        }
        #expect(counts == [0, 0, 0, 0])
        #expect(try db.foodSnapshot() == .empty)
    }

    @Test("A slot holds several meals, kept in time order")
    func severalMealsInOneSlot() throws {
        var first = draft("Pho")
        first.eatenAt = Date(timeIntervalSince1970: 2_000)
        var second = draft("Banh mi")
        second.eatenAt = Date(timeIntervalSince1970: 1_000)
        try db.addMeal(first, journalId: journal.id!)
        try db.addMeal(second, journalId: journal.id!)
        let lunch = try db.foodSnapshot().entries.filter { $0.slot == "Lunch" }
        #expect(lunch.map(\.title) == ["Banh mi", "Pho"])
    }

    @Test("Eating out names a restaurant with its map details")
    func dineOutPlace() throws {
        var meal = draft("Margherita")
        meal.source = .dineOut
        meal.place = PlaceDraft(name: " Una Pizza ", address: "235 12th St, San Francisco", latitude: 37.77, longitude: -122.41,
                                category: "Restaurant", phone: "+1 415", url: "https://example.com", mapsId: "I123")
        let entry = try db.addMeal(meal, journalId: journal.id!)
        let snapshot = try db.foodSnapshot()
        let place = try #require(snapshot.places.first)
        #expect(snapshot.places.count == 1)
        #expect(entry.placeId == place.id)
        #expect(place.name == "Una Pizza")
        #expect(place.address == "235 12th St, San Francisco")
        #expect(place.latitude == 37.77 && place.longitude == -122.41)
        #expect(place.category == "Restaurant" && place.mapsId == "I123")
        #expect(snapshot.entries.first?.source == .dineOut)
    }

    @Test("The same restaurant is reused, matched by Maps id or by name and address")
    func placesAreReused() throws {
        func meal(_ place: PlaceDraft, source: MealSource = .dineOut) -> MealDraft {
            var meal = draft()
            meal.source = source
            meal.place = place
            return meal
        }
        let a = try db.addMeal(meal(PlaceDraft(name: "Una Pizza", mapsId: "I1")), journalId: journal.id!)
        let b = try db.addMeal(meal(PlaceDraft(name: "Una Pizza Napoletana", address: "235 12th St", mapsId: "I1")), journalId: journal.id!)
        let c = try db.addMeal(meal(PlaceDraft(name: "taqueria"), source: .delivery), journalId: journal.id!)
        let d = try db.addMeal(meal(PlaceDraft(name: "Taqueria", address: nil)), journalId: journal.id!)
        #expect(a.placeId == b.placeId)
        #expect(c.placeId == d.placeId)
        #expect(a.placeId != c.placeId)
        let places = try db.foodSnapshot().places
        #expect(places.count == 2)
        // A known place picks up details it was missing.
        #expect(places.first { $0.mapsId == "I1" }?.address == "235 12th St")
    }

    @Test("Home-cooked meals and blank names have no restaurant; long names are refused")
    func placeValidation() throws {
        var home = draft()
        home.place = PlaceDraft(name: "Una Pizza")
        #expect(try db.addMeal(home, journalId: journal.id!).placeId == nil)
        var blank = draft()
        blank.source = .dineOut
        blank.place = PlaceDraft(name: "   ")
        #expect(try db.addMeal(blank, journalId: journal.id!).placeId == nil)
        var long = draft()
        long.source = .dineOut
        long.place = PlaceDraft(name: String(repeating: "x", count: AppDatabase.placeNameLimit + 1))
        #expect(throws: FoodError.placeNameTooLong(limit: AppDatabase.placeNameLimit)) {
            try db.addMeal(long, journalId: journal.id!)
        }
        #expect(try db.foodSnapshot().places.isEmpty)
    }

    @Test("Editing a meal can add, change or drop its restaurant")
    func editPlace() throws {
        let entry = try db.addMeal(draft(), journalId: journal.id!)
        var edit = draft()
        edit.source = .dineOut
        edit.place = PlaceDraft(name: "Una Pizza")
        let out = try db.updateMeal(id: entry.id!, edit)
        #expect(out.placeId != nil)
        edit.source = .home
        let back = try db.updateMeal(id: entry.id!, edit)
        #expect(back.placeId == nil)
        // The restaurant stays known for next time.
        #expect(try db.foodSnapshot().places.map(\.name) == ["Una Pizza"])
    }

    @Test("Restaurants are listed most recently eaten at first, and go with the household")
    func placeOrderAndCascade() throws {
        func meal(_ name: String, at seconds: TimeInterval) -> MealDraft {
            var meal = draft()
            meal.source = .dineOut
            meal.place = PlaceDraft(name: name)
            meal.eatenAt = Date(timeIntervalSince1970: seconds)
            return meal
        }
        try db.addMeal(meal("Old spot", at: 1_000), journalId: journal.id!)
        try db.addMeal(meal("New spot", at: 5_000), journalId: journal.id!)
        try db.addMeal(meal("Old spot", at: 500), journalId: journal.id!)
        #expect(try db.foodSnapshot().places.map(\.name) == ["New spot", "Old spot"])
        try db.writer.write { db in _ = try Household.deleteAll(db) }
        #expect(try db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM foodPlace") } == 0)
    }
}
