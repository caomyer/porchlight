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
        #expect(try db.foodSnapshot().journal == journal)
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
        let entry = try db.addMeal(draft("  Dan dan noodles ", eaters: [james, james]), journalId: journal.id!, photos: photos)
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

    @Test("A blank title falls back to the meal name")
    func blankTitle() throws {
        let entry = try db.addMeal(draft("   "), journalId: journal.id!, photos: photos)
        #expect(entry.title == "Lunch")
        #expect(entry.emoji == DishIllustration.fallbackEmoji)
    }

    @Test("Invalid meals are rejected")
    func validation() throws {
        #expect(throws: FoodError.unknownSlot("Snack")) { try db.addMeal(draft(slot: "Snack"), journalId: journal.id!, photos: photos) }
        #expect(throws: FoodError.nobodyAte) { try db.addMeal(draft(eaters: []), journalId: journal.id!, photos: photos) }
        #expect(throws: FoodError.nobodyAte) { try db.addMeal(draft(eaters: [9_999]), journalId: journal.id!, photos: photos) }
        #expect(throws: FoodError.titleTooLong(limit: AppDatabase.dishTitleLimit)) {
            try db.addMeal(draft(String(repeating: "a", count: 61)), journalId: journal.id!, photos: photos)
        }
        #expect(throws: FoodError.noJournal) { try db.addMeal(draft(), journalId: 9_999, photos: photos) }
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

        let entry = try db.addMeal(draft(), journalId: journal.id!, photo: stored, photos: photos)
        #expect(try db.referencedPhotoFiles() == [stored.photoFile, stored.thumbnailFile])
        try db.deleteMeal(id: entry.id!, photos: photos)
        #expect(files().isEmpty)
        #expect(try db.foodSnapshot().entries.isEmpty)
    }

    @Test("A failed save removes the photo it brought along")
    func failedSaveCleansUp() throws {
        let stored = try photos.save(image())
        #expect(throws: FoodError.nobodyAte) {
            try db.addMeal(draft(eaters: []), journalId: journal.id!, photo: stored, photos: photos)
        }
        #expect(files().isEmpty)
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

    @Test("A meal and its note page are written together")
    func mealWithPage() throws {
        let ink = PKDrawing(strokes: [FoodPageTests.stroke(from: CGPoint(x: 10, y: 60), to: CGPoint(x: 80, y: 60), width: 1.3)])
        var meal = draft()
        meal.noteLine = 9
        let entry = try db.addMeal(meal, journalId: journal.id!, page: ink.dataRepresentation(), photos: photos)
        #expect(entry.noteLine == 4)
        #expect(try db.foodSnapshot().pages["2026-11-07"] != nil)
    }

    @Test("Deleting a person or the household cascades")
    func cascades() throws {
        let mia = people[1].id!
        let entry = try db.addMeal(draft(), journalId: journal.id!, photos: photos)
        try db.deletePerson(id: mia)
        #expect(try db.foodSnapshot().eaters[entry.id!] == [people[0].id!])
        try db.writer.write { db in _ = try Household.deleteAll(db) }
        let counts = try db.writer.read { db in
            try ["journal", "journalEntry", "journalEntryEater", "journalPage"].map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? -1 }
        }
        #expect(counts == [0, 0, 0, 0])
        #expect(try db.foodSnapshot() == .empty)
    }
}
