import SwiftUI

/// Adding or changing an event in a real calendar (docs/proposals/family-calendar.html, "New
/// event"; docs/design/calendar-add-edit.md). A new one starts as one line ("Leo dentist thu
/// 4pm"), read as it is typed into the fields below it, "Reads as ..."; every field is then
/// its own to change, and the line never overwrites one that was. Shared by the phone and the
/// wall, which shows it bigger.
struct PocketEventEditor: View {
    /// What it starts from: a new event in `calendar`, or a change to an existing one.
    enum Start: Identifiable {
        case new(ExternalCalendar)
        case edit(CalendarEvent, EventDraft)
        var id: String {
            switch self {
            case let .new(calendar): "new-\(calendar.id)"
            case let .edit(event, _): "edit-\(event.id)"
            }
        }
    }

    let start: Start
    /// A line already typed into a new event, read as if typed (the hosted looks start here).
    var startingLine = ""
    /// Told once the event is saved, with what to say.
    var onSaved: (String) -> Void = { _ in }

    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var line = ""
    @State private var title = ""
    @State private var begin = Date()
    @State private var end = Date()
    @State private var isAllDay = false
    @State private var repeats: EventRepeat?
    @State private var location = ""
    @State private var notes = ""
    @State private var people: Set<Person.ID> = []
    /// Fields the person changed themselves, which the line leaves alone.
    @State private var edited: Set<String> = []
    @State private var askingSpan = false
    @State private var failure: String?
    @State private var loaded = false
    @FocusState private var lineFocused: Bool

    private var isNew: Bool { if case .new = start { true } else { false } }

