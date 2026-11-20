import SwiftUI

/// The one way to log care on the phone beyond a card's one tap: "More…" on a care card, a
/// slot nobody logged (Today's banner, a missed mark in the week), or a logged entry opened
/// to fix. It is the wall's care sheet at phone size: the same fields (when, how long, who,
/// business, vibe, note), the same rules (`CareLogFields`, `CareLogDay`) and the same words
/// for fixing one (`CareLogWording`), with you already picked as who went on a new log.
struct PocketCareSheet: View {
    struct Request: Identifiable {
        var companionId: Companion.ID
        var routineId: CareRoutine.ID
        /// Who went, to start with: you, and anyone already picked on the card. Unused
        /// when fixing a log, which keeps its own people.
        var people: [Person.ID]
        /// Set to fix this log instead of adding one.
        var logId: CareLog.ID?
        /// Set to catch up on a slot nobody logged: the log is for that slot's day, at its
        /// usual time, unless someone logs the slot first.
        var catchUp: CareLogRequest.CatchUp?

        var id: String {
            "\(companionId)-\(routineId)-\(logId?.description ?? "new")" + (catchUp.map { "-\($0.day.rawValue)-\($0.slot)" } ?? "")
        }

        /// Catches up on `missed`, credited to `people` to start with.
        static func catchUp(_ missed: MissedCare, companionId: Companion.ID, people: [Person.ID]) -> Request {
            Request(
                companionId: companionId, routineId: missed.routine.id, people: people,
                catchUp: CareLogRequest.CatchUp(day: missed.day, slot: missed.slot.index)
            )
        }

        /// Opens a logged entry to fix, as tapping it does on the wall.
        static func edit(_ entry: CareEntry, companionId: Companion.ID) -> Request {
            Request(companionId: companionId, routineId: entry.log.careRoutineId, people: [], logId: entry.id)
        }
    }

    let request: Request
    let logging: PocketLogging

