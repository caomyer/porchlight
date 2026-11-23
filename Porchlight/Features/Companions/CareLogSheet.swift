import SwiftUI

/// Which routine to log for which companion, or which log to fix.
struct CareLogRequest: Identifiable, Equatable {
    var companionId: Companion.ID
    var routineId: CareRoutine.ID
    /// Set to edit an existing log instead of adding one.
    var logId: CareLog.ID?
    /// Set to catch up on an earlier day's missed slot: the log is for that day, at the
    /// slot's usual time.
    var catchUp: CatchUp?
    /// The celebration's button, e.g. "Back to today".
    var returnTitle = "Back to today"
    /// Skip the form and show the celebration (DEBUG screenshots only).
    var celebrateOnly = false

    struct CatchUp: Equatable {
        var day: DayKey
        var slot: Int
    }

    var id: String { "\(companionId)-\(routineId)-\(logId?.description ?? "new")-\(catchUp.map { "\($0.day)-\($0.slot)" } ?? "")" }

    /// Opens a logged entry for editing.
    static func edit(_ entry: CareEntry, companionId: Companion.ID) -> CareLogRequest {
        CareLogRequest(companionId: companionId, routineId: entry.log.careRoutineId, logId: entry.id)
    }

    /// Logs a missed slot for its own day.
    static func catchUp(companionId: Companion.ID, routineId: CareRoutine.ID, day: DayKey, slot: Int) -> CareLogRequest {
        CareLogRequest(companionId: companionId, routineId: routineId, catchUp: CatchUp(day: day, slot: slot))
    }
}

extension View {
    /// Presents the log sheet, then the celebration, over the whole wall. Views
    /// inside can open it through `openCareLog`.
    func careLogFlow(_ request: Binding<CareLogRequest?>) -> some View {
        environment(\.openCareLog, OpenCareLogAction { next in CompanionCover.instantly { request.wrappedValue = next } })
            .wallCover(item: request) { item in
                CareLogFlow(request: item) { CompanionCover.instantly { request.wrappedValue = nil } }
            }
    }
}

/// Opens the log sheet for a routine, or a logged entry to fix.
struct OpenCareLogAction {
    let open: @MainActor (CareLogRequest) -> Void
    @MainActor func callAsFunction(_ request: CareLogRequest) { open(request) }
}

extension EnvironmentValues {
    @Entry var openCareLog: OpenCareLogAction? = nil
}

enum CompanionCover {
    /// Runs a state change with animations turned off, so a wall layer appears in place
    /// and fades itself in.
    @MainActor
    static func instantly(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

/// The log form, then a celebration. Owns its own fade in and out.
private struct CareLogFlow: View {
    let request: CareLogRequest
    let onFinish: () -> Void

    @Environment(CompanionStore.self) private var store
    @State private var celebration: Celebration?
    @State private var isShown = false

    var body: some View {
        ZStack {
            if let report = store.report(for: request.companionId),
               let routine = report.routines.first(where: { $0.id == request.routineId }) {
                if let celebration {
                    CelebrationView(look: report.look, celebration: celebration, returnTitle: request.returnTitle, autoDismiss: !request.celebrateOnly, onDone: close)
                        .transition(.opacity)
                } else if !request.celebrateOnly {
                    WallSheet(width: 640, onClose: close) {
                        if let logId = request.logId {
                            if let entry = store.snapshot.entries(of: routine.id).first(where: { $0.id == logId }) {
                                CareLogForm(report: report, routine: routine, editing: entry, onSaved: { _ in }, onClose: close)
                            }
                        } else {
                            CareLogForm(report: report, routine: routine, catchUp: request.catchUp, onSaved: { result in
                                // Catching up fills in the missed mark; the cheer is for today's care.
                                if request.catchUp != nil { close() } else { withAnimation(.easeOut(duration: 0.3)) { celebration = result } }
                            }, onClose: close)
                        }
                    }
                }
            }
        }
        .opacity(isShown ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) { isShown = true }
            #if DEBUG
            if request.celebrateOnly, let report = store.report(for: request.companionId) {
                celebration = Celebration.preview(report: report)
            }
            #endif
        }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.18)) { isShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onFinish() }
    }
}

