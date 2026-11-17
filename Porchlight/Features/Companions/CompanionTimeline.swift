import SwiftUI

/// Care logs and still-expected care as Today agenda rows.
enum CompanionTimeline {
    static func items(snapshot: CompanionSnapshot, day: DayKey, now: Date) -> [TimelineItem] {
        let calendar = snapshot.calendar
        let today = DayKey(now, calendar: calendar)
        var items: [TimelineItem] = []
        for companion in snapshot.companions {
            let companionId = companion.id
            let routines = snapshot.routines(of: companionId)
            let look = snapshot.look(of: companion)
            let expression = expression(for: routines.first, snapshot: snapshot, now: now)
            let face = AnyView(CompanionFace(look: look, expression: expression, size: 30))
            for (index, routine) in routines.enumerated() {
                let entries = snapshot.entries(of: routine.id)
                let byDay = CareLogic.byDay(entries, calendar: calendar)
                let dayEntries = byDay[day] ?? []
                let captions = dayEntries.isEmpty || companion.captionTone == .off ? [:] : CaptionEngine.captions(
                    for: entries, tone: companion.captionTone, name: companion.name, routine: routine,
                    names: snapshot.names, calendar: calendar
                )
                for entry in dayEntries {
                    items.append(logItem(entry, routine: routine, companion: companion, caption: captions[entry.id], face: face, snapshot: snapshot))
                }
                // Earlier this week, every routine's missed slots show where they'd be, to catch up on.
                for missed in CareCatchUp.missed(routine, entries: entries, on: day, now: now, calendar: calendar, since: companion.createdAt) {
                    items.append(missedItem(missed, companion: companion, face: face))
                }
                // Only the main routine (the walk) is expected on the agenda; the rest show once logged.
                guard day == today, index == 0 else { continue }
                let state = CompanionReport.routineToday(routine, entries: entries, today: today, now: now, calendar: calendar)
                for slot in state.slots where slot.isPendingToday {
                    items.append(expectedItem(
                        slot, routine: routine, companion: companion, entries: entries,
                        face: face, snapshot: snapshot, now: now
                    ))
                }
            }
        }
        return items
    }

    static func expression(for primary: CareRoutine?, snapshot: CompanionSnapshot, now: Date) -> FaceExpression {
        guard let primary else { return .happy }
        let last = snapshot.entries(of: primary.id).last?.time
        return FaceExpression(mood: CareLogic.mood(lastCare: last, interval: CareLogic.interval(for: primary), now: now))
    }

    private static func logItem(
        _ entry: CareEntry, routine: CareRoutine, companion: Companion, caption: String?, face: AnyView, snapshot: CompanionSnapshot
    ) -> TimelineItem {
        let who = CaptionEngine.whoText(entry.people, names: snapshot.names)
        var title = routine.kind.sentence(who: who, name: companion.name, title: routine.title)
        if let minutes = entry.log.durationMinutes { title += " · \(minutes) min" }
        let story = entry.log.note.map { "\"\($0)\"" } ?? caption
        let subtitle = [CareText.business(entry.log, spaced: true), story].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return TimelineItem(
            id: "care-log-\(entry.id)",
            kind: .log,
            time: entry.time,
            title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            owner: entry.people.count == 1 ? .person(entry.people[0]) : .everyone,
            leading: face,
            trailing: AnyView(CarerAvatar(carers: Carers(entry.people, snapshot: snapshot))),
            target: .careLog(companionId: companion.id, routineId: entry.log.careRoutineId, logId: entry.id),
            origin: RowOrigin(rowId: entry.log.id.description, deviceId: entry.log.deviceId)
        )
    }

    private static func expectedItem(
        _ slot: CareSlot, routine: CareRoutine, companion: Companion, entries: [CareEntry],
        face: AnyView, snapshot: CompanionSnapshot, now: Date
    ) -> TimelineItem {
        let calendar = snapshot.calendar
        let day = DayKey(now, calendar: calendar)
        let windows = routine.effectiveWindows
        let recent = entries.filter { $0.time > now.addingTimeInterval(-14 * 24 * 3600) }
        let typical = CareLogic.typicalMinute(slot: slot.index, windows: windows, history: recent, calendar: calendar)

        var time: Date
        var label: String
        if let typical {
            time = CareLogic.date(day, minute: typical, calendar: calendar)
            label = "~" + CareTime.hour(typical, withPeriod: false)
        } else {
            time = now
            label = "Today"
        }
        if time <= now {
            // Overdue or due now: keep it just after the NOW line.
            time = now.addingTimeInterval(1)
            label = slot.state == .late ? "Late" : "Now"
        }

        let lead: String
        switch slot.state {
        case .late: lead = "Was due \(slot.window.rangeText)"
        case .due: lead = "Due now · \(slot.window.rangeText)"
        default: lead = slot.window.isAllDay ? "Due today" : "Usually \(slot.window.rangeText)"
        }
        return TimelineItem(
            id: "care-expected-\(routine.id)-\(slot.index)",
            kind: .expected,
            time: time,
            timeLabel: label,
            title: expectedTitle(slot, routine: routine, companion: companion),
            subtitle: lead,
            owner: .everyone,
            leading: face,
            trailing: AnyView(PawDot(carers: nil, size: 24)),
            target: .careDue(companionId: companion.id, routineId: routine.id)
        )
    }

