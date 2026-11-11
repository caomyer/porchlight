import Foundation
import Testing
import UIKit
@testable import Porchlight

/// The square a meal photo shows on the wall: the viewfinder's square for shots, the
/// middle for picks, and wherever it was dragged after reframing.
@Suite("Food: photo framing")
struct PhotoFramingTests {
    let db: AppDatabase
    let photos: FoodPhotoStore
    let people: [Person]
    let journal: Journal

    init() throws {
        db = try AppDatabase.inMemory()
        photos = FoodPhotoStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("framing-tests-\(UUID().uuidString)", isDirectory: true))
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        people = try db.snapshot().people
        journal = try db.ensureFoodJournal(householdId: household.id!)
    }

    private func draft() -> MealDraft {
        MealDraft(day: DayKey(rawValue: "2026-11-07"), slot: "Lunch", title: "Pho", eaterIds: people.compactMap(\.id), eatenAt: Date(timeIntervalSince1970: 1_000))
    }

    /// A wide photo: red on the left third, green in the middle, blue on the right third.
    private func wideImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.green.setFill(); context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
            UIColor.blue.setFill(); context.fill(CGRect(x: 200, y: 0, width: 100, height: 100))
        }
    }

    /// The color at the middle of a saved thumbnail.
    private func centerColor(of file: String) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let image = try #require(UIImage(contentsOfFile: photos.url(for: file).path)?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }

    @Test("A square slides along a photo's long side")
    func cropMath() {
        let wide = CGSize(width: 400, height: 300)
        #expect(PhotoCrop.centeredSquare(in: wide) == PhotoCrop(x: 0.125, y: 0, width: 0.75, height: 1))
        #expect(PhotoCrop.square(in: wide, position: 0) == PhotoCrop(x: 0, y: 0, width: 0.75, height: 1))
        #expect(PhotoCrop.square(in: wide, position: 1).rect(in: wide) == CGRect(x: 100, y: 0, width: 300, height: 300))
        let tall = CGSize(width: 300, height: 400)
        #expect(PhotoCrop.square(in: tall, position: 1).rect(in: tall) == CGRect(x: 0, y: 100, width: 300, height: 300))
        #expect(abs(PhotoCrop.square(in: tall, position: 0.3).position - 0.3) < 0.0001)
        #expect(PhotoCrop.square(in: tall, position: 7) == PhotoCrop.square(in: tall, position: 1), "positions stay inside the photo")
        #expect(PhotoCrop.centeredSquare(in: CGSize(width: 50, height: 50)).position == 0.5)
    }

    @Test("A thumbnail shows the crop, and the middle when there is none")
    func thumbnailsFollowTheCrop() throws {
        let image = wideImage()
        let middle = try photos.save(image)
        #expect(try centerColor(of: middle.thumbnailFile).green > 0.8, "no crop is the middle square")
        let left = try photos.save(image, crop: .square(in: image.size, position: 0))
        #expect(try centerColor(of: left.thumbnailFile).red > 0.8)
        let right = try photos.thumbnail(of: left.photoFile, crop: .square(in: image.size, position: 1))
        #expect(try centerColor(of: right).blue > 0.8, "reframing makes a thumbnail of the new square")
        #expect(FoodPhotoStore.isOwnFile(right))
        let full = try #require(UIImage(contentsOfFile: photos.url(for: left.photoFile).path))
        #expect(full.size.width > full.size.height, "the whole shot is kept")
    }

    @Test("A crop is saved with the meal and changed by an edit, which drops the old thumbnail")
    func cropsPersist() throws {
        let image = wideImage()
        let stored = try photos.save(image, crop: .square(in: image.size, position: 0))
        let entry = try db.addMeal(draft(), journalId: journal.id!, photos: [stored])
        let saved = try #require(try db.foodSnapshot().photos[entry.id!]?.first)
        #expect(saved.crop == stored.crop)

        let crop = PhotoCrop.square(in: image.size, position: 1)
        let thumbnail = try photos.thumbnail(of: saved.photoFile, crop: crop)
        try db.updateMeal(id: entry.id!, draft(), photos: [MealPhotoItem.kept(saved).reframed(crop, thumbnailFile: thumbnail)], files: photos)

        let after = try #require(try db.foodSnapshot().photos[entry.id!]?.first)
        #expect(after.crop == crop)
        #expect(after.thumbnailFile == thumbnail)
        #expect(after.photoFile == saved.photoFile, "reframing keeps the whole shot")
        let files = try FileManager.default.contentsOfDirectory(atPath: photos.directory.path)
        #expect(!files.contains(saved.thumbnailFile), "the old thumbnail goes once saved")
        #expect(files.contains(thumbnail) && files.contains(saved.photoFile))
    }

    @Test("Photos saved before framing show the middle square")
    func existingPhotosKeepTheirLook() throws {
        let stored = try photos.save(wideImage())
        let entry = try db.addMeal(draft(), journalId: journal.id!, photos: [stored])
        #expect(try db.foodSnapshot().photos[entry.id!]?.first?.crop == nil)
    }

    @Test("Only files nobody uses are cleaned up while photos are edited")
    func unusedFiles() {
        let a = FoodPhotoStore.Stored(photoFile: "meal-a.jpg", thumbnailFile: "meal-a-thumb.jpg")
        let b = FoodPhotoStore.Stored(photoFile: "meal-b.jpg", thumbnailFile: "meal-b-thumb.jpg")
        let kept = MealPhoto(id: 1, entryId: 1, photoFile: "meal-k.jpg", thumbnailFile: "meal-k-thumb.jpg", sortOrder: 0, createdAt: .now)
        let crop = PhotoCrop(x: 0, y: 0, width: 0.75, height: 1)

        // A new photo taken out loses both files; a saved one is left to the save.
        #expect(MealPhotoItem.unusedFiles(from: [.added(a), .added(b), .kept(kept)], to: [.added(b)]) == ["meal-a.jpg", "meal-a-thumb.jpg"])
        // Reframing a new photo drops only its old thumbnail.
        let reframed = MealPhotoItem.added(a).reframed(crop, thumbnailFile: "meal-a2-thumb.jpg")
        #expect(MealPhotoItem.unusedFiles(from: [.added(a)], to: [reframed]) == ["meal-a-thumb.jpg"])
        #expect(MealPhotoItem.unusedFiles(from: [.added(a)], to: [.added(a)]).isEmpty)
    }
}
