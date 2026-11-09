import SwiftUI

/// Which routine to log for which companion.
struct CareLogRequest: Identifiable, Equatable {
    var companionId: Int64
    var routineId: Int64
    /// The celebration's button, e.g. "Back to today".
    var returnTitle = "Back to today"
    /// Skip the form and show the celebration (DEBUG screenshots only).
    var celebrateOnly = false

    var id: String { "\(companionId)-\(routineId)" }
}

extension View {
    /// Presents the log sheet, then the celebration, over the whole wall.
    func careLogFlow(_ request: Binding<CareLogRequest?>) -> some View {
        wallCover(item: request) { item in
            CareLogFlow(request: item) { CompanionCover.instantly { request.wrappedValue = nil } }
        }
    }
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
                        CareLogForm(report: report, routine: routine) { result in
                            withAnimation(.easeOut(duration: 0.3)) { celebration = result }
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

/// The "Who walked Yo-Yo?" form. Only the routine's tracked fields are shown.
private struct CareLogForm: View {
    let report: CompanionReport
    let routine: CareRoutine
    let onSaved: (Celebration) -> Void

    @Environment(CompanionStore.self) private var store
    @Environment(AppModel.self) private var model

    @State private var people: [Int64] = []
    @State private var duration = 20
    @State private var pee = true
    @State private var poo = true
    @State private var vibe: CareVibe = .smooth
    @State private var endedMinutesAgo = 0
    @State private var note = ""
    @State private var didSetDefaults = false

    private static let durations = [10, 20, 30, 45, 60]
    private static let endedOptions = [0, 15, 30, 60, 120, 240]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CompanionFace(look: report.look, expression: report.expression, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.kind.question(name: report.name, title: routine.title))
                        .font(.display(30))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Tap everyone who came along")
                        .font(.body(14, weight: 600))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.trailing, 44)
            }
            label(routine.kind == .walk ? "Walkers" : "Who")
            FlowLayout(spacing: 14) {
                ForEach(model.people) { person in
                    personButton(person)
                }
            }
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
                .fieldStyle()
            HStack {
                Menu {
                    ForEach(Self.endedOptions, id: \.self) { minutes in
                        Button(minutes == 0 ? "Just now" : "\(CompanionReport.durationText(minutes)) ago") { endedMinutesAgo = minutes }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(timingText)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
                }
                Spacer()
                if let error = store.lastError {
                    Text(error).font(.body(13, weight: 600)).foregroundStyle(Theme.accent).lineLimit(2)
                }
                Button(action: save) {
                    Label("Save \(routine.kind.noun(title: routine.title))", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(people.isEmpty)
            }
            .padding(.top, 22)
        }
        .onAppear(perform: setDefaults)
    }

    private func label(_ text: String) -> some View {
        SectionLabel(text)
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

    private var endedAt: Date { report.now.addingTimeInterval(-Double(endedMinutesAgo) * 60) }

    private var startedAt: Date {
        routine.tracks(.duration) ? endedAt.addingTimeInterval(-Double(duration) * 60) : endedAt
    }

    private var timingText: String {
        let calendar = store.snapshot.calendar
        let ended = endedMinutesAgo == 0 ? "Ended just now" : "Ended \(CompanionReport.durationText(endedMinutesAgo)) ago"
        guard routine.tracks(.duration) else { return endedMinutesAgo == 0 ? "Just now" : ended }
        return "\(ended) · started \(CareText.timeWithPeriod(startedAt, calendar: calendar))"
    }

    private func setDefaults() {
        guard !didSetDefaults else { return }
        didSetDefaults = true
        let today = report.primary?.routine.id == routine.id ? report.primary : report.others.first { $0.routine.id == routine.id }
        if let turn = today?.nextTurn {
            people = [turn]
        } else if let first = model.people.first?.id {
            people = [first]
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
        guard store.log(routineId: routine.id ?? -1, draft) != nil else { return }
        onSaved(Celebration.after(report: report, routine: routine, people: people, names: store.snapshot.names, calendar: store.snapshot.calendar))
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
        let person = report.primary?.nextTurn.map { [$0] } ?? []
        return after(report: report, routine: routine, people: person, names: [:], calendar: .current)
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
