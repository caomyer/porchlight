import SwiftUI

/// Today on the phone, mine first, then ours: care that is due leads, then my chores,
/// then what anyone can take, then today's calendar if this phone may already read it.
/// Everything is read from the live stores, so what the wall logs shows up here as it
/// lands in the database.
struct PocketTodayScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(CompanionStore.self) private var companions
    @Environment(HomeStore.self) private var home
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.me) private var me

    @State private var path: [PocketRoute] = []
    @State private var careSheet: PocketCareSheet.Request?
    /// On a shared screen, what is waiting for someone to say who did it.
    @State private var asking: WhoDidIt?
    @AppStorage("pocket.dismissedCatchUps") private var dismissedCatchUps = ""

    var body: some View {
        NavigationStack(path: $path) {
            today
                .navigationTitle("Today")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: PocketRoute.self) { route in
                    Group {
                        switch route {
                        case let .companion(id): PocketCompanionWeek(companionId: id, logging: logging)
                        case .pitchIn: PocketPitchIn(logging: logging)
                        case .nextWeek: PocketNextWeek()
                        case .calendars: PocketCalendars()
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { PocketYouButton() }
                    }
                    .toolbarBackground(Theme.background, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
                }
        }
        .tint(Theme.accent)
    }

    private var today: some View {
        TimelineView(.everyMinute) { _ in
            let now = CompanionClock.now()
            let reports = companions.companions.compactMap { companions.report(for: $0.id, now: now) }
            let cards = PocketToday.cards(reports, calendar: companions.snapshot.calendar)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PocketHeader(
                        small: now.formatted(dateStyle), title: me.map { "Hi, \($0.name)" } ?? "Today",
                        household: model.isInSeveralHouseholds ? model.household?.name : nil
                    )
                    // One banner at a time: sync's, when it is stuck, comes first.
                    PocketSyncBanner { catchUpBanner(reports) }
                    if !cards.isEmpty {
                        PocketCareSection(cards: cards, handlers: careHandlers)
                    }
                    chores
                    PocketAgendaCard { path.append($0) }
                    if cards.isEmpty && home.activeChores.isEmpty {
                        PocketSetUpCard(
                            emoji: "🏡",
                            title: "Nothing to do yet",
                            detail: "Add a pet or plant to look after, and the household's chores. They show up here for everyone, on every phone and the wall.",
                            action: "Set up the household",
                            page: .household
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.background)
        .paperUnderStatusBar()
        .sheet(item: $careSheet, onDismiss: toasts.showPending) { request in
            PocketCareSheet(request: request, logging: logging.inSheet)
        }
        .confirmationDialog(asking?.question ?? "", isPresented: isAsking, titleVisibility: .visible, presenting: asking) { pending in
            ForEach(model.people) { person in
                Button(person.name) { pending.run(person.id) }
            }
        }
        .onAppear(perform: openDebugSheet)
    }

    private var dateStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        style.timeZone = companions.snapshot.calendar.timeZone
        return style
    }

    private var logging: PocketLogging {
        PocketLogging(companions: companions, home: home, toasts: toasts, me: me?.id)
    }

    // MARK: Care

    private var careHandlers: PocketCareHandlers {
        PocketCareHandlers(
            log: { card, action, alsoWent in
                credit(question: CareWords(action.routine, species: card.report.companion.species).question(name: card.report.name)) { person in
                    logging.log(action, companion: card.report.name, people: [person] + alsoWent)
                }
            },
            more: { card, routine, alsoWent in
                careSheet = PocketCareSheet.Request(companionId: card.id, routineId: routine.id, people: (me.map { [$0.id] } ?? []) + alsoWent)
            },
            open: { card in path.append(.companion(card.id)) },
            edit: { card, entry in careSheet = .edit(entry, companionId: card.id) }
        )
    }

    @ViewBuilder
    private func catchUpBanner(_ reports: [CompanionReport]) -> some View {
        let dismissed = Set(dismissedCatchUps.split(separator: "\n").map(String.init))
        if let found = PocketToday.catchUp(reports, snapshot: companions.snapshot, dismissed: dismissed) {
            let (report, missed) = found
            let calendar = companions.snapshot.calendar
            let slot = CareCatchUp.slotName(missed.slot.window, of: missed.routine)
            let when = missed.day == report.today ? "" : " " + PocketCareWords.dayWord(missed.day, today: report.today, calendar: calendar)
            StatusBanner(
                tone: .warn, emoji: missed.routine.emoji,
                title: "\(report.name.possessive) \(slot) wasn't logged\(when)",
                detail: missed.slot.window.isAllDay ? nil : "Usually \(missed.slot.window.rangeText)",
                action: ("Log it", { careSheet = .catchUp(missed, companionId: report.id, people: me.map { [$0.id] } ?? []) }),
                onDismiss: { dismiss(missed) }
            )
            .accessibilityIdentifier("catch-up")
        }
    }

    /// Leaves a missed slot alone from now on, on this device. Only the latest few are
    /// kept: older ones have left the catch-up week anyway.
    private func dismiss(_ missed: MissedCare) {
        let kept = dismissedCatchUps.split(separator: "\n").map(String.init).suffix(40)
        dismissedCatchUps = (kept + [missed.id]).joined(separator: "\n")
    }

    // MARK: Chores

    @ViewBuilder
    private var chores: some View {
        if let me {
            let chores = PocketToday.chores(home.board(people: model.people), me: me.id)
            YoursTodayCard(tasks: chores.mine, starsToday: PocketToday.stars(home.snapshot.earnings, me: me.id, on: home.today), onSeeAll: { path.append(.pitchIn) }) { chore in
                logging.complete(chore, by: me.id)
            }
            if !chores.anyone.isEmpty {
                AnyoneCanTakeCard(tasks: chores.anyone) { chore in logging.complete(chore, by: me.id) }
            }
        } else {
            // A shared screen has nobody's own chores; anyone can take any of them.
            let anyone = home.board(people: model.people).columns.flatMap(\.tasks)
            if !anyone.isEmpty {
                AnyoneCanTakeCard(tasks: anyone) { chore in
                    if chore.ownerId != nil {
                        logging.complete(chore, by: nil)
                    } else {
                        credit(question: "Who did \(chore.title.lowercased())?") { logging.complete(chore, by: $0) }
                    }
                }
            }
        }
    }

    // MARK: Who did it

    /// Credits me on a personal device; a shared screen asks who it was first.
    private func credit(question: String, then run: @escaping (Person.ID) -> Void) {
        if let me {
            run(me.id)
        } else {
            asking = WhoDidIt(question: question, run: run)
        }
    }

    private var isAsking: Binding<Bool> {
        Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })
    }

    struct WhoDidIt {
        let question: String
        let run: (Person.ID) -> Void
    }

    // MARK: Debug

    /// `-debugCompanionSheet log|catchUp` opens the care sheet for a new log or for the
    /// missed slot Today's banner offers, for screenshots.
    private func openDebugSheet() {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "startScreen") {
        case "week": if let first = companions.companions.first { path = [.companion(first.id)] }
        case "pitchIn": path = [.pitchIn]
        case "nextWeek": path = [.nextWeek]
        case "calendars": path = [.calendars]
        default: break
        }
        let mode = UserDefaults.standard.string(forKey: "debugCompanionSheet")
        guard let first = companions.companions.first, let report = companions.report(for: first.id) else { return }
        switch mode {
        case "log":
            if let routine = report.primaryRoutine {
                careSheet = PocketCareSheet.Request(companionId: first.id, routineId: routine.id, people: me.map { [$0.id] } ?? [])
            }
        case "catchUp":
            let reports = companions.companions.compactMap { companions.report(for: $0.id) }
            if let found = PocketToday.catchUp(reports, snapshot: companions.snapshot, dismissed: []) {
                careSheet = .catchUp(found.missed, companionId: found.report.id, people: me.map { [$0.id] } ?? [])
            }
        default: break
        }
        #endif
    }
}

