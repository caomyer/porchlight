#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// The companion's face on the phone, its page and its Today card
/// (docs/design/companion-characters.md, "Where it stands"), hosted in the unit bundle
/// (`HostedScreen`) for each kind of face: a character and a photo sticker (drawn in code),
/// a photo (drawn in code) and the drawn face, on the smallest and largest phones, in light,
/// dark and at the largest text. Review shots; the checks are what must hold on any phone.
///
/// With `TEST_RUNNER_PORCHLIGHT_SCREEN_SHOTS=<folder>` each is written there as a PNG.
@Suite("The companion's face on the phone")
@MainActor
struct CharacterPresenceScreenTests {
    private struct Home {
        let db: AppDatabase
        let store: CompanionStore
        let me: Person
        let companionId: Companion.ID
    }

    /// A household of two with the sample dog showing `face`. `long`: the longest line a
    /// Today card realistically has, a long name walked by someone else ("by Carol").
    private func home(_ face: String, long: Bool = false) throws -> Home {
        let db = try AppDatabase.inMemory(installId: "presence")
        let made = try db.createHousehold(
            name: "The Lake House",
            people: [PersonDraft(name: long ? "Carol" : "James", color: .blue), PersonDraft(name: "Mia", color: .coral)]
        )
        try db.markSetupCompleted(householdId: made.id)
        let snapshot = try db.snapshot()
        try CompanionSamples.seed(db, household: try #require(snapshot.household), people: snapshot.people)
        let companionId = try #require(CompanionStore(database: db).companions.first).id
        if face != "drawn" {
            try db.writer.write { db in try CompanionPhoto(companionId: companionId, image: CharacterPlaceholders.photo()).upsert(db) }
        }
        if face == "sticker" {
            try db.saveSticker(try #require(CharacterPlaceholders.sticker()), companionId: companionId, by: nil)
        }
        if face == "character" {
            var stills: [CharacterMood: Data] = [:]
            var strips: [CharacterMood: (Data, Int)] = [:]
            for mood in CharacterMood.allCases {
                stills[mood] = CharacterPlaceholders.sprite(species: .dog, variant: 0, mood: mood)
                if let gif = CharacterPlaceholders.animation(species: .dog, variant: 0, mood: mood),
                   let strip = CharacterAnimationCodec.strip(fromGIF: gif) { strips[mood] = (strip.image, strip.frameCount) }
            }
            try db.saveCharacter(stills: stills, strips: strips, companionId: companionId, by: nil)
        }
        if long {
            try db.writer.write { db in try db.execute(sql: "UPDATE companion SET name = 'Sir Wigglesworth' WHERE id = ?", arguments: [companionId]) }
        }
        return Home(db: db, store: CompanionStore(database: db), me: snapshot.people[long ? 1 : 0], companionId: companionId)
    }

    nonisolated static let faces = ["character", "sticker", "photo", "drawn"]
    nonisolated static let phones: [(String, CGSize)] = [
        ("smallest", CGSize(width: 375, height: 667)), ("iphone15", CGSize(width: 393, height: 852)), ("largest", CGSize(width: 440, height: 956)),
    ]

    @Test("The page: every kind of face, on the smallest, an iPhone 15 and the largest phone, in each look", arguments: faces, ["light", "dark", "largest"])
    func page(face: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        for (phone, size) in Self.phones {
            let home = try home(face)
            let toasts = ToastCenter()
            let screen = PocketCompanionWeek(
                companionId: home.companionId,
                logging: PocketLogging(companions: home.store, home: HomeStore(database: home.db), toasts: toasts, me: home.me.id)
            )
            .environment(home.store).environment(toasts).environment(PhotoImages(database: home.db)).environment(\.me, home.me)
            let hosted = try await HostedScreen.host(screen, look: look, size: size)
            let name = "presence-page-\(face)-\(phone)-\(look.name)"
            try hosted.saveShot(name)
            for element in hosted.elements {
                #expect(element.frame.minX >= 0 && element.frame.maxX <= size.width, "\(element.label.prefix(40)) is whole across \(name): \(element.frame)")
            }
            // What is promised for "Log a walk", with center stage at 168 points on every phone:
            // on the first screen of the largest phone, between the navigation bar and the tab
            // bar; on smaller phones a scroll away. Measured in the app on a 393 by 852 phone
            // (iOS 17.5, the UI suite's), it ended at 702 points before center stage and at about
            // 802 after it, with the tab bar's top at 770: 32 points short, after the hero was
            // built as the approved mock and the pager's kept row went. The hosted page has no
            // bars and starts 74 points higher than in the app (the same button, 747.5 hosted
            // and 821.5 in the app, measured together), so the room is the screen less the tab
            // bar (83) and those 74, and 3 more for the largest phone's taller status bar.
            let log = try #require(hosted.elements.first { $0.isButton && $0.label.hasPrefix("Log a walk") }, "\(hosted.listing)")
            if look.textSize == .large && phone == "largest" {
                let room = size.height - 83 - 77
                #expect(log.frame.maxY <= room, "Log a walk on the first screen of \(name): its bottom at \(log.frame.maxY) of \(room)")
            }
            #expect(log.frame.width > size.width / 2, "and whole, to scroll to: \(log.frame)")
        }
    }

    @Test("Today's card: every kind of face and the longest line, under a banner, on the smallest, an iPhone 15 and the largest phone, in each look", arguments: faces + ["long"], ["light", "dark", "largest"])
    func today(face: String, lookName: String) async throws {
        let look = HostedScreen.Look.named(lookName)
        for (phone, size) in Self.phones {
            let home = face == "long" ? try home("character", long: true) : try home(face)
            let now = CompanionClock.now()
            let reports = home.store.companions.compactMap { home.store.report(for: $0.id, now: now) }
            let cards = PocketToday.cards(reports, calendar: home.store.snapshot.calendar)
            let handlers = PocketCareHandlers(log: { _, _, _ in }, more: { _, _, _ in }, open: { _ in }, edit: { _, _ in })
            // Today's own column: a banner above the card, as the dinner one is.
            let screen = ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Yo-Yo's dinner wasn't logged yesterday")
                        .phoneFont(.body, 14, weight: 700)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(Color(hex: 0xF5E6C8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    PocketCareSection(cards: cards, handlers: handlers)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .background(Theme.background)
            .environment(AppModel(database: home.db)).environment(home.store).environment(PhotoImages(database: home.db)).environment(\.me, home.me)
            let hosted = try await HostedScreen.host(screen, look: look, size: size)
            let name = "presence-today-\(face)-\(phone)-\(look.name)"
            try hosted.saveShot(name)
            for element in hosted.elements {
                #expect(element.frame.minX >= 0 && element.frame.maxX <= size.width, "\(element.label.prefix(40)) is whole across \(name): \(element.frame)")
            }
        }
    }

    // MARK: One picture at rest and in motion

    private func pixels(_ view: some View, images: PhotoImages, scale: CGFloat = 3) throws -> Data {
        let renderer = ImageRenderer(content: view.environment(images).environment(\.displayScale, scale))
        renderer.scale = scale
        let image = try #require(renderer.uiImage?.cgImage)
        return try #require(image.dataProvider?.data as Data?)
    }

    /// A strip of the placeholder's zoomies at `side` pixels a frame, and its still.
    private func pictures(side: Int) throws -> (still: CharacterLook.Picture, strip: CharacterLook.Picture, images: PhotoImages, db: AppDatabase) {
        let home = try self.home("drawn")
        let still = try #require(CharacterPlaceholders.sprite(species: .dog, variant: 0, mood: .zoomies))
        let gif = try #require(CharacterPlaceholders.animation(species: .dog, variant: 0, mood: .zoomies))
        let strip = try #require(CharacterAnimationCodec.strip(fromGIF: gif, frameSide: side))
        try home.db.saveCharacter(stills: [.fine: still, .zoomies: still], strips: [.zoomies: (strip.image, strip.frameCount)], companionId: home.companionId, by: nil)
        let householdId = try #require(home.store.snapshot.household?.id)
        let look = try #require(try home.db.writer.read { try AppDatabase.characterLooks($0, householdId: householdId) }[home.companionId])
        return (try #require(look.stills[.zoomies]), try #require(look.animation(.zoomies)), PhotoImages(database: home.db), home.db)
    }

    @Test("At rest a face shows its animation's first frame, the very pixels a play starts and ends on, at every size, for 256 and 512 pixel strips")
    func restIsFirstFrame() async throws {
        for side in [256, 512] {
            let (still, strip, images, _) = try pictures(side: side)
            _ = await images.image(PhotoRequest(.character(strip.id, byteCount: strip.byteCount)))
            for size in [28.0, 84, 168, 184] {
                let rest = try pixels(CharacterAnimationView(still: still, frames: strip, size: size) { EmptyView() }, images: images)
                let first = try pixels(CharacterFrame(strip: strip, index: 0, size: size) { EmptyView() }, images: images)
                #expect(rest == first, "\(side) pixel frames at \(size) points: rest is the first frame")
                let stillAlone = try pixels(CharacterStill(picture: still, isPixelArt: true, size: size) { EmptyView() }, images: images)
                #expect(rest != stillAlone, "and not the separate still")
            }
            // The pair, to look at: at rest, and the first frame of a play, at center stage.
            for (name, face) in [("rest", AnyView(CharacterAnimationView(still: still, frames: strip, size: 168) { EmptyView() })),
                                 ("first-played-frame", AnyView(CharacterFrame(strip: strip, index: 0, size: 168) { EmptyView() }))] {
                let hosted = try await HostedScreen.host(face.padding(40).background(Theme.surface).environment(images), look: .light)
                try hosted.saveShot("presence-\(side)-\(name)")
            }
        }
    }

    @Test("Before the strip is read nothing shows, never the still first; with no strip the still shows")
    func coldOpen() async throws {
        let (still, strip, images, _) = try pictures(side: 512)
        _ = await images.image(PhotoRequest(.character(still.id, byteCount: still.byteCount)))
        let cold = try pixels(CharacterAnimationView(still: still, frames: strip, size: 84) { EmptyView() }, images: images)
        #expect(cold.allSatisfy { $0 == 0 }, "clear until the first frame is read: no still to swap away")
        let noStrip = try pixels(CharacterAnimationView(still: still, frames: nil, size: 84) { EmptyView() }, images: images)
        let stillAlone = try pixels(CharacterStill(picture: still, isPixelArt: true, size: 84) { EmptyView() }, images: images)
        #expect(noStrip == stillAlone, "no animation: the mood's still")
    }

    @Test("A strip from before 512 pixel frames, at 168 points: crisp, scaled without smoothing")
    func oldStripAtStage() async throws {
        for side in [256, 512] {
            let (still, strip, images, _) = try pictures(side: side)
            _ = await images.image(PhotoRequest(.character(strip.id, byteCount: strip.byteCount)))
            let screen = CharacterAnimationView(still: still, frames: strip, size: 168) { EmptyView() }
                .padding(40).background(Theme.surface).environment(images)
            let hosted = try await HostedScreen.host(screen, look: .light)
            try hosted.saveShot("presence-strip-\(side)-at-168")
        }
        #expect(CharacterPixels.interpolation(framePixels: 256, points: 168, displayScale: 3) == .none, "enlarged: crisp")
        #expect(CharacterPixels.interpolation(framePixels: 512, points: 84, displayScale: 3) == .high, "reduced: smoothed, nothing dropped")
    }

    /// The real size of a pet's animations at 512 pixel frames, from real relay GIFs in a folder
    /// named at run time (`TEST_RUNNER_PORCHLIGHT_RELAY_GIFS`); none are kept in the repository.
    @Test("The real relay's animations, as 512 pixel strips: their size")
    func realSizes() throws {
        guard let path = ProcessInfo.processInfo.environment["PORCHLIGHT_RELAY_GIFS"] else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let gifs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "gif" }
        for gif in gifs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let data = try Data(contentsOf: gif)
            let big = CharacterAnimationCodec.strip(fromGIF: data, frameSide: 512)
            let small = CharacterAnimationCodec.strip(fromGIF: data, frameSide: 256)
            print("RELAY-STRIP \(gif.lastPathComponent): gif \(data.count) bytes, 512 strip \(big?.image.count ?? -1) bytes, 256 strip \(small?.image.count ?? -1) bytes, \(big?.frameCount ?? 0) frames")
        }
    }
}
#endif