    private var calendar: ExternalCalendar? {
        switch start {
        case let .new(calendar): calendar
        case let .edit(_, draft): store.calendars.first { $0.id == draft.calendarId }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isNew { lineField } else { titleField }
                    forChips
                    whenFields
                    repeatsField
                    textField("Where", text: $location, field: "location", id: "event-where")
                    textField("Notes", text: $notes, field: "notes", id: "event-notes", axis: .vertical)
                    if let calendar {
                        Text("Saved in \(calendar.title) · \(calendar.accountKind)")
                            .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("event-saved-in")
                    }
                    if let failure {
                        Text(failure)
                            .phoneFont(.body, 13, weight: 700, relativeTo: .footnote)
                            .foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("event-failure")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(Theme.background)
            .navigationTitle(isNew ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { saveTapped() }
                        .fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("event-save")
                }
            }
            .confirmationDialog("This is a repeating event", isPresented: $askingSpan, titleVisibility: .visible) {
                Button("Save for this event only") { save(span: .thisEvent) }
                Button("Save for future events") { save(span: .futureEvents) }
                    .accessibilityIdentifier("span-future")
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear(perform: load)
    }

    // MARK: The line

    private var lineField: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Wraps rather than scrolls, so the whole line can be read back at any size.
            TextField("Leo dentist thu 4pm", text: $line, axis: .vertical)
                .lineLimit(1...4)
                .phoneFont(.body, 17, weight: 600)
                .focused($lineFocused)
                .submitLabel(.done)
                .fieldStyle()
                .onChange(of: line) { _, newLine in
                    // Return is Done: it ends the line instead of starting another.
                    if newLine.contains("\n") {
                        line = newLine.replacingOccurrences(of: "\n", with: "")
                        lineFocused = false
                        return
                    }
                    read(newLine)
                }
                .accessibilityIdentifier("event-line")
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                (Text("Reads as ").foregroundStyle(Theme.muted) + Text(readsAs).fontWeight(.heavy).foregroundStyle(Theme.ink))
                    .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("event-reads-as")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Leo dentist · Thursday, Nov 26 · 4:00 PM"
    private var readsAs: String {
        let calendar = store.calendar
        let day = EventText.format(begin, calendar, "EEEE, MMM d")
        let time = isAllDay ? "All day" : ClockFormat.phoneTime(begin, calendar: calendar)
        return [title.isEmpty ? nil : title, day, time].compactMap { $0 }.joined(separator: " · ")
    }

    private func read(_ text: String) {
        let reading = EventLine.read(text, now: store.now(), calendar: store.calendar, people: store.people)
        if !edited.contains("title") { title = reading.title }
        if !edited.contains("when") {
            begin = reading.start
            end = reading.end
            isAllDay = reading.isAllDay
        }
        if !edited.contains("for") { people = Set(reading.forIds) }
    }

    private var titleField: some View {
        textField("Title", text: $title, field: "title", id: "event-title")
    }

    // MARK: Fields

    private var forChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("For")
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(store.people) { person in
                    PhoneChoice(title: person.name, isOn: people.contains(person.id)) {
                        edited.insert("for")
                        if people.contains(person.id) { people.remove(person.id) } else { people.insert(person.id) }
                    }
                    .accessibilityIdentifier("event-for-\(person.name)")
                }
                PhoneChoice(title: "Everyone", isOn: people.isEmpty) {
                    edited.insert("for")
                    people = []
                }
                .accessibilityIdentifier("event-for-everyone")
            }
        }
    }

    private var whenFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("When")
            VStack(spacing: 0) {
                Toggle("All day", isOn: Binding(get: { isAllDay }, set: { edited.insert("when"); isAllDay = $0 }))
                    .phoneFont(.body, 15, weight: 600)
                    .tint(Theme.accent)
                    .frame(minHeight: 44)
                RowDivider()
                dateRow("Starts", selection: Binding(get: { begin }, set: { new in
                    edited.insert("when")
                    let length = end.timeIntervalSince(begin)
                    begin = new
                    end = new.addingTimeInterval(max(length, 0))
                }))
                .accessibilityIdentifier("event-starts")
                if !isAllDay {
                    RowDivider()
                    dateRow("Ends", selection: Binding(get: { end }, set: { edited.insert("when"); end = max($0, begin) }), from: begin)
                }
            }
            .environment(\.timeZone, store.calendar.timeZone)
            .phoneCard()
        }
    }

    /// "Starts" with its day and time: on one line, or at the accessibility sizes the label
    /// over the day and the time over each other, where a line can't hold them (the system's
    /// own row then lays out to no size at all).
    private func dateRow(_ title: String, selection: Binding<Date>, from earliest: Date? = nil) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(title).phoneFont(.body, 15, weight: 600)
            if !stacked { Spacer(minLength: 8) }
            picker(title, selection, from: earliest, [.date])
            if !isAllDay { picker(title, selection, from: earliest, [.hourAndMinute]) }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, stacked ? 10 : 0)
        .accessibilityElement(children: .contain)
    }

    private func picker(_ title: String, _ selection: Binding<Date>, from earliest: Date?, _ components: DatePickerComponents) -> some View {
        Group {
            if let earliest {
                DatePicker("", selection: selection, in: earliest..., displayedComponents: components)
            } else {
                DatePicker("", selection: selection, displayedComponents: components)
            }
        }
        .labelsHidden()
        .phoneFont(.body, 15, weight: 600)
        .accessibilityLabel(components == [.date] ? "\(title), day" : "\(title), time")
    }

    private var repeatsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Repeats")
            if repeats == .custom {
                Text("Custom, as set in Calendar")
                    .phoneFont(.body, 15, weight: 600)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                Menu {
                    Button("Never") { repeats = nil }
                    ForEach(EventRepeat.choices) { choice in
                        Button(choice.label) { repeats = choice }
                    }
                } label: {
                    HStack {
                        Text(repeats?.label ?? "Never").phoneFont(.body, 15, weight: 700)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down").phoneFont(.body, 12, weight: 700, relativeTo: .footnote).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("event-repeats")
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
            .tracking(1.1)
            .foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private func textField(_ title: String, text: Binding<String>, field: String, id: String, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            TextField(title, text: Binding(get: { text.wrappedValue }, set: { edited.insert(field); text.wrappedValue = $0 }), axis: axis)
                .phoneFont(.body, 15, weight: 600)
                .lineLimit(axis == .vertical ? 1...6 : 1...1)
                .fieldStyle()
                .accessibilityIdentifier(id)
        }
    }

    // MARK: Loading and saving

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch start {
        case .new:
            let now = store.now()
            let next = store.calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
            begin = next
            end = next.addingTimeInterval(3600)
            if !startingLine.isEmpty { line = startingLine; read(startingLine) }
            lineFocused = startingLine.isEmpty
        case let .edit(event, draft):
            title = draft.title
            begin = draft.start
            end = draft.end
            isAllDay = draft.isAllDay
            repeats = draft.repeats
            location = draft.location
            notes = draft.notes
            people = Set(store.people(for: event))
            edited = ["title", "when", "for"]
        }
    }

    private func saveTapped() {
        if case let .edit(_, draft) = start, draft.repeats != nil {
            askingSpan = true
        } else {
            save(span: .thisEvent)
        }
    }

    private func save(span: EventSpan) {
        guard let calendar else { return }
        var draft = EventDraft(
            calendarId: calendar.id, title: title.trimmingCharacters(in: .whitespaces), start: begin, end: isAllDay ? begin : end,
            isAllDay: isAllDay, location: location, notes: notes, repeats: repeats
        )
        if isAllDay {
            let day = DayKey(begin, calendar: store.calendar)
            draft.start = day.startDate(in: store.calendar)
            draft.end = day.adding(days: 1, calendar: store.calendar).startDate(in: store.calendar)
        }
        if case let .edit(_, old) = start { draft.occurrenceId = old.occurrenceId }
        do {
            try store.save(draft, span: span, for: Array(people))
            dismiss()
            onSaved(isNew ? "\(draft.title) added" : "\(draft.title) saved")
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Choosing the household's home calendar from this device's own, or making one: asked the
/// first time "+" is tapped without one, and from the Calendars page.
struct PocketHomeCalendarSheet: View {
    var onChosen: (ExternalCalendar) -> Void = { _ in }

    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    /// The calendar's swatch grows with the text, as the title beside it does.
    @ScaledMetric(relativeTo: .subheadline) private var swatch: CGFloat = 10

    var body: some View {
        PhoneSheet(label: "Once, for the household", title: "Choose a home calendar") {
            Text("Events added in Porchlight are saved here, a real calendar everyone can see, so they're in Apple Calendar too. Pick one that's shared with your household, or make a new one.")
                .phoneFont(.body, 14, weight: 500)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(store.writableCalendars.enumerated()), id: \.element.id) { index, calendar in
                    if index > 0 { RowDivider() }
                    Button { choose(calendar) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            // On the title's line, not centered on the two lines.
                            RoundedRectangle(cornerRadius: swatch * 0.3)
                                .fill(Color(hex: UInt32(truncatingIfNeeded: calendar.colorHex)))
                                .frame(width: swatch, height: swatch)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - swatch * 0.05 }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(calendar.title).phoneFont(.body, 15, weight: 700, relativeTo: .subheadline)
                                Text(calendar.accountKind).phoneFont(.body, 12, weight: 600, relativeTo: .caption).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if store.home.calendar?.id == calendar.id {
                                Image(systemName: "checkmark").phoneFont(.body, 14, weight: 800).foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-\(calendar.title)")
                }
            }
            .phoneCard()
            if let failure {
                Text(failure).phoneFont(.body, 13, weight: 700, relativeTo: .footnote).foregroundStyle(Theme.accent)
            }
        } footer: {
            Button("New calendar named Home") {
                do {
                    try store.makeHomeCalendar(title: "Home")
                    if let made = store.home.calendar { onChosen(made) }
                    dismiss()
                } catch {
                    failure = (error as? LocalizedError)?.errorDescription
                }
            }
            .buttonStyle(PhoneButtonStyle(kind: .ghost))
            .accessibilityIdentifier("home-new")
        }
    }

    private func choose(_ calendar: ExternalCalendar) {
        if case .ambiguous = store.home { store.markHome(calendar) } else { store.chooseHome(calendar) }
        dismiss()
        onChosen(calendar)
    }
}
