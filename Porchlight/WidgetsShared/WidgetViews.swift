import AppIntents
import SwiftUI
import WidgetKit

// What each widget draws, from a `WidgetMoment` alone. Compiled into the app too, so unit
// tests render every family to PNG (`WidgetRenderTests`); nothing here reads the database.

/// The widgets' kinds, shared by the extension's configurations and the app's reloads.
enum WidgetKind {
    static let companion = "Companion"
    static let today = "TodayForYou"
    static let groceries = "Groceries"
    static let glow = "Glow"
    static let choresLeft = "ChoresLeft"
}

/// Where a widget's tap takes the app.
enum WidgetLink {
    static let lists = URL(string: "porchlight://lists")!
    static let today = URL(string: "porchlight://today")!
}

// MARK: - Type

extension View {
    /// The app's faces, growing with the reader's text size but only so far: a widget's
    /// box never grows, so the words shrink to fit before they are cut.
    func widgetFont(_ face: Typeface, _ size: CGFloat, weight: CGFloat = 400) -> some View {
        modifier(WidgetFont(face: face, size: size, weight: weight))
    }
}

private struct WidgetFont: ViewModifier {
    let face: Typeface
    let size: CGFloat
    let weight: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.font(.custom(face, size: size * scale, weight: weight))
    }

    private var scale: CGFloat {
        switch typeSize {
        case .xSmall, .small: 0.92
        case .medium, .large: 1
        case .xLarge: 1.06
        case .xxLarge: 1.12
        case .xxxLarge: 1.18
        default: 1.24
        }
    }
}

// MARK: - When there is nothing to show

/// The one line a widget shows instead of the household.
struct WidgetNotice: View {
    let availability: WidgetMoment.Availability
    var compact = false

