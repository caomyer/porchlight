import SwiftUI

/// "More…" on a care card: the wall's care sheet at phone size. The same fields (when,
/// how long, who, business, vibe, note) and the same rules (`CareLogFields`), with you
/// already picked as who went.
struct PocketCareSheet: View {
    struct Request: Identifiable {
        var companionId: Companion.ID
        var routineId: CareRoutine.ID
        /// Who went, to start with: you, and anyone already picked on the card.
        var people: [Person.ID]

        var id: String { "\(companionId)-\(routineId)" }
    }

    let request: Request
    let logging: PocketLogging

    @Environment(AppModel.self) private var model
    @Environment(CompanionStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss

    @State private var fields = CareLogFields()
    @State private var didSetDefaults = false

    var body: some View {
        if let report = store.report(for: request.companionId),
           let routine = report.routines.first(where: { $0.id == request.routineId }) {
            let day = logDay(report: report, routine: routine)
            let noun = routine.kind.noun(title: routine.title)
            PhoneSheet(label: "\(report.name) · \(slotName(routine, day: day))", title: "Log a \(noun)") {
                LogTimeField(
                    time: $fields.when, range: day.range, now: report.now, lasting: day.lasting(fields),
                    suggestions: day.suggestions,
                    accessibilityLabel: routine.tracks(.duration) ? "Started" : "When",
                    identifier: "exact-time", calendar: day.calendar
                ) {
                    VStack(alignment: .leading, spacing: 1) {
                        label(routine.tracks(.duration) ? "Started" : "When")
                        if let note = day.timingNote(fields) {
                            Text(note)
                                .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                if routine.tracks(.duration) {
                    group("How long") {
                        ForEach(CareLogFields.durations, id: \.self) { minutes in
                            PhoneChoice(title: minutes >= 60 ? "1 hr+" : "\(minutes) min", isOn: fields.duration == minutes) { fields.duration = minutes }
                        }
                    }
                }
                group(routine.kind == .walk ? "Who went" : "Who") {
                    ForEach(people) { person in
                        PersonPill(person: person, title: person.id == me?.id ? "You" : nil, isOn: fields.people.contains(person.id)) {
                            fields.toggle(person.id)
                        }
                    }
                }
                if routine.tracks(.pee) || routine.tracks(.poo) {
                    group("Business") {
                        if routine.tracks(.pee) { PhoneChoice(title: "💧 Pee", isOn: fields.pee) { fields.pee.toggle() } }
                        if routine.tracks(.poo) { PhoneChoice(title: "💩 Poo", isOn: fields.poo) { fields.poo.toggle() } }
                        PhoneChoice(title: "🤷 Nothing doing", isOn: !fields.pee && !fields.poo) {
                            fields.pee = false
                            fields.poo = false
                        }
                    }
                }
                if routine.tracks(.vibe) {
                    group("Vibe") {
                        ForEach(CareVibe.allCases, id: \.self) { vibe in
                            PhoneChoice(title: "\(vibe.emoji) \(vibe.label)", isOn: fields.vibe == vibe) { fields.vibe = vibe }
                        }
                    }
                }
                TextField("A note for the \(noun) diary", text: $fields.note, axis: .vertical)
                    .phoneFont(.body, 15, weight: 600)
                    .submitLabel(.done)
                    .fieldStyle()
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = store.lastError {
                        Text(error)
                            .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                            .foregroundStyle(Theme.accent)
                    }
                    Button("Log \(noun) · \(StarWords.earned(routine.stars))") { save(routine, day: day) }
                        .buttonStyle(PhoneButtonStyle())
                        .disabled(fields.people.isEmpty)
                        .accessibilityIdentifier("save-care")
                }
            }
            .onAppear { setDefaults(day) }
        }
    }

    /// You first, then everyone else in the household's order.
    private var people: [Person] {
        model.people.filter { $0.id == me?.id } + model.people.filter { $0.id != me?.id }
    }

    private func logDay(report: CompanionReport, routine: CareRoutine) -> CareLogDay {
        CareLogDay(
            routine: routine, day: report.today, today: report.today, now: report.now,
            calendar: store.snapshot.calendar, history: store.snapshot.entries(of: routine.id)
        )
    }

    /// "evening walk": the slot the chosen time belongs to, by the wall's rule.
    private func slotName(_ routine: CareRoutine, day: CareLogDay) -> String {
        let minute = CareLogic.minuteOfDay(day.startedAt(fields), calendar: day.calendar)
        let index = CareLogic.windowIndex(forMinute: minute, in: routine.effectiveWindows)
        return CareCatchUp.slotName(routine.effectiveWindows[safe: index] ?? .anyTime, of: routine)
    }

    private func label(_ text: String) -> some View {
        Text(text).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            FlowLayout(spacing: 6, lineSpacing: 0) { content() }
        }
    }

    private func setDefaults(_ day: CareLogDay) {
        guard !didSetDefaults else { return }
        didSetDefaults = true
        store.lastError = nil
        fields = .new(people: request.people, for: day, catchUpSlot: nil)
    }

    private func save(_ routine: CareRoutine, day: CareLogDay) {
        let draft = fields.draft(for: day)
        guard let log = store.log(routineId: routine.id, draft, now: CompanionClock.now()) else { return }
        dismiss()
        logging.logged(log, routine: routine, people: draft.people)
    }
}
