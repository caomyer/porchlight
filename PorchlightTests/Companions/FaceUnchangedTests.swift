#if DEBUG
import GRDB
import SwiftUI
import Testing
import UIKit
@testable import Porchlight

/// A household that updates and does nothing sees no change to any companion's face
/// (docs/design/companion-characters.md, "Nothing changes on update"): each kind of face
/// draws the same pixels as the release before characters, the update's migration leaves
/// every existing row as it was, and browsing makes no cut-out.
@Suite("Nothing changes on update")
@MainActor
struct FaceUnchangedTests {
    /// The release's face, verbatim (from 925abb6, before characters), without the bob,
    /// which only moves it: the reference every face without a sticker or character must
    /// match pixel for pixel.
    private struct ReleaseFace: View {
        var look: CompanionLook
        var expression: FaceExpression = .happy
        var size: CGFloat

        var body: some View {
            Group {
                if let photo = look.photo {
                    PhotoView(request: PhotoRequest(photo)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.surface, lineWidth: max(1, size * 0.03)))
                    } placeholder: { isMissing in
                        if isMissing {
                            drawn
                        } else {
                            Circle().fill(look.tint.wash(0.32)).frame(width: size, height: size)
                        }
                    }
                } else {
                    drawn
                }
            }
            .accessibilityHidden(true)
        }

        @ViewBuilder
        private var drawn: some View {
            if look.species.hasDrawnFace {
                DrawnFace(species: look.species, coat: look.coat, expression: expression)
                    .frame(width: size, height: size)
            } else {
                Text(look.species.emoji)
                    .font(.system(size: size * 0.52))
                    .frame(width: size * 0.86, height: size * 0.86)
                    .background(look.tint.wash(0.32), in: Circle())
                    .frame(width: size, height: size)
            }
        }
    }

    private func render(_ view: some View, images: PhotoImages, scheme: ColorScheme) throws -> Data {
        let renderer = ImageRenderer(content: view.environment(images).environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = try #require(renderer.uiImage?.cgImage)
        return try #require(image.dataProvider?.data as Data?)
    }

    /// A face's pixels once its drawing has settled: rendered until two renders in a row
    /// agree. On a hosted runner the first render of a face in the process can differ from
    /// every one after it (the missing photo's placeholder at 28 points, in runs 45347603046,
    /// 45352447810 and 45355876207, never on a development Mac), and a reference taken from
    /// that cold first render fails a comparison that is in fact equal. Settling both sides
    /// keeps the comparison exact; a drawing that never settles fails on its own.
    private func pixels(_ view: some View, images: PhotoImages, scheme: ColorScheme, photo: PhotoRequest) async throws -> Data {
        var last: Data?
        for _ in 0..<6 {
            // The decoded photo kept in the cache, as on a screen that has shown it: NSCache may
            // let it go at any time, and the runner's memory is tight.
            _ = await images.image(photo)
            let data = try render(view, images: images, scheme: scheme)
            if data == last { return data }
            last = data
        }
        Issue.record("The face's drawing never settled in six renders")
        return try #require(last)
    }

    @Test("Every kind of face draws the same pixels as the release before characters, with no face chosen or one chosen with nothing to show")
    func samePixels() async throws {
        let db = try AppDatabase.inMemory(installId: "faces")
        let images = PhotoImages(database: db)
        let photo = PhotoSource.unsaved(CharacterPlaceholders.photo())
        // The photo decoded first, so both draw it in their first frame, as a cached photo is.
        let request = PhotoRequest(photo)
        _ = await images.image(request)
        let kinds: [(String, CompanionLook, FaceExpression)] = [
            ("photo", CompanionLook(species: .dog, coat: .honey, photo: photo), .happy),
            ("dog", CompanionLook(species: .dog, coat: .honey), .happy),
            ("sleepy dog", CompanionLook(species: .dog, coat: .cocoa), .sleepy),
            ("cat", CompanionLook(species: .cat, coat: .honey), .happy),
            ("bird", CompanionLook(species: .bird, coat: .honey), .happy),
            ("plant", CompanionLook(species: .plant, coat: .honey), .happy),
            ("missing photo", CompanionLook(species: .cat, coat: .honey, photo: .companion(Companion.ID(UUID()), byteCount: 1)), .happy),
        ]
        for (name, release, expression) in kinds {
            var nothingChosen = release
            nothingChosen.character = nil
            var photoChosen = release
            photoChosen.character = CharacterLook(face: .photo)
            var characterNotHere = release
            characterNotHere.character = CharacterLook(face: .character)
            for scheme in [ColorScheme.light, .dark] {
                for size in [28.0, 66, 184] {
                    let expected = try await pixels(ReleaseFace(look: release, expression: expression, size: size), images: images, scheme: scheme, photo: request)
                    for (variant, look) in [("no face chosen", nothingChosen), ("photo chosen", photoChosen), ("character not here yet", characterNotHere)] {
                        let drawn = try await pixels(CompanionFace(look: look, expression: expression, size: size), images: images, scheme: scheme, photo: request)
                        #expect(drawn == expected, "\(name), \(variant), \(scheme), \(size) points")
                    }
                }
            }
        }
    }

    @Test("The update's migration leaves every row of an existing household as it was, and adds no face")
    func migrationTouchesNothing() throws {
        // An existing household, with care and a photo, as the release before characters has
        // it: today's database with the characters migration taken back out.
        let db = try AppDatabase.inMemory(installId: "update")
        let household = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)])
        try db.markSetupCompleted(householdId: household.id)
        let snapshot = try db.snapshot()
        try CompanionSamples.seed(db, household: try #require(snapshot.household), people: snapshot.people)
        try db.writer.write { db in
            let yoyo = try #require(try Companion.fetchOne(db))
            try CompanionPhoto(companionId: yoyo.id, image: CharacterPlaceholders.photo()).upsert(db)
            try db.execute(sql: """
                DROP TABLE "companionCharacterImage"; DROP TABLE "companionCharacter";
                DELETE FROM grdb_migrations WHERE identifier = ?;
                """, arguments: [AppDatabase.characterMigration])
        }

        func everything() throws -> [String: [Row]] {
            try db.writer.read { db in
                var rows: [String: [Row]] = [:]
                for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'") {
                    rows[table] = try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\" ORDER BY rowid")
                }
                return rows
            }
        }
        let before = try everything()
        #expect(before["companion"]?.isEmpty == false && before["careLog"]?.isEmpty == false && before["companionPhoto"]?.count == 1)
        try AppDatabase.migrator(files: nil).migrate(db.writer)
        var after = try everything()
        #expect(after.removeValue(forKey: "companionCharacter") == [], "no face is chosen for anyone")
        #expect(after.removeValue(forKey: "companionCharacterImage") == [], "nothing is drawn or cut out")
        #expect(after == before, "every existing row is as it was")
    }
}

