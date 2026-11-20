import Foundation
import GRDB
import Testing
import UIKit
@testable import Porchlight

/// Food on the phone: the week it shows and its words, who ate and who added a meal, and
/// a snapped meal's rows matching the wall's (one 2048 px image, a square thumbnail, this
/// device's stamp).
@Suite("Phone food")
struct PocketFoodTests {
    private typealias F = CareFixture

    private func person(_ id: Person.ID, _ name: String) -> Person {
        Person(id: id, householdId: 100, name: name, color: .blue, sortOrder: 0, createdAt: F.date(day: 1, 0))
    }

    @Test("The week is the seven days ending today, as on the wall")
    func week() {
        let days = PocketFood.week(endingOn: F.key(16), calendar: F.calendar)
        #expect(days.count == 7)
        #expect(days.first == F.key(10))
        #expect(days.last == F.key(16))
        #expect(PocketFood.weekLine(days, meals: 20, calendar: F.calendar) == "Nov 10 to 16 · 20 meals")
        #expect(PocketFood.weekLine(PocketFood.week(endingOn: F.key(3), calendar: F.calendar), meals: 1, calendar: F.calendar) == "Oct 28 to Nov 3 · 1 meal")
    }

    @Test("Meals and days are named as the polaroids name them")
    func names() {
        #expect(PocketFood.mealName(day: F.key(15), slot: "Dinner", calendar: F.calendar) == "Sunday dinner")
        #expect(PocketFood.shortSlot("Breakfast") == "Bkfst")
        #expect(PocketFood.shortSlot("Snack") == "Snack")
        #expect(PocketFood.dayTitle(F.key(16), today: F.key(16), calendar: F.calendar) == "Today")
        #expect(PocketFood.dayTitle(F.key(15), today: F.key(16), calendar: F.calendar) == "Yesterday")
        #expect(PocketFood.dayTitle(F.key(13), today: F.key(16), calendar: F.calendar) == "Friday")
        #expect(PocketFood.whenLine(slot: "Dinner", eatenAt: F.date(day: 15, 18, 40), calendar: F.calendar) == "Dinner · Sunday 6:40pm")
    }

    @Test("Who ate puts me first as you; a whole household of three is everyone")
    func eaters() {
        let james = person(F.james, "James"), mia = person(F.mia, "Mia"), ava = person(F.ava, "Ava")
        #expect(PocketFood.eaters([james, mia], everyone: false, householdSize: 3, me: F.mia) == "You and James")
        #expect(PocketFood.eaters([mia], everyone: false, householdSize: 3, me: F.james) == "Mia")
        #expect(PocketFood.eaters([james, mia, ava], everyone: true, householdSize: 3, me: F.james) == "Everyone")
        #expect(PocketFood.eaters([james, mia], everyone: true, householdSize: 2, me: F.james) == "You and Mia", "Two people are named")
    }

    @Test("Who added a meal comes from the device stamped on it")
    func addedBy() {
        let everyone = [person(F.james, "James"), person(F.mia, "Mia")]
        func device(_ id: String, _ name: String, role: DeviceRole, owner: Person.ID?) -> Device {
            Device(id: .derived(id), householdId: 100, name: name, role: role, model: "iPhone", personId: owner, userName: nil, createdAt: F.date(day: 1, 0), seenAt: F.date(day: 1, 0))
        }
        let devices = [
            device("mine", "James's iPhone", role: .personal, owner: F.james),
            device("hers", "Mia's iPhone", role: .personal, owner: F.mia),
            device("wall", "Hallway iPad", role: .sharedScreen, owner: nil),
        ]
        #expect(PocketFood.addedBy(.derived("mine"), devices: devices, everyone: everyone, me: F.james) == "added by you")
        #expect(PocketFood.addedBy(.derived("hers"), devices: devices, everyone: everyone, me: F.james) == "added by Mia")
        #expect(PocketFood.addedBy(.derived("wall"), devices: devices, everyone: everyone, me: F.james) == "added on Hallway iPad")
        #expect(PocketFood.addedBy(nil, devices: devices, everyone: everyone, me: F.james) == nil, "From before devices were known")
    }

    @Test("Saving says where the meal went, where it came from and who ate")
    func savedToast() {
        var entry = JournalEntry(journalId: 1, day: F.key(15).rawValue, slot: "Dinner", source: .dineOut, title: "Pho", eatenAt: F.date(day: 15, 18, 40), createdAt: F.date(day: 15, 18, 40))
        let words = PocketFood.savedToast(entry, placeName: "Pho Huynh", eaters: "You and Mia", calendar: F.calendar)
        #expect(words.title == "Saved to Sunday dinner")
        #expect(words.detail == "Pho Huynh · you and Mia")
        entry.source = .home
        #expect(PocketFood.savedToast(entry, placeName: "Pho Huynh", eaters: "Mia", calendar: F.calendar).detail == "Home-cooked · Mia", "A home meal names no restaurant")
    }

    @Test("A meal snapped on the phone stores the wall's rows, stamped with this phone")
    @MainActor
    func snappedRows() async throws {
        let db = try AppDatabase.inMemory(installId: "mias-phone")
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "Mia", color: .coral)])
        try db.markSetupCompleted(householdId: household.id)
        try db.rememberCurrentHousehold()
        _ = try db.ensureFoodJournal(householdId: household.id)
        let mia = try #require(try db.snapshot().people.first).id
        let store = FoodStore(database: db)
        let today = store.today()

        // A 4000 x 3000 shot, as a phone camera takes it.
        let shot = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let photo = try await store.preparePhoto(shot)
        let entry = try store.addMeal(MealDraft(day: today, slot: "Dinner", sources: MealSources(.home), title: "Pho", eaterIds: [mia], eatenAt: .now), photos: [photo])

        let stored = try await db.writer.read { db in
            (
                device: try String.fetchOne(db, sql: "SELECT deviceId FROM journalEntry WHERE id = ?", arguments: [entry.id]),
                image: try Data.fetchOne(db, sql: "SELECT i.image FROM journalEntryPhotoImage i JOIN journalEntryPhoto p ON p.id = i.photoId WHERE p.entryId = ?", arguments: [entry.id]),
                thumbnail: try Data.fetchOne(db, sql: "SELECT t.image FROM journalEntryPhotoThumb t JOIN journalEntryPhoto p ON p.id = t.photoId WHERE p.entryId = ?", arguments: [entry.id])
            )
        }
        #expect(stored.device == db.thisDeviceId(in: household.id).description)
        let image = try #require(stored.image.flatMap(UIImage.init(data:)))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) == MealPhotoImaging.maxPixels, "One size is stored and synced")
        let thumbnail = try #require(stored.thumbnail.flatMap(UIImage.init(data:)))
        #expect(thumbnail.size.width * thumbnail.scale == MealPhotoImaging.thumbnailPixels)
        #expect(thumbnail.size.width == thumbnail.size.height, "The polaroid's square")
    }
}
