import Foundation

/// Helpers for decorative motion that plays now and then instead of looping forever.
///
/// The wall is always on, and its ProMotion screen redraws 120 times a second while anything
/// animates. A loop that never ends keeps the app and the render server busy all day, so
/// idle flourishes play a couple of times, then rest until the next minute.
enum Restful {
    /// Phases for `phaseAnimator`: there and back twice, ending where it started.
    static let twice = [false, true, false, true]

    /// Runs `action` now, then once a minute until the task is cancelled.
    @MainActor
    static func everyMinute(_ action: @MainActor () -> Void) async {
        while !Task.isCancelled {
            action()
            try? await Task.sleep(for: .seconds(60))
        }
    }
}
