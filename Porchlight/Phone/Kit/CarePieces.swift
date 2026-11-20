import SwiftUI

// The care pieces at phone size: a companion's face, a slot tile, and the pill that
// adds someone who came along. The words and states come from CareLogic, as on the wall.

/// A companion's face on its tinted circle.
struct CompanionBadge: View {
    let report: CompanionReport
    @PhoneMetric private var side: CGFloat

    init(_ report: CompanionReport, size: CGFloat = 46) {
        self.report = report
        _side = PhoneMetric(wrappedValue: size, upTo: 1.4)
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        CompanionFace(look: report.look, expression: report.expression, size: side * 0.86)
            .frame(width: side, height: side)
            .background(report.look.tint.wash(0.3, over: Theme.surface, in: scheme), in: Circle())
            .accessibilityHidden(true)
    }
}

/// One slot of today: who did it and when, or its window and whether it is open now.
struct CareSlotTile: View {
    let slot: CareSlot
    let routine: CareRoutine
    let snapshot: CompanionSnapshot

    @PhoneMetric private var mark: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 8) {
            if let entry = slot.entry {
                CarerAvatar(carers: Carers(entry.people, snapshot: snapshot), size: mark)
            } else {
                Text(routine.emoji)
                    .phoneFont(.body, 15, relativeTo: .footnote)
                    .frame(width: mark, height: mark)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(PocketToday.slotTitle(slot, of: routine))
                    .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                SlotDetail(parts: PocketToday.slotDetailParts(slot, calendar: snapshot.calendar, namesNobody: namesNobody))
                    .foregroundStyle(isCalling || namesNobody ? Theme.accent : Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background {
            if slot.isDone {
                shape.fill(Theme.goodSoft)
            } else {
                shape.strokeBorder(isCalling ? Theme.accent : Theme.line, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Logged, but by nobody this household knows: it asks who.
    private var namesNobody: Bool { slot.entry.map(snapshot.namesNobody) ?? false }

    /// Open now, or past its window: the slot is asking for someone.
    private var isCalling: Bool { [.open, .due, .late].contains(slot.state) }
}

/// "5-8pm · open now" on one line where it fits, and otherwise the status on a line of
/// its own under the time, never a dot left hanging at either end.
private struct SlotDetail: View {
    let parts: (time: String, status: String?)

    var body: some View {
        if let status = parts.status {
            ViewThatFits(in: .horizontal) {
                line("\(parts.time) · \(status)").lineLimit(1)
                VStack(alignment: .leading, spacing: 0) {
                    line(parts.time)
                    line(status)
                }
            }
        } else {
            line(parts.time)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Someone who came along, toggled on before logging. The pill is small; the place
/// to tap is 44 pt tall.
struct PersonPill: View {
    let person: Person
    var title: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                PersonAvatar(person, size: .small)
                Text(title ?? person.name)
                    .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                    .foregroundStyle(Theme.ink)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(isOn ? Theme.accentSoft : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Theme.accent : Theme.line, lineWidth: isOn ? 1.5 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title ?? person.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A choice on a phone sheet ("20 min", "💧 Pee"): outlined, in the accent once chosen.
struct PhoneChoice: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(isOn ? Theme.accentSoft : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Theme.accent : Theme.line, lineWidth: isOn ? 1.5 : 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
