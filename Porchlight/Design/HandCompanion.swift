import CoreText
import Foundation
import Observation
import os
import UIKit

/// The handwriting's companion for Chinese and Japanese (docs/proposals/food-diary-polish.html).
/// Caveat has no Chinese, Japanese or Korean, so a title's characters it lacks are drawn from
/// Apple's Hannotate (Klee first for Japanese readers): handwritten faces that come with iOS
/// as downloads, not in the app. Until one is on the device the system's own face draws them,
/// as before; Korean always does, as Nanum Pen Script can't be drawn large enough beside
/// Caveat without making the line taller.
enum HandCompanion {
    /// One face to fall back to, and how large to draw it against Caveat's point size.
    struct Face: Equatable, Hashable, Sendable {
        let postScriptName: String
        /// So its characters stand as tall as Caveat's capitals, and its ascent and descent
        /// stay within Caveat's, which keeps rows and polaroids the height they are in English.
        let scale: CGFloat
    }

    /// Hannotate's characters stand 0.92 em tall, Caveat's capitals 0.73: at 0.88 they sit a
    /// touch above the capitals, as written Chinese does beside English, and Hannotate's
    /// ascent (1.06 em) and descent (0.34 em) come to 0.93 and 0.30, inside Caveat's 0.96 and
    /// 0.30.
    static let hannotateScale: CGFloat = 0.88
    /// Klee's kanji stand 0.88 em tall, so it is drawn at 0.92 to match Hannotate's.
    static let kleeScale: CGFloat = 0.92

    /// The faces for a reader of `languages` (most preferred first) at Caveat's `weight`, in
    /// the order to try them. The first Chinese or Japanese language decides: Traditional
    /// Chinese gets Hannotate's Traditional forms, Japanese gets Klee's Japanese forms and
    /// kana first (and Hannotate for the Simplified characters Klee lacks), everyone else
    /// Hannotate's Simplified forms, which also have every Traditional character.
    static func faces(languages: [String], weight: CGFloat) -> [Face] {
        let bold = weight >= 650
        let simplified = Face(postScriptName: bold ? "HannotateSC-W7" : "HannotateSC-W5", scale: hannotateScale)
        let traditional = Face(postScriptName: bold ? "HannotateTC-W7" : "HannotateTC-W5", scale: hannotateScale)
        let klee = Face(postScriptName: bold ? "Klee-Demibold" : "Klee-Medium", scale: kleeScale)
        switch reader(languages) {
        case .traditional: return [traditional]
        case .japanese: return [klee, simplified]
        case .simplified: return [simplified]
        }
    }

    private enum Reader { case simplified, traditional, japanese }

    private static func reader(_ languages: [String]) -> Reader {
        for language in languages {
            let id = Locale.Language(identifier: language)
            switch id.languageCode?.identifier {
            case "ja": return .japanese
            case "zh":
                if id.script?.identifier == "Hant" { return .traditional }
                if id.script?.identifier == "Hans" { return .simplified }
                // "zh-TW" and "zh-HK" without a script are written in Traditional characters.
                if let region = id.region?.identifier, ["TW", "HK", "MO"].contains(region) { return .traditional }
                return .simplified
            default: continue
            }
        }
        return .simplified
    }

    /// Every face any reader might need, at both weights: what the app asks iOS for.
    static func faces(languages: [String]) -> [Face] {
        var seen = Set<Face>()
        return (faces(languages: languages, weight: 600) + faces(languages: languages, weight: 700)).filter { seen.insert($0).inserted }
    }

    /// Whether `text` has a character a companion draws: Chinese characters, or Japanese kana.
    static func wants(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF: true  // Hiragana, Katakana and its extension
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF: true  // Han
            default: false
            }
        }
    }

    /// The cascade to give Caveat at `weight`: only faces on this device now, each scaled.
    /// An empty list leaves the system's fallback, so nothing is ever drawn as a missing glyph.
    static func cascade(weight: CGFloat, ready: Set<String> = HandCompanionFonts.ready) -> [UIFontDescriptor] {
        faces(languages: Locale.preferredLanguages, weight: weight)
            .filter { ready.contains($0.postScriptName) }
            .map { face in
                UIFontDescriptor(fontAttributes: [.name: face.postScriptName])
                    .withMatrix(CGAffineTransform(scaleX: face.scale, y: face.scale))
            }
    }
}

/// Whether the companion faces are on this device, and asking iOS for them when a title
/// first needs one. Nothing waits for it: until a face arrives the system's face draws, and
/// when it arrives every handwritten title draws again (views read `generation`). A failed
/// or cancelled download, or no network, is tried again when the app next comes to the front
/// (at most every five minutes); a face iOS removed later is asked for on the next launch.
/// What happened is in "Sync details" and the log ("hand-fonts").
@MainActor
@Observable
final class HandCompanionFonts {
    static let shared = HandCompanionFonts()

    enum State: Equatable, Sendable {
        case notAsked
        case downloading(percent: Int)
        case ready
        case failed(String)
    }

    /// Each face's state, by PostScript name.
    private(set) var states: [String: State] = [:]
    /// Bumped whenever a face becomes ready, so handwritten titles draw again.
    private(set) var generation = 0

    /// The faces ready to draw, readable from any thread (fonts are made off the main actor
    /// too). The app's one instance fills it; a test's instance keeps its own.
    nonisolated static var ready: Set<String> { sharedReady.withLock { $0 } }
    nonisolated static let sharedReady = OSAllocatedUnfairLock<Set<String>>(initialState: [])
    private nonisolated static let log = Logger(subsystem: "com.mingyucao.porchlight", category: "hand-fonts")

