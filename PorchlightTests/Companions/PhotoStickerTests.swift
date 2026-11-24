import CoreGraphics
import Foundation
import ImageIO
import GRDB
import Testing
import UIKit
@testable import Porchlight

/// The photo sticker, made on the device (docs/design/companion-characters.md, "The photo
/// sticker"): finding the subject in masks drawn in code, drawing the sticker from a photo
/// drawn in code, the edge cases (no subject, several, cut by the frame, a huge photo, a
/// device that can't or is too slow), the steps of making one, and where it is kept.
// Serialized: `browsingCutsNothing` reads the count of cut-outs, and only this suite makes any.
@Suite("The photo sticker", .serialized)
struct PhotoStickerTests {
    // MARK: Finding the subject

    @Test("A subject in the middle has its box, covers its share and doesn't touch the edge")
    func middle() throws {
        let grid = try #require(MaskGrid.drawn("middle", width: 100, height: 100))
        let box = try #require(grid.bounds())
        #expect(abs(box.midX - 50) <= 1 && abs(box.midY - 50) <= 1)
        #expect(abs(box.width - 60) <= 2)
        #expect(abs(grid.coverage() - .pi * 0.09) < 0.02)
        #expect(!grid.touchesEdge())
    }

    @Test("A subject running off the bottom is cut by the edge; a stray pixel there is not")
    func edge() throws {
        #expect(try #require(MaskGrid.drawn("edge", width: 100, height: 100)).touchesEdge())
        var stray = try #require(MaskGrid.drawn("middle", width: 100, height: 100))
        stray.values[99 * 100 + 50] = 1
        #expect(!stray.touchesEdge(), "one pixel on the border is noise, not a cut")
    }