/// Where Today can go.
enum PocketRoute: Hashable {
    case companion(Companion.ID)
    case pitchIn
    case nextWeek
    case calendars
}

extension PocketCareWords {
    /// "yesterday", "on Saturday": when something missed was due.
    static func dayWord(_ day: DayKey, today: DayKey, calendar: Calendar) -> String {
        if day == today.adding(days: -1, calendar: calendar) { return "yesterday" }
        return "on " + day.formatted(.dateTime.weekday(.wide), calendar: calendar)
    }
}

/// Today's calendar, with the next 7 days a tap away. With no calendars to show yet it
/// is a single row to the Calendars page, which explains before asking for access.
struct PocketAgendaCard: View {
    let open: (PocketRoute) -> Void

    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendarStore

    var body: some View {
        if !calendarStore.showsOwnCalendars && !calendarStore.hasOthersCalendars {
            Button { open(.calendars) } label: {
                HStack(spacing: 10) {
                    Text("📅").phoneFont(.body, 20).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("No calendars chosen").phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                        Text("Choose which of this \(DeviceWords.this)'s calendars show on Today")
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("choose-calendars")
            .phoneCard()
        } else {
            let today = calendarStore.today
            let allDay = calendarStore.allDayItems(for: today)
            let timed = calendarStore.timelineItems(for: today)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    PhoneCardHeader(title: "At home today")
                    Spacer(minLength: 8)
                    Button { open(.nextWeek) } label: {
                        Text("Next 7 days ›")
                            .phoneFont(.body, 12, weight: 800, relativeTo: .caption)
                            .foregroundStyle(Theme.accent)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("next-7-days")
                }
                if allDay.isEmpty && timed.isEmpty {
                    Text("Nothing on the calendars today.")
                        .phoneFont(.body, 13.5, weight: 600)
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 7)
                }
                VStack(spacing: 0) {
                    ForEach(Array(allDay.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        row(time: "All day", title: item.title, subtitle: nil, owners: owners(item.id, item.owner))
                    }
                    ForEach(Array(timed.enumerated()), id: \.element.id) { index, item in
                        if index > 0 || !allDay.isEmpty { RowDivider() }
                        row(time: ClockFormat.time(item.time, calendar: calendarStore.calendar), title: item.title, subtitle: item.subtitle, owners: owners(item.id, item.owner))
                    }
                }
                StaleCalendarLines(sources: calendarStore.staleSources, fontSize: 12)
                    .padding(.top, 4)
                if !calendarStore.showsOwnCalendars {
                    RowDivider()
                    Button { open(.calendars) } label: {
                        HStack(spacing: 8) {
                            Text("Add this \(DeviceWords.this)'s calendars")
                                .phoneFont(.body, 13, weight: 700, relativeTo: .footnote)
                                .foregroundStyle(Theme.accent)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").phoneFont(.body, 12, weight: 800, relativeTo: .footnote).foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("choose-calendars")
                }
            }
            .phoneCard()
        }
    }

    /// Everyone the event is for: the owner, and anyone else with the same event.
    private func owners(_ itemId: String, _ owner: Owner) -> [Owner] {
        calendarStore.event(id: String(itemId.dropFirst("calendar-".count)))?.owners ?? [owner]
    }

    private func row(time: String, title: String, subtitle: String?, owners: [Owner]) -> some View {
        AdaptiveRow {
            Text(time)
                .phoneFont(.body, 12, weight: 700, relativeTo: .caption)
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 46, alignment: .leading)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                    if let subtitle {
                        Text(subtitle)
                            .phoneFont(.body, 12, weight: 600, relativeTo: .caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                PocketFaces(owners: owners)
            }
        }
        .padding(.vertical, 7)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// The small faces of everyone an event is for; none for the whole household.
struct PocketFaces: View {
    let owners: [Owner]
    @Environment(AppModel.self) private var model

    var body: some View {
        let people = owners.compactMap { owner -> Person? in
            if case let .person(id) = owner { return model.person(id) } else { return nil }
        }
        if !people.isEmpty {
            HStack(spacing: -8) {
                ForEach(people) { person in
                    PersonAvatar(person, size: .small)
                        .background(Circle().fill(Theme.surface).padding(-1.5))
                }
            }
        }
    }
}
