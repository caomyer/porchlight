import Foundation

/// What the widgets draw, written by the app into the app group for the widget extension
/// to read (docs/design/beyond-the-app.md, "The summary"). Small, versioned, never a photo.
///
/// This file is compiled into the app and the widget extension, so it uses plain types only.
struct WidgetSummary: Codable, Equatable, Sendable {
    /// Bump when the format changes in a way an older widget can't read.
    static let currentVersion = 1

    var version = WidgetSummary.currentVersion
    var writtenAt: Date
    /// Written by a shared screen, whose widgets only say they are for someone's own phone.
    var isSharedScreen = false
    /// Nil when this phone has no household yet.
    var household: HouseholdInfo?
    /// Nil when this phone hasn't said who it belongs to.
    var me: Me?
    /// The days the summary covers, "yyyy-MM-dd", today first.
    var days: [String] = []
    var companions: [CompanionInfo] = []
    var chores: [Chore] = []
    var glow: Glow?
    var groceries: Groceries?

    struct HouseholdInfo: Codable, Equatable, Sendable {
        var name: String
        var timeZone: String
    }

    struct Me: Codable, Equatable, Sendable {
        var name: String
        /// 0xRRGGBB.
        var color: UInt32
    }

    struct CompanionInfo: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var face: String
        var routines: [Routine]
        /// When its main routine was last done, for "9h since the last walk".
        var lastCare: Date?

        struct Routine: Codable, Equatable, Sendable, Identifiable {
            var id: String
            var title: String
            var emoji: String
            /// What the log button says: "Walked", "Fed".
            var doneWord: String
            var slots: [Slot]
        }
    }

    /// One slot of a routine on one day.
    struct Slot: Codable, Equatable, Sendable {
        var day: String
        var index: Int
        /// "evening walk".
        var name: String
        /// Minutes after midnight; an all-day slot runs 0 to 1440.
        var start: Int
        var end: Int
        /// Who logged it and when, when someone did.
        var doneBy: String?
        var doneAt: Date?

        var isDone: Bool { doneAt != nil }
    }

    struct Chore: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var day: String
        var title: String
        var emoji: String?
        var stars: Int
        var done: Bool
    }

    struct Glow: Codable, Equatable, Sendable {
        var myStarsThisWeek: Int
        var goalTitle: String?
        var goalEmoji: String?
        var goalEarned: Int
        var goalTarget: Int
    }

    struct Groceries: Codable, Equatable, Sendable {
        var listId: String
        var title: String
        var count: Int
        var firstItems: [String]
    }

    /// The same summary, as if written at another time: what "changed" ignores.
    func written(at date: Date) -> WidgetSummary {
        var copy = self
        copy.writtenAt = date
        return copy
    }
}

/// Where the summary lives: the app group's container, shared by the app and its widgets.
enum WidgetSummaryFile {
    static let appGroup = "group.com.mingyucao.porchlight"
    static let fileName = "widget-summary.json"

    /// The shared file, or nil in a build without the app group (tests, unsigned builds).
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func encode(_ summary: WidgetSummary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(summary)
    }

    /// The summary in `data`, or nil when it can't be read or is from a version this build
    /// doesn't know: a widget then asks to open the app rather than guessing.
    static func decode(_ data: Data) -> WidgetSummary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let summary = try? decoder.decode(WidgetSummary.self, from: data),
              summary.version == WidgetSummary.currentVersion else { return nil }
        return summary
    }

    static func read(from url: URL? = WidgetSummaryFile.url) -> WidgetSummary? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
}