extension PhotoStickerTests {
    @MainActor
    @Test("Browsing a household's companions, on their pages and in the care sheet, makes no cut-out")
    func browsingCutsNothing() async throws {
        let before = PhotoSticker.cutOuts.count
        let db = try AppDatabase.inMemory(installId: "browse")
        let made = try db.createHousehold(name: "Home", people: [PersonDraft(name: "James", color: .blue), PersonDraft(name: "Mia", color: .coral)])
        try db.markSetupCompleted(householdId: made.id)
        let snapshot = try db.snapshot()
        try CompanionSamples.seed(db, household: try #require(snapshot.household), people: snapshot.people)
        let store = CompanionStore(database: db)
        let companion = try #require(store.companions.first)
        try await db.writer.write { db in try CompanionPhoto(companionId: companion.id, image: CharacterPlaceholders.photo()).upsert(db) }
        let toasts = ToastCenter()
        let me = snapshot.people[0]
        let logging = PocketLogging(companions: store, home: HomeStore(database: db), toasts: toasts, me: me.id)
        let week = PocketCompanionWeek(companionId: companion.id, logging: logging)
            .environment(store).environment(toasts).environment(PhotoImages(database: db)).environment(\.me, me)
        _ = try await HostedScreen.host(week, look: .light)
        let walk = try #require(store.snapshot.routines(of: companion.id).first)
        let sheet = PocketCareSheet(request: PocketCareSheet.Request(companionId: companion.id, routineId: walk.id, people: [me.id]), logging: logging)
            .environment(AppModel(database: db)).environment(store).environment(toasts).environment(PhotoImages(database: db)).environment(\.me, me)
        _ = try await HostedScreen.host(sheet, look: .light)
        #expect(PhotoSticker.cutOuts.count == before, "no subject was cut out")
        #expect(try await db.writer.read { try CompanionCharacter.fetchCount($0) + CharacterImage.fetchCount($0) } == 0, "and nothing was stored")
    }
}
#endif
