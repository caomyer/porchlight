import BackgroundTasks
import Foundation

/// Passes this device's calendars on from a background refresh, when iOS grants one
/// (docs/design/calendar-shared.md, "Passing on"), so a phone that isn't opened keeps the
/// wall and the other phones up to date as often as iOS allows. Each run asks for the next.
enum CalendarPassOnRefresh {
    static let identifier = "com.mingyucao.porchlight.calendar.passOn"
    /// The soonest a refresh is asked for after the last one.
    static let interval: TimeInterval = 3600

    /// Registers the refresh; must run before the app finishes launching.
    static func register() {
        BackgroundRefresh.register(identifier) {
            schedule()
            CalendarStore.shared?.passOn(.background)
            // What the pass wrote goes up before iOS suspends the app again.
            _ = await SyncController.current?.sendSoon(timeout: .seconds(25))
            return true
        }
    }

    /// Asks for the next refresh, an hour from now at the soonest; asking again replaces
    /// the earlier ask. The simulator refuses, which changes nothing.
    static func schedule(now: Date = .now) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = now.addingTimeInterval(interval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