    @Environment(AppModel.self) private var model
    @Environment(CompanionStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss

    @State private var fields = CareLogFields()
    @State private var didSetDefaults = false
    @State private var confirmingRemove = false

    var body: some View {
        if let report = store.report(for: request.companionId),
           let routine = report.routines.first(where: { $0.id == request.routineId }) {
            // A log being fixed that is gone (removed on another device) closes the sheet.
            let editing = request.logId.flatMap { id in store.snapshot.entries(of: routine.id).first { $0.id == id } }
            if request.logId != nil && editing == nil {
                Color.clear.onAppear { dismiss() }
            } else {
                form(report: report, routine: routine, editing: editing)
            }
        }
    }

    private func form(report: CompanionReport, routine: CareRoutine, editing: CareEntry?) -> some View {
        let day = CareLogDay.forSheet(
            routine: routine, editing: editing, catchUpDay: request.catchUp?.day, today: report.today, now: report.now,
            calendar: store.snapshot.calendar, history: store.snapshot.entries(of: routine.id)
        )
        let noun = routine.kind.noun(title: routine.title)
        return PhoneSheet(
            label: "\(report.name) · \(slotName(routine, day: day))",
            title: editing == nil ? "Log a \(noun)" : CareLogWording.editTitle(routine)
        ) {
            if let subtitle = subtitle(routine, report: report, editing: editing) {
                Text(subtitle)
                    .phoneFont(.body, 13, weight: 600, relativeTo: .subheadline)
                    .foregroundStyle(Theme.muted)
            }
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
                    ForEach(fields.durationChoices, id: \.self) { minutes in
                        PhoneChoice(title: CareLogFields.durationTitle(minutes), isOn: fields.duration == minutes) { fields.duration = minutes }
                    }
                }
            }
            group(routine.kind == .walk ? "Who went" : "Who") {
                ForEach(people) { person in
                    PersonPill(person: person, title: person.id == me?.id ? "You" : nil, isOn: fields.people.contains(person.id)) {
                        fields.toggle(person.id)
                    }
                    .accessibilityIdentifier("went-\(person.name)")
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
                .accessibilityIdentifier("care-note")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let error = store.lastError {
                    Text(error)
                        .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.accent)
                }
                if let editing {
                    editButtons(editing, routine: routine, day: day)
                } else {
                    Button("Log \(noun) · \(StarWords.earned(routine.stars))") { save(routine, day: day, companion: report.name) }
                        .buttonStyle(PhoneButtonStyle())
                        .disabled(fields.people.isEmpty)
                        .accessibilityIdentifier("save-care")
                }
            }
        }
        .onAppear { setDefaults(day, editing: editing) }
    }

    /// "Save changes" and "Remove", which asks once more before it removes, as on the wall.
    @ViewBuilder
    private func editButtons(_ editing: CareEntry, routine: CareRoutine, day: CareLogDay) -> some View {
        if confirmingRemove {
            Button(CareLogWording.confirmRemove(routine), role: .destructive) { remove(editing) }
                .buttonStyle(PhoneButtonStyle(kind: .destructive))
                .accessibilityIdentifier("confirm-remove-care")
            Button(CareLogWording.keep) { confirmingRemove = false }
                .buttonStyle(PhoneButtonStyle(kind: .ghost))
                .accessibilityIdentifier("keep-care")
        } else {
            Button(CareLogWording.saveChanges) { saveChanges(editing, day: day) }
                .buttonStyle(PhoneButtonStyle())
                .disabled(fields.people.isEmpty)
                .accessibilityIdentifier("save-care")
            Button { confirmingRemove = true } label: {
                Label(CareLogWording.remove, systemImage: "trash")
            }
            .buttonStyle(PhoneButtonStyle(kind: .ghost))
            .accessibilityIdentifier("remove-care")
        }
    }

    /// You first, then everyone else in the household's order.
    private var people: [Person] {
        model.people.filter { $0.id == me?.id } + model.people.filter { $0.id != me?.id }
    }

    /// Under the title: how a fix works, or which slot is being caught up on ("For today's
    /// morning walk"); nothing on a plain new log.
    private func subtitle(_ routine: CareRoutine, report: CompanionReport, editing: CareEntry?) -> String? {
        if editing != nil { return CareLogWording.editSubtitle }
        guard let catchUp = request.catchUp, let window = routine.effectiveWindows[safe: catchUp.slot] else { return nil }
        return CareCatchUp.subtitle(window, of: routine, on: catchUp.day, today: report.today, calendar: store.snapshot.calendar)
    }

    /// "morning walk": the slot this log is for. Catching up, or fixing a log made for a
    /// slot, that slot, unless the chosen time lies in another slot's window; else the slot
    /// the time belongs to, by the wall's rule.
    private func slotIndex(_ routine: CareRoutine, day: CareLogDay) -> Int {
        let minute = CareLogic.minuteOfDay(day.startedAt(fields), calendar: day.calendar)
        let editing = request.logId.flatMap { id in store.snapshot.entries(of: routine.id).first { $0.id == id } }
        return CareLogic.slot(forMinute: minute, intended: request.catchUp?.slot ?? editing?.log.slot, in: routine.effectiveWindows)
    }

    private func slotName(_ routine: CareRoutine, day: CareLogDay) -> String {
        CareCatchUp.slotName(routine.effectiveWindows[safe: slotIndex(routine, day: day)] ?? .anyTime, of: routine)
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

    private func setDefaults(_ day: CareLogDay, editing: CareEntry?) {
        guard !didSetDefaults else { return }
        didSetDefaults = true
        store.lastError = nil
        fields = editing.map { CareLogFields(editing: $0, people: store.snapshot.knownPeople(of: $0)) } ?? .new(people: request.people, for: day, catchUpSlot: request.catchUp?.slot)
    }

    /// Writes before closing: a log that is turned down keeps the sheet open with the reason.
    private func save(_ routine: CareRoutine, day: CareLogDay, companion: String) {
        let draft = fields.draft(for: day)
        // Catching up logs the slot being caught up on, at whatever time it really happened
        // (a morning walk logged at 7 pm is the morning's), unless the time was moved into
        // another slot's window; the label above says which.
        let slot = request.catchUp.map { _ in slotIndex(routine, day: day) }
        guard logging.save(routine, draft, catchingUp: slot, on: day.day, companion: companion) else { return }
        dismiss()
    }

    /// The log keeps its routine and the stars it earned; only who, when and how change.
    /// A fix the rules turn down keeps the sheet open with the reason; one they accept
    /// closes it at once and is written as it goes, so a busy moment never holds it up.
    private func saveChanges(_ editing: CareEntry, day: CareLogDay) {
        let draft = fields.draft(for: day)
        do {
            _ = try CareRules.validatedNote(draft, now: CompanionClock.now())
        } catch {
            store.lastError = error.userMessage
            return
        }
        let logging = logging
        dismiss()
        DispatchQueue.main.async { logging.saveFix(editing.id, draft) }
    }

    /// Removing it takes its stars back too: they belong to the log.
    private func remove(_ editing: CareEntry) {
        let logging = logging
        dismiss()
        DispatchQueue.main.async { logging.remove(editing.id) }
    }
}
