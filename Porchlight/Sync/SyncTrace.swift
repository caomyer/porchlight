import Foundation
import Observation
import os

/// What sync is doing, for "Sync details" in Settings and for the log
/// (docs/design/sync-icloud.md, "Seeing what sync does").
///
/// It is its own observable object: only the details, when someone opens them, read it, so
/// a check every 15 seconds never redraws the status anywhere else.
@MainActor
@Observable
final class SyncTrace: StoredFirstObservable {
    enum Activity: String, Sendable {
        case active, inactive
    }

    /// One check, as it ended.
    struct Check: Equatable, Sendable {
        var at: Date
        var outcome: String
        var milliseconds: Int
    }

    @ObservationIgnored @StoredFirst var role: DeviceRole? = nil
    @ObservationIgnored @StoredFirst var isActive = false
    /// What last said the app is in front or not: a notification, or the state read directly.
    @ObservationIgnored @StoredFirst var activitySource = "not yet"
    @ObservationIgnored @StoredFirst var isOnline = true
    @ObservationIgnored @StoredFirst var engineRunning = false
    /// "available", "none", or "not checked yet".
    @ObservationIgnored @StoredFirst var account = "not checked yet"
    @ObservationIgnored @StoredFirst var lastCheck: Check? = nil
    /// What started the last check: a push, the timer, coming to the front…
    @ObservationIgnored @StoredFirst var lastTrigger: String? = nil
    /// What the last check brought: "nothing new (timer)", "push, engine fetch, 149 to 150 rows".
    @ObservationIgnored @StoredFirst var received: String? = nil
    /// What the last probe of iCloud said, database by database.
    @ObservationIgnored @StoredFirst var lastProbe: String? = nil
    /// Engine restarts because a fetch brought nothing iCloud said was there.
    @ObservationIgnored @StoredFirst var restarts = 0
    /// Times this launch asked for a push token.
    @ObservationIgnored @StoredFirst var tokenRequests = 0
    @ObservationIgnored @StoredFirst var pushes = 0
    @ObservationIgnored @StoredFirst var lastPush: Date? = nil
    /// "arrived (length 32)", "failed: …", or "not yet".
    @ObservationIgnored @StoredFirst var pushToken = "not yet"
    @ObservationIgnored @StoredFirst var registeredForPushes = false
    @ObservationIgnored @StoredFirst var backgroundRefresh = "unknown"
    @ObservationIgnored @StoredFirst var lowPowerMode = false
    @ObservationIgnored @StoredFirst var checks = 0
    @ObservationIgnored @StoredFirst var failuresInRow = 0
    @ObservationIgnored @StoredFirst var lastError: String? = nil
    @ObservationIgnored @StoredFirst var nextCheckAt: Date? = nil
    /// Records iCloud refused that this device kept and sent again, since it was set up:
    /// kept across launches, so a person can read them to us days later.
    @ObservationIgnored @StoredFirst var deferrals = SyncDeferrals()

    @ObservationIgnored let log: SyncLog
    @ObservationIgnored let defaults: UserDefaults

    init(log: SyncLog = .shared, defaults: UserDefaults = .standard) {
        self.log = log
        self.defaults = defaults
        deferrals = SyncDeferrals(defaults: defaults)
    }

    /// A record iCloud refused, kept here and queued to be sent again.
    func noteDeferred(recordType: String, waitingForParent: Bool, at date: Date = .now) {
        deferrals.note(recordType: recordType, waitingForParent: waitingForParent, at: date)
        deferrals.save(to: defaults)
        note("deferred \(recordType): \(waitingForParent ? "waiting for its parent" : "refused by iCloud"), sent again later")
    }

    /// Notes a line in the log; the screen shows the fields above.
    func note(_ line: String) {
        log.write(line)
    }
}

/// The sync log: os.Logger (subsystem com.mingyucao.porchlight, category sync), and a
/// rolling text file in the data folder that can be copied off a device. Lines hold only
/// states, counts, record types and error codes, never anything a family wrote.
final class SyncLog: Sendable {
    static let fileName = "sync-log.txt"
    static let shared = SyncLog(file: AppFiles.root.appendingPathComponent(fileName))

    /// The file keeps about this many lines.
    let keep: Int
    let file: URL?
    private let logger = Logger(subsystem: "com.mingyucao.porchlight", category: "sync")
    private let queue = DispatchQueue(label: "com.mingyucao.porchlight.sync-log")

    /// - Parameter file: Nil writes only to os.Logger (sample data never writes a file).
    init(file: URL?, keep: Int = 400) {
        self.file = AppFiles.isSandboxed ? nil : file
        self.keep = keep
    }

    /// For tests: a file wherever they say, even in a sandboxed launch.
    init(testFile: URL, keep: Int) {
        file = testFile
        self.keep = keep
    }

    func write(_ line: String, at date: Date = .now) {
        logger.log("\(line, privacy: .public)")
        guard let file else { return }
        let stamped = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)) + " " + line + "\n"
        let keep = keep
        queue.async {
            Self.append(stamped, to: file, keep: keep)
        }
    }

    /// Waits for every write so far; tests read the file after it.
    func flush() {
        queue.sync {}
    }

    private static func append(_ text: String, to file: URL, keep: Int) {
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file)
        }
        // Trim now and then, not on every line: once the file is half again as long as kept.
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        guard size > keep * 150 else { return }
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > keep else { return }
        let kept = lines.suffix(keep).joined(separator: "\n") + "\n"
        try? Data(kept.utf8).write(to: file, options: .atomic)
    }
}

extension Error {
    /// "CKError 4 (networkFailure)", "CKError 2 (partialFailure: 12, 12)": the codes only.
    var syncDescription: String {
        let error = self as NSError
        guard error.domain == "CKErrorDomain" else {
            if self is CancellationError { return "cancelled" }
            return "\(error.domain) \(error.code)"
        }
        var text = "CKError \(error.code)"
        if let partial = error.userInfo["CKPartialErrors"] as? [AnyHashable: Error] {
            let codes = partial.values.map { "\(($0 as NSError).code)" }.sorted()
            text += " (partial: \(codes.prefix(5).joined(separator: ", ")))"
        }
        if let retry = error.userInfo["CKRetryAfter"] as? NSNumber {
            text += " retry after \(retry)s"
        }
        return text
    }
}
