import BackgroundTasks
import Foundation
import Observation
import UIKit
import WidgetKit

/// Keeps the widgets' summary in step with the household (docs/design/beyond-the-app.md,
/// "When it is rewritten"). It looks again a second after the stores change (a log here,
/// a widget or Siri log, anything sync delivers), when "me" or the role changes, when the
/// day turns, and when iOS gives the app background time. It writes only when the summary
/// differs, and only then asks the widgets to reload.
///
/// A shared screen only marks the file once as a shared screen's and then watches nothing
/// but its role, so an idle wall does no work for widgets.
@MainActor
final class WidgetSummaryKeeper {
    /// The keeper of this launch, for background work that has no view.
    private(set) static var shared: WidgetSummaryKeeper?

    static let backgroundTask = "com.mingyucao.porchlight.widgets.refresh"

    private let database: AppDatabase
    private let companions: CompanionStore
    private let home: HomeStore
    private let device: DeviceSettings
    private let file: URL?
    private let clock: () -> Date
    private let didWrite: (WidgetSummary) -> Void
    private var task: Task<Void, Never>?
    private var activeTask: Task<Void, Never>?

    init(
        database: AppDatabase, companions: CompanionStore, home: HomeStore, device: DeviceSettings,
        file: URL? = WidgetSummaryFile.url, clock: @escaping () -> Date = CompanionClock.now,
        didWrite: @escaping (WidgetSummary) -> Void = WidgetSummaryKeeper.announce
    ) {
        self.database = database
        self.companions = companions
        self.home = home
        self.device = device
        self.file = file
        self.clock = clock
        self.didWrite = didWrite
    }

    /// Starts this launch's keeper. A build without the app group (tests, unsigned builds)
    /// has nowhere to write, so it starts nothing.
    static func start(database: AppDatabase, companions: CompanionStore, home: HomeStore, device: DeviceSettings) {
        guard WidgetSummaryFile.url != nil else { return }
        let keeper = WidgetSummaryKeeper(database: database, companions: companions, home: home, device: device)
        shared = keeper
        keeper.start()
    }

    func start() {
        task?.cancel()
        activeTask?.cancel()
        // Coming to the front looks again, so "As of" never lingers on an open app.
        activeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification).map({ _ in () }) {
                await self?.refresh()
            }
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Watch before looking, so a change while it looks is never missed.
                let changed = self.nextChange()
                await self.refresh()
                for await _ in changed { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        activeTask?.cancel()
        activeTask = nil
    }

    /// Fires once when anything the summary depends on changes.
    private func nextChange() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        withObservationTracking {
            guard device.role == .personal else { return }
            _ = companions.snapshot
            _ = home.snapshot
            _ = home.today
            if let household = companions.snapshot.household { _ = device.me(in: household.id) }
        } onChange: {
            continuation.yield()
            continuation.finish()
        }
        return stream
    }

    /// Builds the summary from the database and writes it if it changed. Returns whether
    /// it wrote.
    @discardableResult
    func refresh() async -> Bool {
        guard let file else { return false }
        let now = clock()
        let role = device.role
        let summary: WidgetSummary
        if role == .personal {
            guard let (companionSnapshot, homeSnapshot, households) = try? await database.writer.read({ db in
                let companions = try CompanionSnapshot.fetch(db)
                let calendar = companions.calendar
                let week = HomeWeek(containing: DayKey(now, calendar: calendar), calendar: calendar)
                return (companions, try HomeSnapshot.fetch(db, since: week.first), try Household.fetchCount(db))
            }) else { return false }
            let me = companionSnapshot.household.flatMap { device.me(in: $0.id) }
            summary = WidgetSummaryBuilder.make(companions: companionSnapshot, home: homeSnapshot, me: me, role: role, now: now, households: households)
            scheduleBackgroundRefresh(after: now, timeZone: companionSnapshot.calendar.timeZone)
        } else {
            summary = WidgetSummaryBuilder.make(companions: .empty, home: .empty, me: nil, role: role, now: now)
        }
        guard WidgetSummaryWrite.isNeeded(summary, over: WidgetSummaryFile.read(from: file)) else { return false }
        guard (try? WidgetSummaryFile.encode(summary).write(to: file, options: .atomic)) != nil else { return false }
        didWrite(summary)
        return true
    }

    /// Asks every widget to draw again, and Siri to learn the companions' names.
    nonisolated static func announce(_ summary: WidgetSummary) {
        WidgetCenter.shared.reloadAllTimelines()
        PorchlightShortcuts.updateAppShortcutParameters()
    }

    // MARK: Background refresh

    /// Registers the background refresh; must run before the app finishes launching.
    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTask, using: nil) { task in
            let done = UncheckedTask(task: task)
            Task { @MainActor in
                await shared?.refresh()
                done.task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { done.task.setTaskCompleted(success: false) }
        }
    }

    /// Asks for background time just after the next midnight, so tomorrow becomes today in
    /// the widgets even when the app isn't opened. Asking again replaces the earlier ask.
    private func scheduleBackgroundRefresh(after now: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTask)
        request.earliestBeginDate = midnight
        // The simulator and builds without the background mode refuse; the widgets then
        // turn over when the app next runs, and say "Open Porchlight to see today" meanwhile.
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// The task, carried to the main actor where it is completed.
private struct UncheckedTask: @unchecked Sendable {
    let task: BGTask
}

/// When a summary is worth writing. Pure, covered by `WidgetSummaryKeeperTests`.
enum WidgetSummaryWrite {
    /// How old a summary on disk may be before the same contents are written again, so a
    /// widget's "As of" reflects when the app last looked, not when something last changed.
    static let freshness: TimeInterval = 3600

    static func isNeeded(_ summary: WidgetSummary, over old: WidgetSummary?) -> Bool {
        guard let old else { return true }
        if old.written(at: summary.writtenAt) != summary { return true }
        // A shared screen's marker never goes stale.
        if summary.isSharedScreen { return false }
        return summary.writtenAt.timeIntervalSince(old.writtenAt) >= freshness
    }
}