    static func text(_ availability: WidgetMoment.Availability) -> String? {
        switch availability {
        case .missing: "Open Porchlight once to see today here."
        case .sharedScreen: "Porchlight widgets are for your own phone."
        case .noHousehold: "Join or start a household in Porchlight."
        case .noMe: "Open Porchlight and say who you are."
        case .beyondSummary: "Open Porchlight to see today."
        case .ready: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "house")
                .font(.system(size: compact ? 14 : 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(Self.text(availability) ?? "")
                .widgetFont(.body, compact ? 12 : 14, weight: 600)
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "As of 5:40 pm" under a widget whose summary is old.
private struct AsOfLine: View {
    let moment: WidgetMoment
    let timeZone: TimeZone

    var body: some View {
        if let asOf = moment.asOf {
            Text("As of \(WidgetWords.clock(asOf, timeZone: timeZone))")
                .widgetFont(.body, 11, weight: 600)
                .foregroundStyle(Theme.warnInk)
        }
    }
}

// MARK: - Companion, small

/// One companion: its open slot with the log button, or who did the last one, or what's next.
struct CompanionSmallView: View {
    let moment: WidgetMoment
    var companionId: String?
    var timeZone: TimeZone = .current

    var body: some View {
        if moment.availability != .ready {
            WidgetNotice(availability: moment.availability)
        } else if let card = moment.companion(companionId) {
            content(card)
        } else {
            empty
        }
    }

    private func content(_ card: WidgetMoment.CompanionCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(card.face)
                    .font(.system(size: 20))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surface2))
                Text(card.name)
                    .widgetFont(.display, 19, weight: 600)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            detail(card)
            Spacer(minLength: 8)
            footer(card)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func detail(_ card: WidgetMoment.CompanionCard) -> some View {
        switch card.care {
        case let .open(_, _, _, name, _, _, start, end):
            lines(name.capitalizedFirst, WidgetWords.window(start, end), tint: Theme.accent)
        case let .done(name, by, at):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name.capitalizedFirst) ✓")
                    .widgetFont(.body, 13.5, weight: 700)
                    .foregroundStyle(Theme.goodInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 0) {
                    if let by {
                        Text("by \(by) ").privacySensitive()
                    }
                    Text("at \(WidgetWords.clock(at, timeZone: timeZone))")
                }
                .widgetFont(.body, 12.5)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        case let .next(name, start):
            lines(name.capitalizedFirst, "Opens at \(WidgetWords.time(start))", tint: Theme.ink)
        case .allSet:
            lines("All set today", card.minutesSinceCare.map { "Last care \(WidgetWords.since($0)) ago" } ?? "Nothing more due", tint: Theme.goodInk)
        }
    }

    private func lines(_ title: String, _ subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .widgetFont(.body, 13.5, weight: 700)
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .widgetFont(.body, 12.5)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private func footer(_ card: WidgetMoment.CompanionCard) -> some View {
        if case let .open(routineId, slot, day, _, emoji, doneWord, _, _) = card.care {
            Button(intent: LogSlotIntent(routineId: routineId, slot: slot, day: day)) {
                Text("\(emoji) \(doneWord)")
                    .widgetFont(.body, 14, weight: 700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(Theme.accentInk)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("widget-log")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                if case .done = card.care, let upcoming = card.upcoming {
                    Text("Next: \(upcoming.name) at \(WidgetWords.time(upcoming.start))")
                        .widgetFont(.body, 12, weight: 600)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                AsOfLine(moment: moment, timeZone: timeZone)
            }
        }
        if case .open = card.care {
            AsOfLine(moment: moment, timeZone: timeZone)
                .padding(.top, 3)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🐾").font(.system(size: 22))
            Text("Add a companion in Porchlight to see its care here.")
                .widgetFont(.body, 13, weight: 600)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Companion, Lock Screen

/// "🐶 9h": the time since a companion's main routine was last done.
struct CompanionCircularView: View {
    let moment: WidgetMoment
    var companionId: String?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if moment.availability == .ready, let card = moment.companion(companionId) {
                    Text(card.face).font(.system(size: 20))
                    Text(card.minutesSinceCare.map(WidgetWords.since) ?? "–")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .widgetAccentable()
                } else {
                    Image(systemName: "house").font(.system(size: 18, weight: .semibold))
                    Text("Open").font(.system(size: 11, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Today for you, medium

/// The open care with its button, then my chores today with check boxes.
struct TodayMediumView: View {
    let moment: WidgetMoment
    var timeZone: TimeZone = .current

    /// How many rows fit at the usual text size.
    static let rows = 3

    private var openCare: [(WidgetMoment.CompanionCard, routineId: String, slot: Int, day: String, name: String, emoji: String)] {
        moment.companions.compactMap { card in
            if case let .open(routineId, slot, day, name, emoji, _, _, _) = card.care {
                return (card, routineId, slot, day, name, emoji)
            }
            return nil
        }
    }

    var body: some View {
        if moment.availability != .ready {
            WidgetNotice(availability: moment.availability)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(moment.isOneOfSeveral ? moment.householdName ?? "Today at home" : "Today at home")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetFont(.display, 17, weight: 600)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if let name = moment.meName {
                        Text(name)
                            .widgetFont(.body, 12.5, weight: 700)
                            .foregroundStyle(moment.meColor.map { Color(hex: $0) } ?? Theme.muted)
                            .privacySensitive()
                    }
                }
                rows
                Spacer(minLength: 0)
                HStack {
                    if moment.starsToday > 0 {
                        Text("+\(moment.starsToday) ★ today")
                            .widgetFont(.body, 12, weight: 700)
                            .foregroundStyle(Theme.warnInk)
                    }
                    Spacer()
                    AsOfLine(moment: moment, timeZone: timeZone)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var rows: some View {
        let care = Array(openCare.prefix(Self.rows))
        let chores = Array(moment.chores.prefix(Self.rows - care.count))
        if care.isEmpty && chores.isEmpty {
            Text("Nothing waiting for you today.")
                .widgetFont(.body, 13.5, weight: 600)
                .foregroundStyle(Theme.goodInk)
        }
        ForEach(care, id: \.routineId) { item in
            HStack(spacing: 8) {
                Text(item.emoji).font(.system(size: 15))
                Text("\(item.0.name)'s \(item.name)")
                    .widgetFont(.body, 13.5, weight: 600)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button(intent: LogSlotIntent(routineId: item.routineId, slot: item.slot, day: item.day)) {
                    Text("Log")
                        .widgetFont(.body, 13, weight: 700)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accent))
                        .foregroundStyle(Theme.accentInk)
                }
                .buttonStyle(.plain)
            }
        }
        ForEach(chores) { chore in
            HStack(spacing: 8) {
                Button(intent: CheckChoreIntent(choreId: chore.id, day: chore.day)) {
                    Image(systemName: chore.done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(chore.done ? Theme.good : Theme.muted)
                }
                .buttonStyle(.plain)
                .disabled(chore.done)
                Text([chore.emoji, chore.title].compactMap { $0 }.joined(separator: " "))
                    .widgetFont(.body, 13.5, weight: 600)
                    .foregroundStyle(chore.done ? Theme.muted : Theme.ink)
                    .strikethrough(chore.done)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                Spacer(minLength: 4)
                if chore.stars > 0 {
                    Text("+\(chore.stars)")
                        .widgetFont(.body, 12, weight: 700)
                        .foregroundStyle(Theme.warnInk)
                }
            }
        }
    }
}

// MARK: - Groceries, small

/// The list's count and first items; "+ Add" opens Lists in the app.
struct GroceriesSmallView: View {
    let moment: WidgetMoment

    var body: some View {
        if moment.availability != .ready {
            WidgetNotice(availability: moment.availability)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(moment.groceries?.title ?? "Groceries")
                    .widgetFont(.display, 18, weight: 600)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(countText)
                    .widgetFont(.body, 12.5, weight: 700)
                    .foregroundStyle(Theme.muted)
                if let items = moment.groceries?.firstItems, !items.isEmpty {
                    Text(items.joined(separator: ", ") + ((moment.groceries?.count ?? 0) > items.count ? "…" : ""))
                        .widgetFont(.body, 13)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .privacySensitive()
                }
                Spacer(minLength: 4)
                Link(destination: WidgetLink.lists) {
                    Text("+ Add")
                        .widgetFont(.body, 14, weight: 700)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().stroke(Theme.line, lineWidth: 1.5))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var countText: String {
        guard let count = moment.groceries?.count else { return "No list yet" }
        return count == 0 ? "All bought" : count == 1 ? "1 item" : "\(count) items"
    }
}

// MARK: - Glow, Lock Screen

/// "✨ Glow 23 · Pizza 72/80": my stars this week and the family goal.
struct GlowRectangularView: View {
    let moment: WidgetMoment

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if moment.availability == .ready, let glow = moment.glow {
                Text("✨ \(glow.myStarsThisWeek) \(glow.myStarsThisWeek == 1 ? "star" : "stars") this week")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let goal = glow.goalTitle, glow.goalTarget > 0 {
                    Text("\(glow.goalEmoji ?? "🎯") \(goal) \(glow.goalEarned)/\(glow.goalTarget)")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text("✨ Glow")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text(WidgetNotice.text(moment.availability) ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chores left, Lock Screen

/// "☑️ 1 left": my chores still to do today.
struct ChoresCircularView: View {
    let moment: WidgetMoment

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if moment.availability == .ready {
                    Image(systemName: moment.choresLeft == 0 ? "checkmark.circle" : "checklist")
                        .font(.system(size: 16, weight: .semibold))
                        .widgetAccentable()
                    Text(moment.choresLeft == 0 ? "done" : "\(moment.choresLeft) left")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: "house").font(.system(size: 18, weight: .semibold))
                    Text("Open").font(.system(size: 11, weight: .semibold))
                }
            }
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
