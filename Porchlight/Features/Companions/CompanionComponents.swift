import SwiftUI

// Small building blocks shared by the companion card, page, sheet and lanes.

// MARK: - Navigation hook

/// Opens a companion's page. The wall provides it; without it, "See the week" is hidden.
///
///     .environment(\.openCompanion, OpenCompanionAction { selection = .companion($0) })
struct OpenCompanionAction {
    var open: @MainActor (Int64) -> Void

    @MainActor func callAsFunction(_ companionId: Int64) { open(companionId) }
}

private struct OpenCompanionKey: EnvironmentKey {
    static let defaultValue: OpenCompanionAction? = nil
}

extension EnvironmentValues {
    var openCompanion: OpenCompanionAction? {
        get { self[OpenCompanionKey.self] }
        set { self[OpenCompanionKey.self] = newValue }
    }
}

// MARK: - People marks

/// Who did something, resolved for drawing: one person or several together.
struct Carers: Equatable {
    var colors: [Color]
    var initials: [String]

    static let nobody = Carers(colors: [], initials: [])

    init(colors: [Color], initials: [String]) {
        self.colors = colors
        self.initials = initials
    }

    init(_ ids: [Int64], snapshot: CompanionSnapshot) {
        let people = ids.compactMap { snapshot.person($0) }
        colors = people.map(\.color.color)
        initials = people.map(\.initial)
    }

    var isTogether: Bool { colors.count > 1 }
    var single: Color { colors.first ?? Theme.everyone }
}

/// A person's avatar, or a gold ♥ when several people did it together.
struct CarerAvatar: View {
    var carers: Carers
    var size: CGFloat = 30

    var body: some View {
        if carers.isTogether {
            Avatar(initial: "♥", color: Theme.everyone, size: size)
        } else {
            Avatar(initial: carers.initials.first ?? "?", color: carers.single, size: size)
        }
    }
}

/// A round mark for one slot: the walker's color (split when together), or a dashed ghost.
struct PawDot: View {
    enum Content {
        /// The paw print.
        case paw
        /// The walker's initial, or ♥ when together.
        case initial
    }

    var carers: Carers?
    var size: CGFloat = 24
    var content: Content = .paw

    var body: some View {
        ZStack {
            if let carers {
                if carers.isTogether {
                    Circle().fill(AngularGradient(stops: splitStops(carers.colors), center: .center, angle: .degrees(-90)))
                } else {
                    Circle().fill(carers.single)
                }
                label(carers)
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func label(_ carers: Carers) -> some View {
        switch content {
        case .paw:
            Image(systemName: "pawprint.fill").font(.system(size: size * 0.5, weight: .semibold))
        case .initial:
            Text(carers.isTogether ? "♥" : (carers.initials.first ?? ""))
                .font(.body(size * 0.36, weight: 800))
        }
    }

    /// Hard-edged pie slices, clockwise from 12 o'clock, last walker first like the mock.
    private func splitStops(_ colors: [Color]) -> [Gradient.Stop] {
        let ordered = Array(colors.reversed())
        let step = 1 / Double(ordered.count)
        return ordered.enumerated().flatMap { index, color in
            [Gradient.Stop(color: color, location: Double(index) * step), Gradient.Stop(color: color, location: Double(index + 1) * step)]
        }
    }
}

/// The small grey circle with a paw used on pending slot tiles.
struct PendingPaw: View {
    var size: CGFloat = 30
    var color: Color = Theme.muted

    var body: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Theme.surface2, in: Circle())
    }
}

// MARK: - Slot tile

/// One slot on the Today card or the hero: done (walker avatar, tinted) or pending (dashed).
struct SlotTile: View {
    var slot: CareSlot
    /// "Morning" on Today, "AM" on the hero.
    var title: String
    var carers: Carers?
    /// The pending line, e.g. "5-8pm · James' turn".
    var pendingDetail: String
    /// The done line, e.g. "8:12 · 25 min · 💧💩".
    var doneDetail: String

    var body: some View {
        HStack(spacing: 10) {
            if let carers, slot.isDone {
                CarerAvatar(carers: carers)
            } else {
                PendingPaw(color: isNudging ? Theme.accent : Theme.muted)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.isDone ? "\(title) ✓" : title)
                    .font(.body(14, weight: 700))
                    .foregroundStyle(Theme.ink)
                Text(slot.isDone ? doneDetail : pendingDetail)
                    .font(.body(12.5, weight: 600))
                    .foregroundStyle(isNudging ? Theme.accent : Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(background)
    }

    private var isNudging: Bool { slot.state == .due || slot.state == .late }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
        if slot.isDone {
            shape.fill((carers?.isTogether == true ? Theme.everyone : carers?.single ?? Theme.everyone).wash(0.15))
        } else {
            shape.fill(Theme.surface)
                .overlay(shape.strokeBorder(isNudging ? Theme.accent.opacity(0.7) : Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
    }
}

// MARK: - Text helpers

enum CareText {
    /// "James' turn".
    static func turn(_ name: String) -> String {
        name.hasSuffix("s") ? "\(name)' turn" : "\(name)'s turn"
    }

    /// "8:12".
    static func time(_ date: Date, calendar: Calendar) -> String {
        ClockFormat.time(date, calendar: calendar)
    }

    /// "8:12am".
    static func timeWithPeriod(_ date: Date, calendar: Calendar) -> String {
        CareTime.hour(CareLogic.minuteOfDay(date, calendar: calendar))
    }

    /// "💧💩" for what was logged.
    static func business(_ log: CareLog, spaced: Bool = false) -> String {
        [log.pee == true ? "💧" : nil, log.poo == true ? "💩" : nil].compactMap { $0 }.joined(separator: spaced ? " " : "")
    }

    /// "8:12 · 25 min · 💧💩".
    static func doneDetail(_ entry: CareEntry, calendar: Calendar, includeTime: Bool = true) -> String {
        var parts: [String] = []
        if includeTime { parts.append(time(entry.time, calendar: calendar)) }
        if let minutes = entry.log.durationMinutes { parts.append("\(minutes) min") }
        let business = business(entry.log)
        if !business.isEmpty { parts.append(business) }
        return parts.joined(separator: " · ")
    }

    /// "1h ago", "25 min ago", "just now", "2 days ago".
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(max(now.timeIntervalSince(date), 0) / 60)
        switch minutes {
        case ..<2: return "just now"
        case ..<60: return "\(minutes) min ago"
        case ..<(48 * 60): return "\(minutes / 60)h ago"
        default: return "\(minutes / (24 * 60)) days ago"
        }
    }

    /// Short slot labels for the trail and hero: AM/PM when a routine has one morning and one evening window.
    static func shortLabels(_ windows: [CareWindow]) -> [String] {
        if windows.count == 2, windows[0].end <= 12 * 60 + 60, windows[1].start >= 12 * 60 {
            return ["AM", "PM"]
        }
        if windows.count == 1 { return [windows[0].isAllDay ? "Due" : String(windows[0].label.prefix(3))] }
        return windows.map { String($0.label.prefix(3)) }
    }
}

// MARK: - Pills

/// A selectable pill for the log sheet and editors (dark when selected, like the mock).
struct ChoicePill: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body(14.5, weight: 700))
                .foregroundStyle(isSelected ? Theme.surface : Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? Theme.ink : Theme.surface2, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A rounded card header row: serif title and a muted meta on the right.
struct CardHeader: View {
    var title: String
    var meta: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.display(19))
            Spacer(minLength: 8)
            if let meta {
                Text(meta)
                    .font(.body(13, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.ink)
    }
}
