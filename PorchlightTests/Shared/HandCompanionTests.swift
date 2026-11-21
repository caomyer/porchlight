import CoreText
import Foundation
import os
import Testing
import UIKit
@testable import Porchlight

/// The handwriting's companion for Chinese and Japanese (docs/proposals/food-diary-polish.html):
/// which faces each reader gets, how large they are drawn, which titles ask for them, and how
/// asking iOS for them goes, with the download faked. Whether iOS really delivers a face can
/// only be seen on a device ("Sync details", "Handwriting fonts").
@Suite("The handwriting's companion")
struct HandCompanionTests {
    private func names(_ languages: [String], weight: CGFloat = 700) -> [String] {
        HandCompanion.faces(languages: languages, weight: weight).map(\.postScriptName)
    }

    @Test("Simplified, Traditional and Japanese readers each get their own forms; everyone else Simplified")
    func readers() {
        #expect(names(["en-US"]) == ["HannotateSC-W7"])
        #expect(names(["zh-Hans-CN"]) == ["HannotateSC-W7"])
        #expect(names(["zh-CN"]) == ["HannotateSC-W7"])
        #expect(names(["zh-Hant-TW"]) == ["HannotateTC-W7"])
        #expect(names(["zh-TW"]) == ["HannotateTC-W7"])
        #expect(names(["zh-HK"]) == ["HannotateTC-W7"])
        #expect(names(["ja-JP"]) == ["Klee-Demibold", "HannotateSC-W7"])
        #expect(names(["ko-KR"]) == ["HannotateSC-W7"], "Korean keeps the system's face; Han characters still get Hannotate")
        // The first Chinese or Japanese language decides, whatever comes before it.
        #expect(names(["en-US", "ja-JP", "zh-Hant-TW"]) == ["Klee-Demibold", "HannotateSC-W7"])
        #expect(names(["en-GB", "zh-Hant-HK", "ja-JP"]) == ["HannotateTC-W7"])
        #expect(names([]) == ["HannotateSC-W7"])
    }

    @Test("Caveat's 600 gets the lighter weights, 700 the heavier")
    func weights() {
        #expect(names(["ja"], weight: 600) == ["Klee-Medium", "HannotateSC-W5"])
        #expect(names(["ja"], weight: 700) == ["Klee-Demibold", "HannotateSC-W7"])
        #expect(names(["zh-Hant"], weight: 560) == ["HannotateTC-W5"])
        #expect(HandCompanion.faces(languages: ["ja"]).map(\.postScriptName) == ["Klee-Medium", "HannotateSC-W5", "Klee-Demibold", "HannotateSC-W7"])
    }

    @Test("Chinese characters and kana ask for the companion; English, Korean and emoji don't")
    func wants() {
        #expect(HandCompanion.wants("大盘鸡"))
        #expect(HandCompanion.wants("Steak 牛排"))
        #expect(HandCompanion.wants("おにぎり"))
        #expect(HandCompanion.wants("ラーメン"))
        #expect(HandCompanion.wants("滷肉飯"))
        #expect(!HandCompanion.wants("Steak & eggs"))
        #expect(!HandCompanion.wants("비빔밥"))
        #expect(!HandCompanion.wants("Pizza 🍕"))
        #expect(!HandCompanion.wants(""))
    }

    /// Ascent and descent in ems, measured from the fonts: Caveat's from the bundled file,
    /// Hannotate's and Klee's from Apple's (they aren't on a test machine).
    private static let hannotate = (ascent: 1.06, descent: 0.34)
    private static let klee = (ascent: 0.88, descent: 0.12)

    @Test("Each companion's lines stay inside Caveat's, so rows and polaroids keep their height")
    func heights() throws {
        let caveat = UIFont.variable(.hand, size: 100, weight: 700)
        let ascent = caveat.ascender / 100
        let descent = -caveat.descender / 100
        #expect(HandCompanion.hannotateScale * Self.hannotate.ascent <= ascent)
        #expect(HandCompanion.hannotateScale * Self.hannotate.descent <= descent + 0.005)
        #expect(HandCompanion.kleeScale * Self.klee.ascent <= ascent)
        #expect(HandCompanion.kleeScale * Self.klee.descent <= descent)
        // Where the face is on this machine, the same from the font itself.
        for face in HandCompanion.faces(languages: ["ja"]) where HandCompanionFonts.installed(face.postScriptName) {
            let font = CTFontCreateWithName(face.postScriptName as CFString, 100, nil)
            #expect(face.scale * CTFontGetAscent(font) / 100 <= ascent, "\(face.postScriptName)")
            #expect(face.scale * CTFontGetDescent(font) / 100 <= descent + 0.005, "\(face.postScriptName)")
        }
    }

    @Test("The cascade has only the faces on the device, each drawn smaller to Caveat's capitals")
    func cascade() throws {
        #expect(HandCompanion.cascade(weight: 700, ready: []).isEmpty, "nothing ready: the system's face draws, as before")
        let ready = HandCompanion.faces(languages: Locale.preferredLanguages, weight: 700).map(\.postScriptName)
        let cascade = HandCompanion.cascade(weight: 700, ready: Set(ready))
        #expect(cascade.map { $0.fontAttributes[.name] as? String } == ready)
        for descriptor in cascade {
            #expect(descriptor.matrix.a < 1 && descriptor.matrix.a == descriptor.matrix.d, "scaled evenly: \(descriptor.matrix)")
        }
    }
}

