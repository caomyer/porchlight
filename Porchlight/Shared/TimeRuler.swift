import SwiftUI

// The app's own time picker: the time shows as a pill in the serif numerals of
// Today's clock, and tapping it opens a ruler of the day in place, with the
// usual times shaded (meals, or a routine's windows) and later than allowed
// hatched. Replaces the system's gray time box and floating wheel.

/// A shaded stretch of the day on the ruler, e.g. dinner 5-10pm. Minutes from midnight.
struct TimeBand: Equatable {
    var label: String
    var start: Int
    var end: Int
    var color: Color

    static let colors = [Color(hex: 0xF3DFB0), Color(hex: 0xDCE9C9), Color(hex: 0xF0CDBE), Color(hex: 0xE6DCEC)]

    /// The diary's meals at their usual times, in the order they are enabled.
    static func meals(_ slots: [String]) -> [TimeBand] {
        let tints: [String: Color] = ["Breakfast": colors[0], "Lunch": colors[1], "Dinner": colors[2], "Snack": colors[3]]
        return slots.compactMap { name in
            let slot = MealSlot.named(name)
            guard let window = slot.window else { return nil }
            return TimeBand(label: slot.name, start: window.lowerBound, end: window.upperBound, color: tints[slot.name] ?? colors[3])
        }
    }

    /// A routine's windows; a single all-day window shades nothing.
    static func windows(_ windows: [CareWindow]) -> [TimeBand] {
        let warm = [colors[0], colors[2], colors[1], colors[3]]
        return windows.enumerated().compactMap { index, window in
            guard window.end - window.start < 20 * 60 else { return nil }
            return TimeBand(label: window.label, start: window.start, end: window.end, color: warm[index % warm.count])
        }
    }
}

/// Clock text for the pill and the ruler: "7:12" and "PM".
enum ClockText {
    static func parts(_ date: Date, calendar: Calendar) -> (time: String, period: String) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        return ("\((hour + 11) % 12 + 1):\(String(format: "%02d", minute))", hour < 12 ? "AM" : "PM")
    }

    static func spoken(_ date: Date, calendar: Calendar) -> String {
        let parts = parts(date, calendar: calendar)
        return "\(parts.time) \(parts.period)"
    }
}

/// The picked time as one of the app's pills. Tapping it opens or closes the ruler.
struct TimePill: View {
    let date: Date
    @Binding var isOpen: Bool
    var calendar: Calendar = .current
    let accessibilityLabel: String
    let identifier: String

    var body: some View {
        let parts = ClockText.parts(date, calendar: calendar)
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(parts.time)
                    .font(.display(19))
                    .monospacedDigit()
                Text(parts.period)
                    .font(.body(12, weight: 700))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 7)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOpen ? Theme.accent : Theme.line, lineWidth: isOpen ? 2 : 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(ClockText.spoken(date, calendar: calendar))
        .accessibilityHint(isOpen ? "Closes the day ruler" : "Opens a ruler of the day to pick the time")
        .accessibilityIdentifier(identifier)
    }
}

/// A ruler of the day: drag along it, or nudge by five minutes. Times outside
/// `range` are hatched and out of reach.
struct DayRuler: View {
    @Binding var date: Date
    let range: ClosedRange<Date>
    var bands: [TimeBand] = []
    var calendar: Calendar = .current
    let accessibilityLabel: String
    let onDone: () -> Void

    static let step = 5

    private var dayStart: Date { calendar.startOfDay(for: range.lowerBound) }

    private func minute(of date: Date) -> Int {
        Int((date.timeIntervalSince(dayStart) / 60).rounded())
    }

    private func date(at minute: Int) -> Date {
        dayStart.addingTimeInterval(Double(minute) * 60)
    }

    /// The day from 6am to midnight, or from earlier when the time or the
    /// allowed range starts before 6.
    private var span: ClosedRange<Int> {
        let earliest = min(minute(of: date), minute(of: range.upperBound))
        let start = min(6 * 60, max(0, earliest / 60 * 60))
        return start...(24 * 60)
    }

    private var allowed: ClosedRange<Int> {
        let low = minute(of: range.lowerBound)
        return low...max(low, minute(of: range.upperBound))
    }

    /// Rounds to the step and keeps it within the allowed range. The edges of the
    /// range stay reachable even when they are not on a step, e.g. "now".
    private func clamp(_ minute: Int) -> Int {
        let stepped = Int((Double(minute) / Double(Self.step)).rounded()) * Self.step
        return min(max(stepped, allowed.lowerBound), allowed.upperBound)
    }

