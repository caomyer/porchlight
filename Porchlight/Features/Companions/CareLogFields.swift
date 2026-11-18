import Foundation

/// What a care log form holds, and how it becomes a log. The wall's log sheet and the
/// phone's care sheet lay these out differently but share every rule here.
struct CareLogFields: Equatable {
    var people: [Person.ID] = []
    var duration = 20
    var pee = true
    var poo = true
    var vibe: CareVibe = .smooth
    var when: LogTime = .justNow
    var note = ""

    /// The lengths offered for a walk.
    static let durations = [10, 20, 30, 45, 60]

    /// "20 min", "1 hr+" for the hour choice; a saved length past it says its minutes.
    static func durationTitle(_ minutes: Int) -> String {
        minutes == 60 ? "1 hr+" : "\(minutes) min"
    }

    /// The length a log being fixed was saved with, when it isn't one of `durations`.
    var savedDuration: Int?

    /// The lengths to offer: the usual ones, plus the one a log being fixed was saved with
    /// when it isn't among them ("12 min"), in order, so the form shows what is saved and
    /// can go back to it.
    var durationChoices: [Int] {
        guard let savedDuration, !Self.durations.contains(savedDuration) else { return Self.durations }
        return (Self.durations + [savedDuration]).sorted()
    }

    /// A new log by `people`: at the slot's usual time when catching up, else just now,
    /// lasting about as long as the routine's recent logs.
    static func new(people: [Person.ID], for day: CareLogDay, catchUpSlot: Int?) -> CareLogFields {
        var fields = CareLogFields(people: people)
        if let catchUpSlot {
            fields.when = .at(day.usualTime(catchUpSlot))
        }
        let recent = day.history.suffix(10).compactMap(\.log.durationMinutes)
        if !recent.isEmpty {
            let average = recent.reduce(0, +) / recent.count
            fields.duration = durations.min { abs($0 - average) < abs($1 - average) } ?? 20
        }
        return fields
    }

    /// The log as it stands, for fixing it.
    init(editing entry: CareEntry) {
        let draft = CareLogDraft(entry)
        people = draft.people
        when = .at(draft.occurredAt)
        duration = draft.durationMinutes ?? duration
        savedDuration = draft.durationMinutes
        pee = draft.pee ?? false
        poo = draft.poo ?? false
        vibe = draft.vibe ?? vibe
        note = draft.note ?? ""
    }

    init(people: [Person.ID] = []) {
        self.people = people
    }

    /// Adds someone, or takes them off when already picked.
    mutating func toggle(_ person: Person.ID) {
        if people.contains(person) { people.removeAll { $0 == person } } else { people.append(person) }
    }

    /// The log to store, keeping only what the routine tracks.
    func draft(for day: CareLogDay) -> CareLogDraft {
        let routine = day.routine
        return CareLogDraft(
            people: people,
            occurredAt: day.startedAt(self),
            durationMinutes: routine.tracks(.duration) ? duration : nil,
            pee: routine.tracks(.pee) ? pee : nil,
            poo: routine.tracks(.poo) ? poo : nil,
            vibe: routine.tracks(.vibe) ? vibe : nil,
            note: note
        )
    }
}

/// The care sheet's words for fixing a log, the same on the wall and the phone.
enum CareLogWording {
    /// "Edit walk", "Edit feed".
    static func editTitle(_ routine: CareRoutine) -> String {
        "Edit " + routine.kind.noun(title: routine.title)
    }

    static let editSubtitle = "Fix who, when or how it went"
    static let saveChanges = "Save changes"
    /// The first tap on removing, which only asks.
    static let remove = "Remove"
    /// Backing out of removing.
    static let keep = "Keep it"

    /// "Remove walk": the second tap, which removes it and the stars it earned.
    static func confirmRemove(_ routine: CareRoutine) -> String {
        "Remove " + routine.kind.noun(title: routine.title)
    }
}

/// The day a care log belongs to, and the times it can take on it.
struct CareLogDay {
    /// The day a care sheet works on: the day of the log being fixed, else a missed slot's
    /// day, else today.
    static func forSheet(
        routine: CareRoutine, editing: CareEntry?, catchUpDay: DayKey?, today: DayKey, now: Date, calendar: Calendar, history: [CareEntry]
    ) -> CareLogDay {
        let day = editing.map { DayKey($0.time, calendar: calendar) } ?? catchUpDay ?? today
        return CareLogDay(routine: routine, day: day, today: today, now: now, calendar: calendar, history: history)
    }

    let routine: CareRoutine
    /// The log's day: the day of the one being fixed, a missed slot's day, or today.
    let day: DayKey
    let today: DayKey
    /// "Now" as the sheet opened, for its wording.
    let now: Date
    let calendar: Calendar
    /// The routine's logs, oldest first.
    let history: [CareEntry]

    var isToday: Bool { day == today }

    /// How long the log lasts, for times that mean "it just ended".
    func lasting(_ fields: CareLogFields) -> Int {
        routine.tracks(.duration) ? fields.duration : 0
    }

    /// The day's start up to now, or its last minute for an earlier day.
    var range: ClosedRange<Date> {
        let start = day.startDate(in: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-60) ?? start
        return start...max(start, min(end, CompanionClock.now()))
    }

    /// When the log started, kept inside the day.
    func startedAt(_ fields: CareLogFields) -> Date {
        min(max(fields.when.start(now: CompanionClock.now(), lasting: lasting(fields)), range.lowerBound), range.upperBound)
    }

    /// "back by 6:32pm" next to the start, so the saved times are never a guess.
    func timingNote(_ fields: CareLogFields) -> String? {
        guard routine.tracks(.duration) else { return nil }
        let end = fields.when.start(now: now, lasting: fields.duration).addingTimeInterval(Double(fields.duration) * 60)
        return "back by \(CareText.timeWithPeriod(end, calendar: calendar))"
    }

    /// The time card's one-tap choices: recent times today, or the day's slots at their
    /// usual times on an earlier day.
    var suggestions: [(title: String, time: LogTime)] {
        if isToday { return LogTime.recentSuggestions(justNow: routine.tracks(.duration) ? "Just got back" : "Just now") }
        return routine.effectiveWindows.indices.compactMap { index in
            let window = routine.effectiveWindows[index]
            guard !window.isAllDay else { return nil }
            return (window.label, .at(usualTime(index)))
        }
    }

    /// When a slot usually happens on this day.
    func usualTime(_ slot: Int) -> Date {
        CareCatchUp.usualTime(slot, of: routine, on: day, entries: history, now: now, calendar: calendar)
    }
}
