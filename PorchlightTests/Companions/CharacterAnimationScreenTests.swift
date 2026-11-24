#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// A character on a screen, at rest and mid-play, hosted in the unit bundle (`HostedScreen`)
/// with sprites drawn in code: at rest it is its still, and a frame of its stored strip
/// stands in for the still, never over it.
///
/// With `TEST_RUNNER_PORCHLIGHT_SCREEN_SHOTS=<folder>` each is written there as a PNG.
@Suite("A character's animation, on the screen")
@MainActor
struct CharacterAnimationScreenTests {
    private struct Drawn {
        let db: AppDatabase
        let still: CharacterLook.Picture
        let frames: CharacterLook.Picture
    }

    /// A companion with a character whose doing-fine mood has its still and its strip.
    private func drawn() throws -> Drawn {
        let db = try AppDatabase.inMemory(installId: "character-animation")
        let made = try db.createHousehold(name: "The Lake House", people: [PersonDraft(name: "James", color: .blue)])
        var draft = CompanionDraft.new(species: .dog)
        draft.name = "Yo-Yo"
        let companionId = try db.saveCompanion(draft, householdId: made.id)
        let still = try #require(CharacterPlaceholders.sprite(species: .dog, variant: 0, mood: .zoomies))
        let gif = try #require(CharacterPlaceholders.animation(species: .dog, variant: 0, mood: .zoomies))
        let strip = try #require(CharacterAnimationCodec.strip(fromGIF: gif))
        let images = [
            CharacterImage(companionId: companionId, source: .character, mood: .fine, image: still),
            CharacterImage(companionId: companionId, source: .character, mood: .fine, kind: .frames, frameCount: strip.frameCount, image: strip.image),
        ]
        try db.writer.write { db in try AppDatabase.replace(.character, of: companionId, with: images, db: db) }
        let look = try #require(try db.writer.read { try AppDatabase.characterLooks($0, householdId: made.id) }[companionId])
        return Drawn(db: db, still: try #require(look.still(.fine)), frames: try #require(look.animation(.fine)))
    }

    /// How many pixels of a picture are not the paper behind it, in the square the face fills.
    private func inked(_ image: UIImage, in rect: CGRect) throws -> Int {
        let cg = try #require(image.cgImage)
        let scale = CGFloat(cg.width) / image.size.width
        let area = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        let crop = try #require(cg.cropping(to: area))
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let context = try #require(CGContext(data: &bytes, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let paper = (bytes[0], bytes[1], bytes[2])
        return stride(from: 0, to: bytes.count, by: 4).count { abs(Int(bytes[$0]) - Int(paper.0)) + abs(Int(bytes[$0 + 1]) - Int(paper.1)) + abs(Int(bytes[$0 + 2]) - Int(paper.2)) > 24 }
    }

    private func page(_ title: String, @ViewBuilder face: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.display(22))
            face()
            Text("Below the face").font(.body(14, weight: 600))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    @Test("At rest a character is its still, whole and in place", arguments: ["light", "dark"])
    func atRest(lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        let drawn = try drawn()
        let screen = page("At rest") {
            CharacterAnimationView(still: drawn.still, frames: drawn.frames, size: 200) { Color.red.frame(width: 200, height: 200) }
        }
        .environment(PhotoImages(database: drawn.db))
        // Reduce Motion in the host would be the same picture: at rest nothing moves anyway.
        let hosted = try await HostedScreen.host(screen, look: look)
        try hosted.saveShot("character-animation-rest-\(look.name)")
        #expect(hosted.element(beginningWith: "At rest") != nil && hosted.element(beginningWith: "Below the face") != nil, "\(hosted.listing)")
        let below = try #require(hosted.element(beginningWith: "Below the face"))
        let title = try #require(hosted.element(beginningWith: "At rest"))
        #expect(below.frame.minY - title.frame.maxY >= 200, "the face holds its square")
        #expect(try inked(hosted.image, in: CGRect(x: 16, y: title.frame.maxY + 16, width: 200, height: 200)) > 2000, "the still is drawn")
    }

    @Test("Mid-play a frame of the strip stands in for the still: one sprite, not two, and the strip's other frames out of sight")
    func midPlay() async throws {
        let drawn = try drawn()
        var inkedByFrame: [Int] = []
        for index in [0, 1, 4] {
            let screen = page("Frame \(index)") {
                CharacterFrame(strip: drawn.frames, index: index, size: 200) { Color.red.frame(width: 200, height: 200) }
            }
            .environment(PhotoImages(database: drawn.db))
            let hosted = try await HostedScreen.host(screen, look: .light)
            try hosted.saveShot("character-animation-frame-\(index)")
            let title = try #require(hosted.element(beginningWith: "Frame"))
            let below = try #require(hosted.element(beginningWith: "Below the face"))
            #expect(below.frame.minY - title.frame.maxY >= 200 && below.frame.minY - title.frame.maxY < 260, "a frame is the face's size, not the strip's")
            let face = CGRect(x: 16, y: title.frame.maxY + 16, width: 200, height: 200)
            inkedByFrame.append(try inked(hosted.image, in: face))
            // Right of the face, where the strip's next frames would spill if it weren't clipped.
            #expect(try inked(hosted.image, in: CGRect(x: 230, y: face.minY, width: 140, height: 200)) == 0, "frame \(index) shows one frame only")
        }
        #expect(inkedByFrame.allSatisfy { $0 > 2000 }, "each frame is drawn: \(inkedByFrame)")
        #expect(Set(inkedByFrame).count > 1, "and they are different frames: \(inkedByFrame)")
    }

    @Test("A strip whose bytes are gone shows what waits in its place, the still")
    func stripGone() async throws {
        let drawn = try drawn()
        try await drawn.db.writer.write { db in _ = try CharacterImage.deleteOne(db, id: drawn.frames.id) }
        let screen = page("Gone") {
            CharacterFrame(strip: drawn.frames, index: 2, size: 200) {
                Text("The still").font(.body(14, weight: 600)).frame(width: 200, height: 200)
            }
        }
        .environment(PhotoImages(database: drawn.db))
        let hosted = try await HostedScreen.host(screen, look: .light)
        #expect(hosted.element(beginningWith: "The still") != nil, "\(hosted.listing)")
    }
}
#endif
