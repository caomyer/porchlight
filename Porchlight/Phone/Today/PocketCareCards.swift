import SwiftUI

/// What a care card can ask Today to do.
struct PocketCareHandlers {
    /// Log the action now, with whoever else came along.
    let log: (PocketToday.CareCard, PocketToday.CareAction, _ alsoWent: [Person.ID]) -> Void
    /// Open the full care sheet for a routine, with whoever else came along.
    let more: (PocketToday.CareCard, CareRoutine, _ alsoWent: [Person.ID]) -> Void
    /// Open the companion's week.
    let open: (PocketToday.CareCard) -> Void
    /// Open a logged entry to fix, as tapping a done slot does on the wall.
    let edit: (PocketToday.CareCard, CareEntry) -> Void
}

/// The companions on Today: a full card each, or a grid of two when there are several
/// (back to full cards at the largest text sizes, so nothing gets squeezed).
struct PocketCareSection: View {
    let cards: [PocketToday.CareCard]
    let handlers: PocketCareHandlers

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if cards.count > 1 && !typeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(cards) { card in
                    SmallCareCard(card: card, handlers: handlers)
                }
            }
        } else {
            ForEach(cards) { card in
                if card.standing == .allSet && !PocketToday.isFresh(card) {
                    AllSetCard(card: card) { handlers.open(card) }
                } else {
                    FullCareCard(card: card, handlers: handlers)
                }
            }
        }
    }
}

/// One companion with its slots today, the big button, and who else came along.
private struct FullCareCard: View {
    let card: PocketToday.CareCard
    let handlers: PocketCareHandlers

