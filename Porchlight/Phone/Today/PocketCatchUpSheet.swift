import SwiftUI

/// Catching up on a slot that was never logged: only the time is asked, on the wall's
/// number pad with its suggestions, laid into the sheet. It is credited to you.
struct PocketCatchUpSheet: View {
    struct Request: Identifiable {
        var companionId: Companion.ID
        var missed: MissedCare

        var id: String { missed.id }
    }

    let request: Request
    let logging: PocketLogging

    @Environment(AppModel.self) private var model
    @Environment(CompanionStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss

    @State private var when: LogTime?
    @State private var typing = TimeTyping()
    /// A typed time that can't be used, shown with the reason until it is fixed.
    @State private var refused: Int?
    @State private var note: String?
    /// On a shared screen, who did it.
    @State private var picked: [Person.ID] = []

    private var missed: MissedCare { request.missed }
    private var routine: CareRoutine { missed.routine }

    var body: some View {
        if let report = store.report(for: request.companionId) {
            let clock = timeDay(report)
            let time = when ?? .at(missed.usual)
            let minute = clock.minute(clock.resolved(time, now: report.now, lasting: 0))
            let slot = CareCatchUp.slotName(missed.slot.window, of: routine)
            PhoneSheet(
                label: "\(report.name) · \(slot)",
                title: routine.kind.whenQuestion(name: report.name, title: routine.title)
            ) {
                TimeKeypadCard(
                    minute: refused ?? minute,
                    suggestions: clock.suggestions(suggestions(report), selected: time, now: report.now, lasting: 0) { chosen in
                        when = chosen
                        refused = nil
                        note = nil
                    },
                    note: note,
                    typing: $typing,
                    onChange: { change($0, clock: clock) },
                    onSuggestion: { _ = $0.apply() },
                    onClose: {},
                    isInline: true
                )
                if me == nil {
                    FlowLayout(spacing: 6, lineSpacing: 0) {
                        ForEach(model.people) { person in
                            PersonPill(person: person, isOn: picked.contains(person.id)) {
                                if picked.contains(person.id) { picked.removeAll { $0 == person.id } } else { picked.append(person.id) }
                            }
                        }
                    }
                }
            } footer: {
                Button("Log \(slot) at \(ClockStyle.current.text(minute))") { save(clock.date(minute)) }
                    .buttonStyle(PhoneButtonStyle())
                    .disabled(refused != nil || people.isEmpty)
                    .accessibilityIdentifier("save-catch-up")
            }
        }
    }

    private var people: [Person.ID] { me.map { [$0.id] } ?? picked }

    private func timeDay(_ report: CompanionReport) -> LogTimeDay {
        let day = CareLogDay(
            routine: routine, day: missed.day, today: report.today, now: report.now,
            calendar: store.snapshot.calendar, history: store.snapshot.entries(of: routine.id)
        )
        return LogTimeDay(range: day.range, calendar: day.calendar)
    }

    /// The usual time first, then the slot's window: its start, middle and end.
    private func suggestions(_ report: CompanionReport) -> [(title: String, time: LogTime)] {
        let window = missed.slot.window
        var list: [(title: String, time: LogTime)] = [("Usual", .at(missed.usual))]
        guard !window.isAllDay else { return list }
        let calendar = store.snapshot.calendar
        for minute in [window.start, window.midpoint, window.end] {
            let date = CareLogic.date(missed.day, minute: minute, calendar: calendar)
            guard !list.contains(where: { $0.time == .at(date) }) else { continue }
            list.append((ClockStyle.current.text(minute), .at(date)))
        }
        return list
    }

    private func change(_ minute: Int, clock: LogTimeDay) {
        if let problem = clock.problem(minute) {
            refused = minute
            note = problem
        } else {
            when = .at(clock.date(minute))
            refused = nil
            note = nil
        }
    }

    private func save(_ time: Date) {
        let draft = CareLogDraft(people: people, occurredAt: time, durationMinutes: nil, pee: nil, poo: nil, vibe: nil, note: nil)
        let name = store.companion(request.companionId)?.name ?? ""
        dismiss()
        logging.log(routine, slot: missed.slot.index, on: missed.day, draft, companion: name)
    }
}
