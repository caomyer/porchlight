import SwiftUI

/// Which routine to log for which companion, or which log to fix.
struct CareLogRequest: Identifiable, Equatable {
    var companionId: Int64
    var routineId: Int64
    /// Set to edit an existing log instead of adding one.
    var logId: Int64?
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

    var id: String { "\(companionId)-\(routineId)-\(logId ?? 0)-\(catchUp.map { "\($0.day)-\($0.slot)" } ?? "")" }

    /// Opens a logged entry for editing.
    static func edit(_ entry: CareEntry, companionId: Int64) -> CareLogRequest {
        CareLogRequest(companionId: companionId, routineId: entry.log.careRoutineId, logId: entry.id)
    }

    /// Logs a missed slot for its own day.
    static func catchUp(companionId: Int64, routineId: Int64, day: DayKey, slot: Int) -> CareLogRequest {
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

    @State private var people: [Int64] = []
    @State private var duration = 20
    @State private var pee = true
    @State private var poo = true
    @State private var vibe: CareVibe = .smooth
    @State private var when: LogTime = .justNow
    @State private var note = ""
    @State private var didSetDefaults = false
    @State private var confirmingDelete = false
    @FocusState private var noteFocused: Bool

    private static let durations = [10, 20, 30, 45, 60]

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
                time: $when,
                range: dayRange,
                now: report.now,
                lasting: routine.tracks(.duration) ? duration : 0,
                suggestions: isToday ? LogTime.recentSuggestions(justNow: routine.tracks(.duration) ? "Just got back" : "Just now") : slotSuggestions,
                accessibilityLabel: routine.tracks(.duration) ? "Started" : "When",
                identifier: "exact-time",
                calendar: store.snapshot.calendar
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionLabel(routine.tracks(.duration) ? "Started" : "When")
                    if let timingNote {
                        Text(timingNote).font(.body(12.5, weight: 600)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.top, 16)
            if routine.tracks(.duration) {
                label("How long")
                FlowLayout(spacing: 8) {
                    ForEach(Self.durations, id: \.self) { minutes in
                        ChoicePill(title: minutes >= 60 ? "1 hr+" : "\(minutes) min", isSelected: duration == minutes) { duration = minutes }
                    }
                }
            }
            if routine.tracks(.pee) || routine.tracks(.poo) {
                label("Business")
                FlowLayout(spacing: 8) {
                    if routine.tracks(.pee) { ChoicePill(title: "💧 Pee", isSelected: pee) { pee.toggle() } }
                    if routine.tracks(.poo) { ChoicePill(title: "💩 Poo", isSelected: poo) { poo.toggle() } }
                    ChoicePill(title: "🤷 Nothing doing", isSelected: !pee && !poo) {
                        pee = false
                        poo = false
                    }
                }
            }
            if routine.tracks(.vibe) {
                label("Vibe")
                FlowLayout(spacing: 8) {
                    ForEach(CareVibe.allCases, id: \.self) { option in
                        ChoicePill(title: "\(option.emoji) \(option.label)", isSelected: vibe == option) { vibe = option }
                    }
                }
            }
            label("Note")
            TextField("Optional: what happened?", text: $note)
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
                    Button("Keep it") { confirmingDelete = false }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Remove \(noun)", role: .destructive, action: delete)
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button { confirmingDelete = true } label: {
                        Label("Remove", systemImage: "trash")
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
                Button(action: save) {
                    Label(editing == nil ? "Save \(noun)" : "Save changes", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(people.isEmpty)
            }
        }
    }

    private var noun: String { routine.kind.noun(title: routine.title) }

    private var subtitle: String {
        if editing != nil { return "Fix who, when or how it went" }
        if let catchUp, let window = routine.effectiveWindows[safe: catchUp.slot] {
            return CareCatchUp.subtitle(window, of: routine, on: catchUp.day, today: report.today, calendar: store.snapshot.calendar)
        }
        return "Tap everyone who came along"
    }

    /// On an earlier day, the time card offers that day's slots at their usual times.
    private var slotSuggestions: [(title: String, time: LogTime)] {
        routine.effectiveWindows.indices.compactMap { index in
            let window = routine.effectiveWindows[index]
            guard !window.isAllDay else { return nil }
            return (window.label, .at(usualTime(index)))
        }
    }

    private func usualTime(_ slot: Int) -> Date {
        CareCatchUp.usualTime(slot, of: routine, on: day, entries: store.snapshot.entries(of: routine.id), now: report.now, calendar: store.snapshot.calendar)
    }

    private var title: String {
        guard editing != nil else { return routine.kind.question(name: report.name, title: routine.title) }
        return "Edit " + noun
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
        let id = person.id ?? -1
        let isSelected = people.contains(id)
        let color = person.color.color
        return Button {
            if isSelected { people.removeAll { $0 == id } } else { people.append(id) }
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

    /// The log's day: the day of the one being fixed, the missed slot's day, or today.
    private var day: DayKey {
        if let editing { return DayKey(editing.time, calendar: store.snapshot.calendar) }
        return catchUp?.day ?? report.today
    }

    private var isToday: Bool { day == report.today }

    /// The day's start up to now, or its last minute for an earlier day.
    private var dayRange: ClosedRange<Date> {
        let calendar = store.snapshot.calendar
        let start = day.startDate(in: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-60) ?? start
        return start...max(start, min(end, CompanionClock.now()))
    }

    private var startedAt: Date {
        let lasting = routine.tracks(.duration) ? duration : 0
        return min(max(when.start(now: CompanionClock.now(), lasting: lasting), dayRange.lowerBound), dayRange.upperBound)
    }

    /// "back by 6:32pm" next to the Started label, so the saved times are never a guess.
    private var timingNote: String? {
        guard routine.tracks(.duration) else { return nil }
        let end = when.start(now: report.now, lasting: duration).addingTimeInterval(Double(duration) * 60)
        return "back by \(CareText.timeWithPeriod(end, calendar: store.snapshot.calendar))"
    }

    private func setDefaults() {
        guard !didSetDefaults else { return }
        didSetDefaults = true
        store.lastError = nil
        if let editing {
            let draft = CareLogDraft(editing)
            people = draft.people
            when = .at(draft.occurredAt)
            duration = draft.durationMinutes ?? duration
            pee = draft.pee ?? false
            poo = draft.poo ?? false
            vibe = draft.vibe ?? vibe
            note = draft.note ?? ""
            return
        }
        if let first = model.people.first?.id {
            people = [first]
        }
        if let catchUp {
            when = .at(usualTime(catchUp.slot))
        }
        // Start from the usual length of recent logs.
        let recent = store.snapshot.entries(of: routine.id).suffix(10).compactMap(\.log.durationMinutes)
        if !recent.isEmpty {
            let average = recent.reduce(0, +) / recent.count
            duration = Self.durations.min { abs($0 - average) < abs($1 - average) } ?? 20
        }
    }

    private func save() {
        let draft = CareLogDraft(
            people: people,
            occurredAt: startedAt,
            durationMinutes: routine.tracks(.duration) ? duration : nil,
            pee: routine.tracks(.pee) ? pee : nil,
            poo: routine.tracks(.poo) ? poo : nil,
            vibe: routine.tracks(.vibe) ? vibe : nil,
            note: note
        )
        if let editing {
            if store.updateLog(id: editing.id, draft) { onClose() }
            return
        }
        guard store.log(routineId: routine.id ?? -1, draft) != nil else { return }
        onSaved(Celebration.after(report: report, routine: routine, people: people, names: store.snapshot.names, calendar: store.snapshot.calendar))
    }

    private func delete() {
        guard let editing else { return }
        store.deleteLog(id: editing.id)
        onClose()
    }
}

// MARK: - Celebration

struct Celebration: Equatable {
    var title: String
    var message: String
    var stars: Int
    var confetti: [String]

    /// The celebration for a log just saved on top of `report` (taken before the save).
    static func after(report: CompanionReport, routine: CareRoutine, people: [Int64], names: [Int64: String], calendar: Calendar) -> Celebration {
        let firstNames = people.compactMap { names[$0] }
        let who = firstNames.isEmpty ? "" : ", " + CaptionEngine.whoText(people, names: names)
        let today = report.primary?.routine.id == routine.id ? report.primary : report.others.first { $0.routine.id == routine.id }
        let countToday = (today?.slots.filter(\.isDone).count ?? 0) + 1
        let noun = routine.kind.noun(title: routine.title)
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