/// Asking iOS for the faces, with the download and the font check faked.
@Suite("Fetching the handwriting's companion")
@MainActor
struct HandCompanionFontsTests {
    /// A pretend device: which faces it has, and the downloads asked for.
    final class Device: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock<(installed: Set<String>, asked: [String], reports: [String: @Sendable (HandCompanionFonts.DownloadEvent) -> Void])>(initialState: ([], [], [:]))
        var installed: Set<String> {
            get { lock.withLock { $0.installed } }
            set { lock.withLock { $0.installed = newValue } }
        }
        var asked: [String] { lock.withLock { $0.asked } }
        func has(_ name: String) -> Bool { installed.contains(name) }
        func download(_ name: String, report: @escaping @Sendable (HandCompanionFonts.DownloadEvent) -> Void) {
            lock.withLock { $0.asked.append(name); $0.reports[name] = report }
        }
        func send(_ event: HandCompanionFonts.DownloadEvent, to name: String) {
            lock.withLock { $0.reports[name] }?(event)
        }
    }

    private let faces = [HandCompanion.Face(postScriptName: "HannotateSC-W5", scale: 0.88), HandCompanion.Face(postScriptName: "HannotateSC-W7", scale: 0.88)]

    private func fonts(_ device: Device) -> (HandCompanionFonts, OSAllocatedUnfairLock<Set<String>>) {
        let ready = OSAllocatedUnfairLock<Set<String>>(initialState: [])
        let fonts = HandCompanionFonts(faces: faces, isInstalled: device.has, download: device.download, ready: ready, recheck: .milliseconds(5))
        return (fonts, ready)
    }

    /// Lets the main actor run what the fake download handed it.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(60))
    }

    @Test("English titles ask for nothing")
    func englishAsksNothing() {
        let device = Device()
        let (fonts, _) = fonts(device)
        fonts.note(titles: ["Steak", "Pancakes", "비빔밥"])
        #expect(device.asked.isEmpty)
        #expect(fonts.summary == "not needed yet")
    }

    @Test("Faces already on the device are ready at once, with no download, and titles draw again")
    func alreadyThere() {
        let device = Device()
        device.installed = ["HannotateSC-W5", "HannotateSC-W7"]
        let (fonts, ready) = fonts(device)
        fonts.note(titles: ["Steak", "大盘鸡"])
        #expect(device.asked.isEmpty)
        #expect(ready.withLock { $0 } == ["HannotateSC-W5", "HannotateSC-W7"])
        #expect(fonts.generation == 2)
        #expect(fonts.summary == "HannotateSC-W5 ready, HannotateSC-W7 ready")
    }

    @Test("A download is asked for once, shows its progress, and its face is ready when it arrives")
    func downloads() async {
        let device = Device()
        let (fonts, ready) = fonts(device)
        fonts.note(titles: ["大盘鸡"])
        fonts.note(titles: ["大盘鸡", "牛排"])
        #expect(device.asked == ["HannotateSC-W5", "HannotateSC-W7"], "asked once per face, however often titles change")
        #expect(fonts.summary == "HannotateSC-W5 downloading 0%, HannotateSC-W7 downloading 0%")
        device.send(.progress(40), to: "HannotateSC-W7")
        await settle()
        #expect(fonts.states["HannotateSC-W7"] == .downloading(percent: 40))
        #expect(ready.withLock { $0 }.isEmpty, "nothing is drawn from a face that isn't here yet")
        device.installed = ["HannotateSC-W7"]
        device.send(.finished, to: "HannotateSC-W7")
        await settle()
        #expect(fonts.states["HannotateSC-W7"] == .ready)
        #expect(ready.withLock { $0 } == ["HannotateSC-W7"])
        #expect(fonts.generation == 1)
    }

    @Test("A face that takes a moment after its download is ready once iOS makes it")
    func lateFace() async {
        let device = Device()
        let (fonts, _) = fonts(device)
        fonts.note(titles: ["大盘鸡"])
        device.send(.finished, to: "HannotateSC-W5")
        try? await Task.sleep(for: .milliseconds(8))
        device.installed = ["HannotateSC-W5"]
        await settle()
        #expect(fonts.states["HannotateSC-W5"] == .ready)
    }

    @Test("No network or a failed download leaves the system's face, says why, and tries again later")
    func failsAndRetries() async {
        let device = Device()
        let (fonts, ready) = fonts(device)
        fonts.note(titles: ["大盘鸡"])
        device.send(.failed("The Internet connection appears to be offline."), to: "HannotateSC-W5")
        device.send(.finished, to: "HannotateSC-W5")
        device.send(.finished, to: "HannotateSC-W7")
        await settle()
        #expect(fonts.states["HannotateSC-W5"] == .failed("The Internet connection appears to be offline."))
        #expect(fonts.states["HannotateSC-W7"] == .failed("not on this device after downloading"))
        #expect(ready.withLock { $0 }.isEmpty)
        #expect(fonts.summary.contains("HannotateSC-W5 failed (The Internet connection appears to be offline.)"))
        // Coming to the front right away doesn't ask again; five minutes later it does.
        fonts.retryIfFailed(now: .now)
        #expect(device.asked.count == 2)
        fonts.retryIfFailed(now: .now.addingTimeInterval(5 * 60 + 1))
        #expect(device.asked.count == 4)
    }
}