/// The "Who walked Yo-Yo?" form, also used to fix a logged entry. Only the
/// routine's tracked fields are shown.
private struct CareLogForm: View {
    let report: CompanionReport
    let routine: CareRoutine
    /// The log being fixed; nil when logging a new one.
    var editing: CareEntry?
    /// The earlier day's slot being caught up on.
    var catchUp: CareLogRequest.CatchUp?
    let onSaved: (Celebration) -> Void
    let onClose: () -> Void

    @Environment(CompanionStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var fields = CareLogFields()
    @State private var didSetDefaults = false
    @State private var confirmingDelete = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CompanionFace(look: report.look, expression: report.expression, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.display(30))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.trailing, 44)
            }
            ScrollViewReader { proxy in
                FittedScrollView {
                    sections
                }
                .onChange(of: noteFocused) { _, focused in
                    guard focused else { return }
                    // After the keyboard has shrunk the sheet.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("note", anchor: .bottom) }
                    }
                }
            }
            buttons
                .padding(.top, 22)
        }
        .onAppear(perform: setDefaults)
    }

    /// Everything between the title and the buttons; scrolls only when space runs out.
    private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
            label(routine.kind == .walk ? "Walkers" : "Who")
            FlowLayout(spacing: 14) {
                ForEach(model.people) { person in
                    personButton(person)
                }
            }
            LogTimeField(
                time: $fields.when,
                range: logDay.range,
                now: report.now,
                lasting: logDay.lasting(fields),
                suggestions: logDay.suggestions,
                accessibilityLabel: routine.tracks(.duration) ? "Started" : "When",
                identifier: "exact-time",
                calendar: store.snapshot.calendar
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionLabel(routine.tracks(.duration) ? "Started" : "When")
                    if let timingNote = logDay.timingNote(fields) {
                        Text(timingNote).font(.body(12.5, weight: 600)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.top, 16)
            if routine.tracks(.duration) {
                label("How long")
                FlowLayout(spacing: 8) {
                    ForEach(fields.durationChoices, id: \.self) { minutes in
                        ChoicePill(title: CareLogFields.durationTitle(minutes), isSelected: fields.duration == minutes) { fields.duration = minutes }
                    }
                }
            }
            if routine.tracks(.pee) || routine.tracks(.poo) {
                label("Business")
                FlowLayout(spacing: 8) {
                    if routine.tracks(.pee) { ChoicePill(title: "💧 Pee", isSelected: fields.pee) { fields.pee.toggle() } }
                    if routine.tracks(.poo) { ChoicePill(title: "💩 Poo", isSelected: fields.poo) { fields.poo.toggle() } }
                    ChoicePill(title: "🤷 Nothing doing", isSelected: !fields.pee && !fields.poo) {
                        fields.pee = false
                        fields.poo = false
                    }
                }
            }
            if routine.tracks(.vibe) {
                label("Vibe")
                FlowLayout(spacing: 8) {
                    ForEach(CareVibe.allCases, id: \.self) { option in
                        ChoicePill(title: "\(option.emoji) \(option.label)", isSelected: fields.vibe == option) { fields.vibe = option }
                    }
                }
            }
            label("Note")
            TextField("Optional: what happened?", text: $fields.note)
                .font(.body(15, weight: 600))
                .submitLabel(.done)
                .focused($noteFocused)
                .fieldStyle()
                .id("note")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 10) {
            if editing != nil {
                if confirmingDelete {
                    Button(CareLogWording.keep) { confirmingDelete = false }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(CareLogWording.confirmRemove(words), role: .destructive, action: delete)
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button { confirmingDelete = true } label: {
                        Label(CareLogWording.remove, systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            Spacer(minLength: 8)
            if let error = store.lastError {
                Text(error).font(.body(13, weight: 600)).foregroundStyle(Theme.accent).lineLimit(2)
            }
            if !confirmingDelete {
                if editing != nil {
                    Button("Cancel", action: onClose).buttonStyle(SecondaryButtonStyle())
                }
                // Waiting for a person, it says so: "Pick who walked", not a silent gray Save.
                Button(action: save) {
                    if fields.people.isEmpty {
                        Text(words.pickWho)
                    } else {
                        Label(editing == nil ? "Save \(noun)" : CareLogWording.saveChanges, systemImage: "checkmark")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(fields.people.isEmpty)
                .accessibilityIdentifier("save-care")
            }
        }
    }

    private var words: CareWords { CareWords(routine, species: report.companion.species) }
    private var noun: String { words.noun }

    private var subtitle: String {
        if editing != nil { return CareLogWording.editSubtitle }
        if let catchUp, let window = routine.effectiveWindows[safe: catchUp.slot] {
            return CareCatchUp.subtitle(window, of: routine, on: catchUp.day, today: report.today, calendar: store.snapshot.calendar)
        }
        return "Tap everyone who came along"
    }

    private var title: String {
        guard editing != nil else { return words.question(name: report.name) }
        return CareLogWording.editTitle(words)
    }

    private func label(_ text: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SectionLabel(text)
            if let note {
                Text(note).font(.body(12.5, weight: 600)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func personButton(_ person: Person) -> some View {
        let id = person.id
        let isSelected = fields.people.contains(id)
        let color = person.color.color
        return Button {
            fields.toggle(id)
        } label: {
            VStack(spacing: 6) {
                Avatar(person: person, size: 76)
                Text(person.name)
                    .font(.body(14, weight: 700))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(width: 96)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.wash(0.12))
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(color, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(color, in: Circle())
                        .padding(.top, 6)
                        .padding(.trailing, 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The log's day and the times it can take.
    private var logDay: CareLogDay {
        CareLogDay.forSheet(
            routine: routine, editing: editing, catchUpDay: catchUp?.day, today: report.today, now: report.now,
            calendar: store.snapshot.calendar, history: store.snapshot.entries(of: routine.id)
        )
    }

    private func setDefaults() {
        guard !didSetDefaults else { return }
        didSetDefaults = true
        store.lastError = nil
        if let editing {
            fields = CareLogFields(editing: editing, people: store.snapshot.knownPeople(of: editing))
            return
        }
        // The wall can't know who is standing at it: it picks someone only when there is
        // nobody else it could be (docs/design/companion-care.md, "Who is credited").
        fields = .new(people: CareLogFields.wallDefault(model.people.map(\.id)), for: logDay, catchUpSlot: catchUp?.slot)
    }

    private func save() {
        let draft = fields.draft(for: logDay)
        if let editing {
            if store.updateLog(id: editing.id, draft) { onClose() }
            return
        }
        if let catchUp {
            // The slot itself, unless someone logged it meanwhile: then there is nothing to add.
            switch store.log(routineId: routine.id, slot: catchUp.slot, on: catchUp.day, draft) {
            case nil: return
            case .alreadyLogged: return onClose()
            case .logged: break
            }
        } else {
            guard store.log(routineId: routine.id, draft) != nil else { return }
        }
        onSaved(Celebration.after(report: report, routine: routine, people: fields.people, names: store.snapshot.names, calendar: store.snapshot.calendar))
    }

    private func delete() {
        guard let editing else { return }
        // A removal that is turned down keeps the sheet open with the reason.
        if store.deleteLog(id: editing.id) { onClose() }
    }
}

// MARK: - Celebration

struct Celebration: Equatable {
    var title: String
    var message: String
    var stars: Int
    var confetti: [String]

    /// The celebration for a log just saved on top of `report` (taken before the save).
    static func after(report: CompanionReport, routine: CareRoutine, people: [Person.ID], names: [Person.ID: String], calendar: Calendar) -> Celebration {
        let firstNames = people.compactMap { names[$0] }
        let who = firstNames.isEmpty ? "" : ", " + CaptionEngine.whoText(people, names: names)
        let today = report.primary?.routine.id == routine.id ? report.primary : report.others.first { $0.routine.id == routine.id }
        let countToday = (today?.slots.filter(\.isDone).count ?? 0) + 1
        let noun = CareWords(routine, species: report.companion.species).noun
        var message = "\(noun.prefix(1).uppercased() + noun.dropFirst()) #\(countToday) today"
        if let slots = today?.slots, countToday >= slots.count, slots.count > 1 {
            message += slots.count == 2 ? ", both slots done" : ", all \(slots.count) slots done"
        }
        let mood = CompanionPresets.mood(for: report.companion.species, level: 0.7)
        message += ". \(report.name) is officially \(mood.label.lowercased())."
        return Celebration(
            title: "Nice one\(who)!",
            message: message,
            stars: routine.stars,
            confetti: CompanionPresets.confetti(for: report.companion.species)
        )
    }

    #if DEBUG
    static func preview(report: CompanionReport) -> Celebration {
        guard let routine = report.primaryRoutine else {
            return Celebration(title: "Nice one!", message: "", stars: 0, confetti: CompanionPresets.confetti(for: report.companion.species))
        }
        return after(report: report, routine: routine, people: [], names: [:], calendar: .current)
    }
    #endif
}

/// Full-screen confetti with the companion jumping for joy. Dismisses itself after a few seconds.
private struct CelebrationView: View {
    let look: CompanionLook
    let celebration: Celebration
    let returnTitle: String
    var autoDismiss = true
    let onDone: () -> Void

    @State private var jump = false

    var body: some View {
        ZStack {
            look.tint.wash(0.3, over: Theme.background)
                .ignoresSafeArea()
            Confetti(symbols: celebration.confetti)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                CompanionFace(look: look, expression: .happy, size: 200)
                    .scaleEffect(x: jump ? 1 : 1.02, y: jump ? 1 : 0.97, anchor: .bottom)
                    .rotationEffect(.degrees(jump ? 4 : 0))
                    .offset(y: jump ? -34 : 10)
                Text(celebration.title)
                    .font(.display(46))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                Text(celebration.message)
                    .font(.body(18, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                if celebration.stars > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill").foregroundStyle(Color(hex: 0xC2933A))
                        Text("+\(celebration.stars) \(celebration.stars == 1 ? "star" : "stars")")
                    }
                        .font(.body(16, weight: 800))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.surface, in: Capsule())
                        .padding(.top, 16)
                }
                Button(returnTitle, action: onDone)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 22)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .onAppear {
            withAnimation(.timingCurve(0.3, 0.7, 0.4, 1, duration: 0.7).repeatForever(autoreverses: true)) { jump = true }
        }
        .task {
            guard autoDismiss else { return }
            try? await Task.sleep(for: .seconds(4.5))
            onDone()
        }
    }
}

/// Emoji falling at staggered speeds, like the mock's confetti.
private struct Confetti: View {
    let symbols: [String]
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                let resolved = symbols.map { context.resolve(Text($0).font(.system(size: 26))) }
                guard !resolved.isEmpty else { return }
                for index in 0..<22 {
                    let duration = 2.2 + Double(index % 5) * 0.5
                    let delay = Double(index % 7) * 0.25
                    let t = elapsed - delay
                    guard t > 0 else { continue }
                    let progress = t.truncatingRemainder(dividingBy: duration) / duration
                    let x = size.width * CGFloat((Double(index) * 4.7).truncatingRemainder(dividingBy: 100) / 100) + 13
                    let y = -30 + (size.height + 60) * progress
                    var symbol = context
                    symbol.translateBy(x: x, y: y)
                    symbol.rotate(by: .degrees(360 * progress))
                    symbol.draw(resolved[index % resolved.count], at: .zero)
                }
            }
        }
    }
}