    private func set(_ minute: Int) {
        let value = clamp(minute)
        if value != self.minute(of: date) { date = self.date(at: value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            track
            HStack(spacing: 10) {
                readout
                nudge("−5 min", by: -Self.step, label: "5 minutes earlier")
                nudge("+5 min", by: Self.step, label: "5 minutes later")
                Spacer(minLength: 8)
                Button("Done") {
                    withAnimation(.easeOut(duration: 0.2)) { onDone() }
                }
                .font(.body(14, weight: 800))
                .foregroundStyle(Theme.surface)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Theme.ink, in: Capsule())
                .contentShape(Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1.5))
    }

    private var readout: some View {
        let parts = ClockText.parts(date, calendar: calendar)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(parts.time).font(.display(28)).monospacedDigit()
            Text(parts.period).font(.body(13, weight: 700)).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 104, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func nudge(_ title: String, by delta: Int, label: String) -> some View {
        Button(title) { set(minute(of: date) + delta) }
            .font(.body(14, weight: 800))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface2, in: Capsule())
            .contentShape(Capsule())
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let span = self.span
            let length = Double(span.upperBound - span.lowerBound)
            let x = { (minute: Int) -> CGFloat in
                CGFloat(Double(minute - span.lowerBound) / length) * width
            }
            ZStack(alignment: .topLeading) {
                // The day, its usual times, and what can't be picked.
                ZStack(alignment: .topLeading) {
                    Theme.surface2
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                        let start = max(band.start, span.lowerBound), end = min(band.end, span.upperBound)
                        if end > start {
                            Text(band.label.uppercased())
                                .font(.body(10, weight: 800))
                                .tracking(0.8)
                                .foregroundStyle(Theme.ink.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 2)
                                .frame(width: max(0, x(end) - x(start) - 2), height: 26)
                                .background(band.color)
                                .offset(x: x(start) + 1)
                        }
                    }
                    if allowed.upperBound < span.upperBound {
                        Hatching()
                            .frame(width: width - x(allowed.upperBound), height: 26)
                            .offset(x: x(allowed.upperBound))
                    }
                    if allowed.lowerBound > span.lowerBound {
                        Hatching()
                            .frame(width: x(allowed.lowerBound), height: 26)
                    }
                }
                .frame(width: width, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .offset(y: 14)

                // Hours, labeled every three.
                ForEach(Array(stride(from: (span.lowerBound + 59) / 60 * 60, through: span.upperBound, by: 60)), id: \.self) { minute in
                    let major = (minute / 60) % 3 == 0
                    Rectangle()
                        .fill(Theme.muted.opacity(major ? 0.9 : 0.55))
                        .frame(width: 1, height: major ? 9 : 6)
                        .offset(x: min(x(minute), width - 1), y: 42)
                    if major {
                        Text(Self.hourLabel(minute))
                            .font(.body(11, weight: 700))
                            .foregroundStyle(Theme.muted)
                            .fixedSize()
                            .frame(width: 40)
                            .offset(x: x(minute) - 20, y: 53)
                    }
                }

                // The picked time.
                let thumb = x(min(max(minute(of: date), span.lowerBound), span.upperBound))
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 4, height: 46)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 3).padding(-3))
                        .offset(y: -8)
                }
                .frame(width: 24)
                .offset(x: thumb - 12, y: 4)
            }
            .frame(width: width, height: 66, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(Double(value.location.x / max(width, 1)), 0), 1)
                        set(span.lowerBound + Int((fraction * length).rounded()))
                    }
            )
        }
        .frame(height: 66)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(ClockText.spoken(date, calendar: calendar))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(minute(of: date) + Self.step)
            case .decrement: set(minute(of: date) - Self.step)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("time-ruler")
    }

    /// "6a", "12p", "9p"; the end of the day is "12a".
    static func hourLabel(_ minute: Int) -> String {
        let hour = minute / 60 % 24
        return "\((hour + 11) % 12 + 1)\(hour < 12 ? "a" : "p")"
    }
}

/// Diagonal stripes for times that can't be picked.
private struct Hatching: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 12
            }
            context.stroke(path, with: .color(Theme.muted.opacity(0.22)), lineWidth: 5)
        }
        .background(Theme.surface2.opacity(0.4))
        .allowsHitTesting(false)
    }
}