    @Test("Of several subjects the largest is used and the others are counted; tiny ones aren't subjects")
    func several() throws {
        let two = try #require(MaskGrid.drawn("two", width: 100, height: 100))
        // The two discs apart, as Vision gives each instance its own mask.
        var left = two, right = two
        for y in 0..<100 {
            for x in 0..<100 {
                if x >= 50 { left.values[y * 100 + x] = 0 } else { right.values[y * 100 + x] = 0 }
            }
        }
        let pick = try #require(MaskGrid.pick([right, left]))
        #expect(pick.index == 1, "the larger disc, on the left")
        #expect(pick.others == 1)
        var speck = MaskGrid(width: 100, height: 100, values: Array(repeating: 0, count: 10_000))
        speck.values[5050] = 1
        #expect(MaskGrid.pick([speck]) == nil, "a speck is no subject")
        #expect(MaskGrid.pick([try #require(MaskGrid.drawn("none", width: 10, height: 10))]) == nil)
        let (largest, small) = (try #require(MaskGrid.drawn("middle", width: 100, height: 100)), speck)
        #expect(MaskGrid.pick([largest, small])?.others == 0, "a far smaller one isn't counted as a second subject")
    }

    // MARK: Drawing it

    /// A photo drawn in code: a warm subject-coloured field, 400 by 300.
    private static func photo(width: Int = 400, height: Int = 300) -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { context in
            UIColor(red: 0.78, green: 0.55, blue: 0.35, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    private static func finder(_ shape: String) -> SubjectFinder { SubjectFinder.drawn(shape) }

    /// RGBA at a point, top-left origin, from a PNG.
    private static func pixel(_ png: Data, _ x: Int, _ y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let image = try #require(UIImage(data: png)?.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (bytes[0], bytes[1], bytes[2], bytes[3])
    }

    @Test("The sticker is a clear square with the subject in the middle, outlined in white")
    func sticker() async throws {
        let result = try await PhotoSticker.make(from: Self.photo(), finder: Self.finder("middle"))
        let image = try #require(UIImage(data: result.sticker)?.cgImage)
        #expect(image.width == PhotoSticker.side && image.height == PhotoSticker.side)
        #expect(try Self.pixel(result.sticker, 4, 4).a == 0, "clear in the corner")
        let middle = try Self.pixel(result.sticker, 256, 256)
        #expect(middle.a == 255 && middle.r > middle.b, "the subject, in its own colour, in the middle")
        // The subject fills 80% of the square across: its left edge is near 51 pixels in, at
        // the middle row, and the white outline just outside it.
        let outline = try Self.pixel(result.sticker, 46, 256)
        #expect(outline.a > 200 && outline.r > 240 && outline.g > 240 && outline.b > 240, "white just outside the subject: \(outline)")
        #expect(result.notes.isEmpty)
        // The plain cut-out, for drawing a character from: no outline, at most 1024 on a side.
        let cutout = try #require(UIImage(data: result.cutout)?.cgImage)
        #expect(max(cutout.width, cutout.height) <= PhotoSticker.cutoutSide)
        #expect(try Self.pixel(result.cutout, 1, 1).a == 0, "clear outside the round subject")
    }

    @Test("Several subjects and a subject cut by the frame are made, with a note each")
    func notes() async throws {
        #expect(try await PhotoSticker.make(from: Self.photo(), finder: Self.finder("two")).notes == [.severalSubjects])
        #expect(try await PhotoSticker.make(from: Self.photo(), finder: Self.finder("edge")).notes == [.cutByEdge])
    }

    @Test("No subject, an unreadable photo, a device that can't, and one too slow each say so")
    func failures() async throws {
        await #expect(throws: PhotoSticker.Failure.noSubject) { try await PhotoSticker.make(from: Self.photo(), finder: Self.finder("none")) }
        await #expect(throws: PhotoSticker.Failure.unreadable) { try await PhotoSticker.make(from: Data("not a photo".utf8), finder: Self.finder("middle")) }
        await #expect(throws: PhotoSticker.Failure.unavailable) { try await PhotoSticker.make(from: Self.photo(), finder: Self.finder("unavailable")) }
        await #expect(throws: PhotoSticker.Failure.unavailable) {
            try await PhotoSticker.make(from: Self.photo(), finder: Self.finder("slow"), timeout: .milliseconds(200))
        }
    }

    @Test("A huge photo is read at no more than 2048 on its long side, upright")
    func huge() throws {
        let data = Self.photo(width: 6000, height: 4000)
        let image = try #require(PhotoSticker.image(from: data))
        #expect(max(image.width, image.height) == 2048)
        #expect(image.width > image.height)
    }

    @Test("Vision on this simulator either finds a drawn subject or says it can't: never a crash or a hang")
    func vision() async throws {
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
            UIColor(red: 0.45, green: 0.3, blue: 0.2, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 150, y: 150, width: 300, height: 300))
        }
        do {
            let result = try await PhotoSticker.make(from: try #require(picture.pngData()), finder: .vision, timeout: .seconds(20))
            #expect(!result.sticker.isEmpty)
        } catch let failure as PhotoSticker.Failure {
            #expect([.unavailable, .noSubject].contains(failure), "\(failure)")
        }
    }

    // MARK: The steps

    @MainActor
    @Test("Making one: cut from the saved photo, used, saved with no photo of its own")
    func steps() async throws {
        let result = PhotoSticker.Result(sticker: Data("sticker".utf8), cutout: Data("cutout".utf8), notes: [])
        let making = StickerMaking(photo: Data("photo".utf8)) { _ in result }
        #expect(making.step == .cutting)
        await making.start()
        #expect(making.step == .ready(result))
        var saved: (Data, Data?)?
        making.use { sticker, photo in saved = (sticker, photo); return nil }
        #expect(making.step == .done)
        #expect(saved?.0 == result.sticker && saved?.1 == nil, "the saved photo stays")
    }

    @MainActor
    @Test("No photo asks for one; a photo picked here is saved with its sticker; a failed save keeps the sheet")
    func pickedPhoto() async throws {
        let result = PhotoSticker.Result(sticker: Data("sticker".utf8), cutout: Data(), notes: [])
        let making = StickerMaking(photo: nil) { _ in result }
        #expect(making.step == .needsPhoto)
        await making.start()
        #expect(making.step == .needsPhoto)
        await making.start(with: Data("new".utf8))
        making.use { _, _ in "The household is gone." }
        #expect(making.saveError == "The household is gone.")
        #expect(making.step == .ready(result), "the sheet stays, with the reason")
        var photo: Data?
        making.use { _, picked in photo = picked; return nil }
        #expect(photo == Data("new".utf8))
    }

    @MainActor
    @Test("A cut that fails says why, and a slow one overtaken by another photo is dropped")
    func failedAndOvertaken() async throws {
        let failing = StickerMaking(photo: Data("photo".utf8)) { _ in throw PhotoSticker.Failure.noSubject }
        await failing.start()
        #expect(failing.step == .failed(.noSubject))

        let quick = PhotoSticker.Result(sticker: Data("quick".utf8), cutout: Data(), notes: [])
        let making = StickerMaking(photo: Data("slow".utf8)) { photo in
            if photo == Data("slow".utf8) { try await Task.sleep(for: .milliseconds(300)) }
            return PhotoSticker.Result(sticker: photo == Data("slow".utf8) ? Data("late".utf8) : quick.sticker, cutout: Data(), notes: [])
        }
        async let slow: Void = making.start()
        try await Task.sleep(for: .milliseconds(50))
        await making.start(with: Data("quick".utf8))
        await slow
        #expect(making.step == .ready(quick), "the late cut of the first photo doesn't replace the second")
    }

    // MARK: Where it is kept, and which face shows

    private struct Home {
        let db: AppDatabase
        let householdId: Household.ID
        let id: Companion.ID

        func look() throws -> CharacterLook? {
            try db.writer.read { try AppDatabase.characterLooks($0, householdId: householdId) }[id]
        }

        func images(_ source: FaceSource) throws -> Int {
            try db.writer.read { try CharacterImage.filter(Column("source") == source.rawValue).fetchCount($0) }
        }

        /// A character drawn in code: a still for each mood and an animation for doing fine.
        func drawCharacter() throws {
            try db.writer.write { db in
                try AppDatabase.replace(.character, of: id, with: CharacterMood.allCases.map {
                    CharacterImage(companionId: id, source: .character, mood: $0, image: Data("still \($0)".utf8))
                } + [CharacterImage(companionId: id, source: .character, mood: .fine, kind: .frames, frameCount: 9, image: Data("frames".utf8))], db: db)
            }
        }
    }

    private func home(photo: Bool = true) throws -> Home {
        let db = try AppDatabase.inMemory(installId: "sticker")
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue)])
        var yoyo = CompanionDraft.new(species: .dog)
        yoyo.name = "Yo-Yo"
        yoyo.photo = photo ? Data("photo".utf8) : nil
        return Home(db: db, householdId: household.id, id: try db.saveCompanion(yoyo, householdId: household.id))
    }

    @Test("A sticker is saved and shown; a new one replaces it, with the photo it came from; it goes with the companion")
    func storage() throws {
        let home = try home()
        #expect(try home.look() == nil, "nothing beyond the photo yet")
        try home.db.saveSticker(Data("one".utf8), companionId: home.id, by: nil)
        let first = try #require(try home.look())
        #expect(first.shown == .sticker && first.sticker?.byteCount == 3)
        #expect(!first.hasCharacter)

        try home.db.saveSticker(Data("second".utf8), photo: Data("new photo".utf8), companionId: home.id, by: nil)
        #expect(try home.look()?.sticker?.byteCount == 6, "a new sticker replaces the old one")
        #expect(try home.db.companionPhoto(id: home.id) == Data("new photo".utf8), "with the photo it was cut from")
        #expect(try home.images(.sticker) == 1)

        try home.db.deleteCompanion(id: home.id)
        #expect(try home.db.writer.read { try CompanionCharacter.fetchCount($0) + CharacterImage.fetchCount($0) } == 0)
        #expect(throws: CharacterError.unknownCompanion) { try home.db.saveSticker(Data("x".utf8), companionId: home.id, by: nil) }
    }

    @Test("Switching between character, sticker, photo and drawn face deletes and redraws nothing; a face that isn't there can't be chosen")
    func switching() throws {
        let home = try home()
        try home.drawCharacter()
        try home.db.saveSticker(Data("sticker".utf8), companionId: home.id, by: nil)
        let before = try home.db.writer.read { try CharacterImage.fetchAll($0).map(\.image) }
        for face in [CompanionFaceChoice.character, .photo, .drawn, .sticker, .character] {
            try home.db.chooseFace(face, companionId: home.id, by: nil)
            #expect(try home.look()?.shown == (face == .photo ? nil : face), "\(face) shows")
        }
        #expect(try home.db.writer.read { try CharacterImage.fetchAll($0).map(\.image) } == before, "nothing was drawn again or deleted")
        let character = try #require(try home.look())
        #expect(character.still(.asleep)?.byteCount == "still asleep".utf8.count)
        #expect(character.animation(.fine)?.frameCount == 9)
        #expect(character.animation(.waiting) == nil)

        let bare = try self.home(photo: false)
        #expect(throws: CharacterError.faceNotAvailable) { try bare.db.chooseFace(.photo, companionId: bare.id, by: nil) }
        #expect(throws: CharacterError.faceNotAvailable) { try bare.db.chooseFace(.character, companionId: bare.id, by: nil) }
        try bare.db.chooseFace(.drawn, companionId: bare.id, by: nil)
    }

    @Test("Removing the character deletes its pictures for everyone and shows the sticker, else the photo; the sticker stays")
    func removing() throws {
        let home = try home()
        try home.drawCharacter()
        try home.db.saveSticker(Data("sticker".utf8), companionId: home.id, by: nil)
        try home.db.chooseFace(.character, companionId: home.id, by: nil)
        try home.db.removeCharacter(companionId: home.id, by: nil)
        #expect(try home.images(.character) == 0)
        #expect(try home.images(.sticker) == 1, "the sticker stays")
        #expect(try home.look()?.shown == .sticker, "and shows")

        let plain = try self.home()
        try plain.drawCharacter()
        try plain.db.chooseFace(.character, companionId: plain.id, by: nil)
        try plain.db.removeCharacter(companionId: plain.id, by: nil)
        #expect(try plain.look()?.face == .photo, "with no sticker, the photo")

        let notShown = try self.home()
        try notShown.drawCharacter()
        try notShown.db.chooseFace(.drawn, companionId: notShown.id, by: nil)
        try notShown.db.removeCharacter(companionId: notShown.id, by: nil)
        #expect(try notShown.look()?.face == .drawn, "a face chosen over it stays chosen")
    }

    @Test("A character whose still hasn't arrived by sync yet isn't shown; a face, set or mood from a newer build is left alone")
    func partial() async throws {
        let home = try home()
        try await home.db.writer.write { db in
            try CompanionCharacter(companionId: home.id, face: .character, personId: nil, chosenAt: .now).insert(db)
        }
        #expect(try home.look()?.shown == nil, "the photo shows meanwhile")
        try await home.db.writer.write { db in
            for (source, mood) in [("hologram", "fine"), ("character", "grumpy")] {
                try db.execute(sql: """
                    INSERT INTO companionCharacterImage (id, companionId, source, mood, kind, frameCount, byteCount, image)
                    VALUES (?, ?, ?, ?, 'still', 1, 1, x'00')
                    """, arguments: [UUID().uuidString.lowercased(), home.id, source, mood])
            }
        }
        #expect(try home.look()?.shown == nil, "pictures it doesn't know aren't drawn")
        try home.drawCharacter()
        #expect(try home.look()?.shown == .character)
        try await home.db.writer.write { db in
            try db.execute(sql: "UPDATE companionCharacter SET face = 'hologram' WHERE companionId = ?", arguments: [home.id])
        }
        let look = try #require(try home.look())
        #expect(look.face == nil && look.shown == nil, "a face it doesn't know shows the photo")
        #expect(look.stills.count == 4, "the unknown mood is skipped")
    }

    // MARK: The offer

    @Test("The offer: dogs and cats, while drawing is possible, until closed here; gone once there is a character or sticker or while drawing; a photo first")
    func offer() {
        func card(
            _ species: Species = .dog, look: CharacterLook? = nil, photo: Bool = true, drawing: Bool = false, dismissed: Bool = false,
            availability: CharacterAvailability = .available(roundsLeft: 3)
        ) -> CharacterOffer.Card {
            CharacterOffer.card(species: species, look: look, hasPhoto: photo, isDrawing: drawing, dismissed: dismissed, availability: availability)
        }
        let picture = CharacterLook.Picture(id: CharacterImage.ID(UUID()), byteCount: 1, frameCount: 1)
        #expect(card() == .draw)
        #expect(card(.cat) == .draw)
        #expect(card(photo: false) == .needsPhoto, "no photo: a photo first")
        #expect(card(availability: .available(roundsLeft: nil)) == .draw, "before the allowance answers")
        for species in [Species.bird, .rabbit, .fish, .plant, .other] {
            #expect(card(species) == .hidden, "\(species) isn't drawn yet")
        }
        #expect(card(look: CharacterLook(sticker: picture)) == .hidden, "a sticker")
        #expect(card(look: CharacterLook(face: .photo, stills: [.fine: picture])) == .hidden, "a character, even one not shown")
        #expect(card(look: CharacterLook(face: .character)) == .draw, "a face row whose character hasn't arrived isn't a character")
        #expect(card(drawing: true) == .hidden, "while one is being drawn")
        #expect(card(dismissed: true) == .hidden)
        #expect(card(availability: .unavailable) == .hidden, "no relay in this build")
        #expect(card(availability: .available(roundsLeft: 0)) == .hidden, "no rounds left")

        let suite = "offer-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let id = Companion.ID(UUID()), other = Companion.ID(UUID())
        CharacterOffer.dismiss(id, defaults: defaults)
        #expect(CharacterOffer.isDismissed(id, defaults: defaults))
        #expect(!CharacterOffer.isDismissed(other, defaults: defaults), "per companion")
    }

    @Test("The faces offered are the ones there are, in a fixed order, and the one showing is named")
    func faces() {
        let picture = CharacterLook.Picture(id: CharacterImage.ID(UUID()), byteCount: 1, frameCount: 1)
        var look = CompanionLook(species: .dog, coat: .honey)
        #expect(FaceSheetContent.offered(look) == [.drawn])
        #expect(FaceSheetContent.shown(look) == .drawn)
        look.photo = .unsaved(Data("photo".utf8))
        #expect(FaceSheetContent.shown(look) == .photo)
        look.character = CharacterLook(face: .sticker, sticker: picture, stills: [.fine: picture])
        #expect(FaceSheetContent.offered(look) == [.character, .sticker, .photo, .drawn])
        #expect(FaceSheetContent.shown(look) == .sticker)
        #expect(CompanionFaceChoice.drawn.label(species: .dog) == "Drawn face")
        #expect(CompanionFaceChoice.drawn.label(species: .bird) == "Emoji")
    }
}