    @ObservationIgnored private var asked = false
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    private let faces: [HandCompanion.Face]
    private let isInstalled: @Sendable (String) -> Bool
    private let download: @Sendable (String, @escaping @Sendable (DownloadEvent) -> Void) -> Void
    private let readyLock: OSAllocatedUnfairLock<Set<String>>
    private let recheck: Duration

    enum DownloadEvent: Sendable {
        case progress(Int)
        case failed(String)
        case finished
    }

    init(
        faces: [HandCompanion.Face] = HandCompanion.faces(languages: Locale.preferredLanguages),
        isInstalled: @escaping @Sendable (String) -> Bool = HandCompanionFonts.installed,
        download: @escaping @Sendable (String, @escaping @Sendable (DownloadEvent) -> Void) -> Void = HandCompanionFonts.requestDownload,
        ready: OSAllocatedUnfairLock<Set<String>> = HandCompanionFonts.sharedReady,
        recheck: Duration = .seconds(1)
    ) {
        self.faces = faces
        self.isInstalled = isInstalled
        self.download = download
        readyLock = ready
        self.recheck = recheck
        for face in faces { states[face.postScriptName] = .notAsked }
    }

    /// Called with the diary's titles whenever they change; asks for the faces the first
    /// time one of them needs a companion, and after that does nothing.
    func note(titles: some Sequence<String>) {
        guard !asked, titles.contains(where: HandCompanion.wants) else { return }
        asked = true
        Self.log.info("A title needs the handwriting's companion; checking \(self.faces.map(\.postScriptName).joined(separator: ", "), privacy: .public)")
        request()
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryIfFailed() }
        }
    }

    /// What "Sync details" shows: "HannotateSC-W7 ready, HannotateSC-W5 downloading 40%".
    var summary: String {
        guard asked else { return "not needed yet" }
        return faces.map { face in
            let state: String = switch states[face.postScriptName] ?? .notAsked {
            case .notAsked: "not asked"
            case let .downloading(percent): "downloading \(percent)%"
            case .ready: "ready"
            case let .failed(reason): "failed (\(reason))"
            }
            return "\(face.postScriptName) \(state)"
        }.joined(separator: ", ")
    }

    func retryIfFailed(now: Date = .now) {
        guard asked, faces.contains(where: { if case .failed = states[$0.postScriptName] { true } else { false } }) else { return }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < 5 * 60 { return }
        request(now: now)
    }

    private func request(now: Date = .now) {
        lastAttempt = now
        for face in faces {
            let name = face.postScriptName
            if states[name] == .ready { continue }
            if isInstalled(name) {
                arrived(name, downloaded: false)
                continue
            }
            states[name] = .downloading(percent: 0)
            Self.log.info("Asking iOS for \(name, privacy: .public)")
            download(name) { [weak self] event in
                Task { @MainActor in self?.handle(event, for: name) }
            }
        }
    }

    private func handle(_ event: DownloadEvent, for name: String) {
        switch event {
        case let .progress(percent):
            if states[name] != .ready { states[name] = .downloading(percent: percent) }
        case let .failed(reason):
            states[name] = .failed(reason)
            Self.log.error("\(name, privacy: .public) didn't download: \(reason, privacy: .public)")
        case .finished:
            if case .failed = states[name] { return }  // Already said why.
            finish(name, checksLeft: 4)
        }
    }

    /// A face can take a moment after its download finishes before iOS makes it: look
    /// again a few times, a second apart, before calling it failed.
    private func finish(_ name: String, checksLeft: Int) {
        if isInstalled(name) {
            arrived(name, downloaded: true)
        } else if checksLeft > 0 {
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: self.recheck)
                self.finish(name, checksLeft: checksLeft - 1)
            }
        } else {
            states[name] = .failed("not on this device after downloading")
            Self.log.error("\(name, privacy: .public) isn't on this device after its download finished")
        }
    }

    private func arrived(_ name: String, downloaded: Bool) {
        states[name] = .ready
        readyLock.withLock { _ = $0.insert(name) }
        generation += 1
        Self.log.info("\(name, privacy: .public) is ready\(downloaded ? " (downloaded now)" : "", privacy: .public)")
    }

    /// Whether iOS can make the face now, without a download.
    nonisolated static func installed(_ name: String) -> Bool {
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == name
    }

    /// Asks iOS to download the face, reporting as it goes. The handler runs off the main
    /// thread and always lets the match go on; it ends with `.finished`.
    nonisolated static func requestDownload(_ name: String, report: @escaping @Sendable (DownloadEvent) -> Void) {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name] as CFDictionary)
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler([descriptor] as CFArray, nil) { state, progress in
            let info = progress as NSDictionary
            log.debug("\(name, privacy: .public): match state \(state.rawValue), \(info.allKeys.map { "\($0)" }.joined(separator: " "), privacy: .public)")
            switch state {
            case .downloading:
                if let percent = info[kCTFontDescriptorMatchingPercentage] as? Double { report(.progress(Int(percent))) }
            case .didFailWithError:
                let error = info[kCTFontDescriptorMatchingError] as? NSError
                report(.failed(error?.localizedDescription ?? "unknown error"))
            case .didFinish:
                report(.finished)
            default:
                break
            }
            return true
        }
    }
}
