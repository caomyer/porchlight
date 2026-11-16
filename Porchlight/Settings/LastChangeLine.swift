import SwiftUI

/// "Last change 2 min ago, from Mia's phone": the newest thing another device wrote, under
/// the sync switch (journey D2). Nothing until another device has written something.
struct LastChangeLine: View {
    @Environment(AppModel.self) private var model
    @State private var change: LastChange?

    var body: some View {
        Group {
            if let change, let from = source(of: change) {
                TimelineView(.everyMinute) { context in
                    Text("Last change \(Self.ago(change.at, now: context.date)), \(from)")
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("last-change")
                }
            }
        }
        .task(id: model.thisDeviceId) {
            do {
                for try await latest in model.database.lastChangeUpdates(excluding: model.thisDeviceId) {
                    change = latest
                }
            } catch {}
        }
    }

    /// "from Mia's phone", or the device's name for a shared screen.
    private func source(of change: LastChange) -> String? {
        if let tag = model.tag(for: change.deviceId) { return tag }
        return model.devices.first { $0.id == change.deviceId }.map { "from \($0.name)" }
    }

    /// "just now", "2 min ago", "3 hours ago", "on Nov 12".
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes) min ago"
        case ..<(24 * 60):
            let hours = minutes / 60
            return hours == 1 ? "an hour ago" : "\(hours) hours ago"
        default: return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}