    private static func missedItem(_ missed: MissedCare, companion: Companion, face: AnyView) -> TimelineItem {
        let window = missed.slot.window
        let target = TimelineTarget.careMissed(companionId: companion.id, routineId: missed.routine.id, day: missed.day, slot: missed.slot.index)
        return TimelineItem(
            id: "care-missed-\(missed.id)",
            kind: .expected,
            time: missed.usual,
            timeLabel: "Not logged",
            title: expectedTitle(missed.slot, routine: missed.routine, companion: companion),
            subtitle: window.isAllDay ? nil : "Usually \(window.rangeText)",
            owner: .everyone,
            leading: face,
            trailing: AnyView(PawDot(carers: nil, size: 24)),
            target: target
        )
    }

    /// "Evening walk", "Water Fern", "Feed Mochi · Breakfast".
    static func expectedTitle(_ slot: CareSlot, routine: CareRoutine, companion: Companion) -> String {
        if routine.kind == .walk && !slot.window.isAllDay { return "\(slot.window.label) walk" }
        let base = "\(routine.title) \(companion.name)"
        return slot.window.isAllDay || routine.slotsPerDay == 1 ? base : "\(base) · \(slot.window.label)"
    }
}

/// Paw lanes inside month cells (the week and day grids show each walk at its time).
enum CompanionLanes {
    static func lanes(snapshot: CompanionSnapshot) -> [CalendarLane] {
        snapshot.companions.compactMap { companion in
            let companionId = companion.id
            let routines = snapshot.routines(of: companionId).filter(\.isWalkLike)
            guard !routines.isEmpty else { return nil }
            let look = snapshot.look(of: companion)
            return CalendarLane(
                id: "companion-\(companionId)",
                styles: [.month],
                label: AnyView(CompanionFace(look: look, size: 24).accessibilityLabel(companion.name)),
                title: "walks",
                cell: { day, style in
                    let marks = marks(routines: routines, snapshot: snapshot, day: day, now: CompanionClock.now())
                    switch style {
                    case .week, .day: return AnyView(WeekPaws(marks: marks))
                    case .month: return AnyView(MonthPaws(count: marks.compactMap { $0 }.count, tint: look.tint))
                    }
                }
            )
        }
    }

    /// One mark per log that day (walker colors), then a ghost (nil) per slot still expected today.
    static func marks(routines: [CareRoutine], snapshot: CompanionSnapshot, day: DayKey, now: Date) -> [Carers?] {
        let calendar = snapshot.calendar
        var marks: [Carers?] = []
        var pending = 0
        for routine in routines {
            let entries = snapshot.entries(of: routine.id)
            let byDay = CareLogic.byDay(entries, calendar: calendar)
            marks += (byDay[day] ?? []).map { Carers($0.people, snapshot: snapshot) }
            pending += CareLogic.slots(for: routine, on: day, byDay: byDay, now: now, calendar: calendar)
                .filter(\.isPendingToday).count
        }
        return marks + Array(repeating: nil, count: pending)
    }
}

private struct WeekPaws: View {
    var marks: [Carers?]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(marks.indices, id: \.self) { index in
                PawDot(carers: marks[index], size: 24)
            }
        }
    }
}

private struct MonthPaws: View {
    var count: Int
    var tint: Color

    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                ForEach(0..<min(count, 3), id: \.self) { _ in
                    Image(systemName: "pawprint.fill").font(.system(size: 9.5, weight: .semibold))
                }
                if count > 3 {
                    Text("+\(count - 3)").font(.body(10.5, weight: 700))
                }
            }
            .foregroundStyle(tint)
            .accessibilityLabel("\(count) logged")
        }
    }
}
