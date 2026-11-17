import AppIntents
import SwiftUI
import WidgetKit

// The widget extension: it reads the summary the app writes into the app group, plans a
// timeline from it, and draws. It never opens the database; its buttons are App Intents
// that run in the app (docs/design/beyond-the-app.md).

@main
struct PorchlightWidgets: WidgetBundle {
    var body: some Widget {
        CompanionWidget()
        TodayWidget()
        GroceriesWidget()
        GlowWidget()
        ChoresLeftWidget()
    }
}

/// One timeline entry: what the widget shows at `date`.
struct MomentEntry: TimelineEntry {
    let date: Date
    let moment: WidgetMoment
    let timeZone: TimeZone
    var companionId: String?
}

/// Entries for the planned dates, each worked out from the summary at its own time.
enum MomentTimeline {
    static func entries(at dates: [Date], summary: WidgetSummary?, companionId: String? = nil) -> [MomentEntry] {
        let timeZone = summary?.household.flatMap { TimeZone(identifier: $0.timeZone) } ?? .current
        return dates.map { MomentEntry(date: $0, moment: .at($0, summary: summary), timeZone: timeZone, companionId: companionId) }
    }

    static func timeline(companionId: String? = nil) -> Timeline<MomentEntry> {
        let summary = WidgetSummaryFile.read()
        let dates = WidgetTimeline.dates(for: summary, from: .now)
        // After the last planned entry, ask again; the app also reloads whenever it writes.
        return Timeline(entries: entries(at: dates, summary: summary, companionId: companionId), policy: .atEnd)
    }

    static func placeholder() -> MomentEntry {
        MomentEntry(date: .now, moment: .at(.now, summary: WidgetPreviewData.summary(at: .now)), timeZone: .current)
    }
}

/// The widgets that need no setting.
struct MomentProvider: TimelineProvider {
    func placeholder(in context: Context) -> MomentEntry { MomentTimeline.placeholder() }

    func getSnapshot(in context: Context, completion: @escaping (MomentEntry) -> Void) {
        let summary = context.isPreview ? WidgetPreviewData.summary(at: .now) : WidgetSummaryFile.read()
        completion(MomentTimeline.entries(at: [.now], summary: summary)[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MomentEntry>) -> Void) {
        completion(MomentTimeline.timeline())
    }
}

/// The companion widget, configured with which companion it shows.
struct CompanionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MomentEntry { MomentTimeline.placeholder() }

    func snapshot(for configuration: SelectCompanionIntent, in context: Context) async -> MomentEntry {
        let summary = context.isPreview ? WidgetPreviewData.summary(at: .now) : WidgetSummaryFile.read()
        return MomentTimeline.entries(at: [.now], summary: summary, companionId: configuration.companion?.id)[0]
    }

    func timeline(for configuration: SelectCompanionIntent, in context: Context) async -> Timeline<MomentEntry> {
        MomentTimeline.timeline(companionId: configuration.companion?.id)
    }
}

/// The paper every home-screen widget sits on.
private extension View {
    func paper() -> some View {
        containerBackground(for: .widget) { Theme.surface }
    }

    func lockScreen() -> some View {
        containerBackground(for: .widget) { Color.clear }
    }
}

struct CompanionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.companion, intent: SelectCompanionIntent.self, provider: CompanionProvider()) { entry in
            CompanionFamilyView(entry: entry)
        }
        .configurationDisplayName("Companion")
        .description("One companion's care, with a button to log it. On the Lock Screen, the time since its last walk or meal.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct CompanionFamilyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomentEntry

    var body: some View {
        if family == .accessoryCircular {
            CompanionCircularView(moment: entry.moment, companionId: entry.companionId).lockScreen()
        } else {
            CompanionSmallView(moment: entry.moment, companionId: entry.companionId, timeZone: entry.timeZone)
                .paper()
                .widgetURL(WidgetLink.today)
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today, provider: MomentProvider()) { entry in
            TodayMediumView(moment: entry.moment, timeZone: entry.timeZone)
                .paper()
                .widgetURL(WidgetLink.today)
        }
        .configurationDisplayName("Today for you")
        .description("Care that's open now and your chores today, with buttons to log them.")
        .supportedFamilies([.systemMedium])
    }
}

struct GroceriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.groceries, provider: MomentProvider()) { entry in
            GroceriesSmallView(moment: entry.moment)
                .paper()
                .widgetURL(WidgetLink.lists)
        }
        .configurationDisplayName("Groceries")
        .description("What's on the grocery list.")
        .supportedFamilies([.systemSmall])
    }
}

struct GlowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.glow, provider: MomentProvider()) { entry in
            GlowRectangularView(moment: entry.moment).lockScreen()
        }
        .configurationDisplayName("Glow")
        .description("Your stars this week and the family goal.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct ChoresLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.choresLeft, provider: MomentProvider()) { entry in
            ChoresCircularView(moment: entry.moment).lockScreen()
        }
        .configurationDisplayName("Chores left")
        .description("How many of your chores are left today.")
        .supportedFamilies([.accessoryCircular])
    }
}