    @Environment(AppModel.self) private var model
    @Environment(CompanionStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var alsoWent: [Person.ID] = []

    private var report: CompanionReport { card.report }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let shown = card.shown, !shown.slots.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                    ForEach(shown.slots) { slot in
                        slotTile(slot, routine: shown.routine)
                    }
                }
            }
            if let lead = card.lead {
                Button {
                    handlers.log(card, lead, alsoWent)
                    alsoWent = []
                } label: {
                    Text("\(lead.routine.emoji) \(lead.routine.kind.buttonTitle(name: report.name, title: lead.routine.title))")
                }
                .buttonStyle(PhoneButtonStyle())
                .accessibilityLabel(PocketCareWords.logLabel(lead, companion: report.name))
                .accessibilityIdentifier("log-\(report.name)")
            } else if card.standing == .allSet, let latest {
                DoneCapsule(text: "✓ Logged · \(StarWords.earned(latest.log.stars))")
            } else if let routine = card.shown?.routine {
                Button("Log a \(routine.kind.noun(title: routine.title))…") { handlers.more(card, routine, []) }
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
            }
            if !card.others.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(card.others, id: \.routine.id) { action in
                        otherButton(action)
                    }
                }
            }
            if let lead = card.lead {
                alsoWentRow(lead.routine)
            }
        }
        .phoneCard(tint: report.look.tint)
    }

    private var header: some View {
        Button { handlers.open(card) } label: { headerContent.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(report.name.possessive) week")
            .accessibilityIdentifier("week-\(report.name)")
    }

    private var headerContent: some View {
        HStack(alignment: .center, spacing: 10) {
            CompanionBadge(report)
            VStack(alignment: .leading, spacing: 1) {
                Text(report.name)
                    .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
                Text(PocketToday.lastLine(card.shown, report: report, me: me?.id, names: store.snapshot.names))
                    .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if report.streak > 1 && !typeSize.isAccessibilitySize {
                PhoneTag(text: "🔥 \(report.streak)-day streak")
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }

    /// The newest log today, for "✓ Logged".
    private var latest: CareEntry? {
        ([report.primary].compactMap { $0 } + report.others).flatMap(\.slots).compactMap(\.entry).max { $0.time < $1.time }
    }

    private func otherButton(_ action: PocketToday.CareAction) -> some View {
        Button { handlers.log(card, action, alsoWent) } label: {
            HStack(spacing: 6) {
                Text(action.routine.emoji)
                Text(PocketToday.slotTitle(action.slot, of: action.routine) == action.routine.title
                     ? action.routine.title
                     : "\(action.routine.title) · \(action.slot.window.label.lowercased())")
                    .phoneFont(.body, 13, weight: 700, relativeTo: .subheadline)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PocketCareWords.logLabel(action, companion: report.name))
    }

    /// A done slot opens its log to fix, as on the wall; an open one is the big button's.
    @ViewBuilder
    private func slotTile(_ slot: CareSlot, routine: CareRoutine) -> some View {
        if let entry = slot.entry {
            Button { handlers.edit(card, entry) } label: {
                CareSlotTile(slot: slot, routine: routine, snapshot: store.snapshot)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(CareLogWording.editSubtitle)
            .accessibilityIdentifier("slot-\(report.name)-\(slot.index)")
        } else {
            CareSlotTile(slot: slot, routine: routine, snapshot: store.snapshot)
        }
    }

    private func alsoWentRow(_ routine: CareRoutine) -> some View {
        let others = model.people.filter { $0.id != me?.id }
        return FlowLayout(spacing: 6) {
            if me != nil && !others.isEmpty {
                Text(routine.kind == .walk ? "Also went:" : "Also helped:")
                    .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 44)
                ForEach(others) { person in
                    PersonPill(person: person, isOn: alsoWent.contains(person.id)) {
                        if alsoWent.contains(person.id) { alsoWent.removeAll { $0 == person.id } } else { alsoWent.append(person.id) }
                    }
                }
            }
            Button { handlers.more(card, routine, alsoWent) } label: {
                Text("More…")
                    .phoneFont(.body, 12.5, weight: 800, relativeTo: .footnote)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More details for \(report.name.possessive) \(routine.kind.noun(title: routine.title))")
            .accessibilityIdentifier("more-\(report.name)")
        }
    }
}

/// A companion whose day is done, folded to one line: "Yo-Yo is all set".
private struct AllSetCard: View {
    let card: PocketToday.CareCard
    let onOpen: () -> Void

    @Environment(CompanionStore.self) private var store
    @Environment(\.me) private var me

    var body: some View {
        Button(action: onOpen) { content.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(card.report.name.possessive) week")
            .accessibilityIdentifier("week-\(card.report.name)")
            .phoneCard(tint: card.report.look.tint)
    }

    private var content: some View {
        HStack(spacing: 10) {
            CompanionBadge(card.report)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(card.report.name) is all set")
                    .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
                Text(PocketToday.allSetLine(card.report, me: me?.id, names: store.snapshot.names, calendar: store.snapshot.calendar))
                    .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A companion in the grid of two: face, name, what is due, and one tap.
private struct SmallCareCard: View {
    let card: PocketToday.CareCard
    let handlers: PocketCareHandlers

    @Environment(CompanionStore.self) private var store
    @Environment(\.me) private var me

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { handlers.open(card) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    CompanionBadge(card.report, size: 34)
                    Text(card.report.name)
                        .phoneFont(.display, 16, weight: 600, relativeTo: .headline)
                    Text(status)
                        .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(card.report.name.possessive) week")
            .accessibilityIdentifier("week-\(card.report.name)")
            Spacer(minLength: 0)
            if let lead = card.lead {
                Button("\(lead.routine.emoji) \(lead.routine.kind.pastVerb)") { handlers.log(card, lead, []) }
                    .buttonStyle(PhoneButtonStyle(small: true))
                    .accessibilityLabel(PocketCareWords.logLabel(lead, companion: card.report.name))
                    .accessibilityIdentifier("log-\(card.report.name)")
            } else if card.standing == .allSet {
                DoneCapsule(text: "✓ All set", small: true)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .phoneCard(tint: card.standing == .due ? card.report.look.tint : nil)
        .contextMenu {
            if let routine = card.lead?.routine ?? card.shown?.routine {
                Button("Log with details…") { handlers.more(card, routine, []) }
            }
        }
        .accessibilityAction(named: "Log with details") {
            if let routine = card.lead?.routine ?? card.shown?.routine { handlers.more(card, routine, []) }
        }
    }

    private var status: String {
        let calendar = store.snapshot.calendar
        if let lead = card.lead {
            let name = PocketCareWords.capitalized(CareCatchUp.slotName(lead.slot.window, of: lead.routine))
            switch lead.slot.state {
            case .due: return "\(name) due now"
            case .open: return "\(name) open now"
            default: return lead.slot.window.isAllDay ? "\(name) due today" : "\(name) from \(CareTime.hour(lead.slot.window.start))"
            }
        }
        if card.standing == .allSet {
            return PocketToday.allSetLine(card.report, me: me?.id, names: store.snapshot.names, calendar: calendar)
        }
        return PocketToday.lastLine(card.shown, report: card.report, me: me?.id, names: store.snapshot.names)
    }
}

/// Words the care cards share.
enum PocketCareWords {
    /// "Log Yo-Yo's evening walk": what VoiceOver reads for a care button.
    static func logLabel(_ action: PocketToday.CareAction, companion: String) -> String {
        "Log \(companion.possessive) \(CareCatchUp.slotName(action.slot.window, of: action.routine))"
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
