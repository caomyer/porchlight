import SwiftUI

/// A logged meal up close: the big polaroid, its details, and ways to fix or remove it.
struct MealDetailSheet: View {
    let entry: JournalEntry
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var confirmingDelete = false
    @State private var editing: MealEdit?

    /// The entry as it is now, so saved edits show right away.
    private var current: JournalEntry {
        store.snapshot.entries.first { $0.id == entry.id } ?? entry
    }

    var body: some View {
        WallSheet(width: 640, staysAboveKeyboard: true, onClose: onClose) {
            HStack(alignment: .top, spacing: 26) {
                Polaroid(entry: current, rotation: -2, emojiSize: 84, captionSize: 22, plate: 0.5, badgeSize: 26)
                    .environment(\.foodPreferFullPhoto, true)
                    .frame(width: 220)
                    .padding(.top, 8)
                if let editing {
                    MealEditForm(
                        entry: current,
                        edit: Binding(get: { editing }, set: { self.editing = $0 }),
                        error: store.lastError,
                        onCancel: { self.editing = nil },
                        onSave: save
                    )
                } else {
                    details
                }
            }
        }
    }

    private var details: some View {
        let entry = current
        return VStack(alignment: .leading, spacing: 0) {
            Text(entry.title)
                .font(.display(30))
                .lineLimit(2)
                .padding(.trailing, 40)
            Text(dateLine)
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 10) {
                detail(entry.source.emoji, entry.source.label)
                if let rating = entry.rating {
                    detail(rating.emoji, rating.phrase.prefix(1).uppercased() + rating.phrase.dropFirst())
                }
                HStack(spacing: 10) {
                    EaterBadge(people: store.eaters(of: entry), everyone: store.ateTogether(entry), size: 26)
                    Text(whoText).font(.body(16, weight: 600))
                }
                if let line = entry.noteLine {
                    detail("✍️", "Note on line \(line + 1) of the day's page")
                }
            }
            .padding(.top, 18)
            HStack {
                if !confirmingDelete {
                    Button {
                        store.lastError = nil
                        editing = MealEdit(entry: entry, eaterIds: store.eaters(of: entry).compactMap(\.id))
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                if confirmingDelete {
                    Button("Keep it") { confirmingDelete = false }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Remove meal") {
                        store.deleteMeal(entry)
                        onClose()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button {
                        confirmingDelete = true
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.top, 28)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func save() {
        guard let editing else { return }
        if store.updateMeal(current, editing.draft(for: current, calendar: store.calendar)) {
            self.editing = nil
        }
    }

    private var dateLine: String {
        let entry = current
        let date = entry.dayKey.startDate(in: store.calendar)
        return "\(entry.slot) · " + date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var whoText: String {
        if store.ateTogether(current) { return "Everyone ate" }
        return ListFormat.join(store.eaters(of: current).map(\.name)) + " ate"
    }

    private func detail(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 18)).frame(width: 26)
            Text(text).font(.body(16, weight: 600))
        }
    }
}

/// The editable details of a logged meal.
struct MealEdit: Equatable {
    var title: String
    var slot: String
    var source: MealSource
    var rating: MealRating?
    var eaterIds: Set<Int64>
    var time: LogTime

    init(entry: JournalEntry, eaterIds: [Int64]) {
        title = entry.title
        slot = entry.slot
        source = entry.source
        rating = entry.rating
        self.eaterIds = Set(eaterIds)
        time = .at(entry.eatenAt)
    }

    /// The meal's day, up to now if that's today.
    static func timeRange(for entry: JournalEntry, calendar: Calendar, now: Date = .now) -> ClosedRange<Date> {
        let start = entry.dayKey.startDate(in: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-60) ?? start
        return start...max(start, min(end, now))
    }

    /// The chosen time. Moving a meal to another slot without picking a time moves it
    /// to that slot's usual hour, so the day's timeline keeps meals in order.
    func draft(for entry: JournalEntry, calendar: Calendar) -> MealDraft {
        let range = Self.timeRange(for: entry, calendar: calendar)
        var eatenAt = min(max(time.start(now: .now), range.lowerBound), range.upperBound)
        if slot != entry.slot, time == .at(entry.eatenAt) {
            eatenAt = MealSlot.usualTime(of: slot, on: entry.dayKey, calendar: calendar)
        }
        return MealDraft(
            day: entry.dayKey,
            slot: slot,
            source: source,
            title: title,
            rating: rating,
            eaterIds: Array(eaterIds),
            noteLine: entry.noteLine,
            eatenAt: eatenAt
        )
    }
}

/// Fixes a meal's name, slot, maker, eaters or rating, laid out like the capture form.
private struct MealEditForm: View {
    let entry: JournalEntry
    @Binding var edit: MealEdit
    let error: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    @Environment(FoodStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit meal")
                .font(.display(30))
                .padding(.trailing, 40)

            HStack(spacing: 10) {
                Text(DishIllustration.suggestEmoji(for: edit.title) ?? DishIllustration.fallbackEmoji)
                    .font(.system(size: 22))
                TextField("What was it?", text: $edit.title)
                    .font(.body(17, weight: 600))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
            }
            .fieldStyle()
            .padding(.top, 12)

            label("Meal")
            HStack(alignment: .center, spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(slots, id: \.self) { slot in
                        FoodChoicePill("\(MealSlot.named(slot).emoji) \(slot)", isSelected: edit.slot == slot) { edit.slot = slot }
                    }
                }
                Spacer(minLength: 4)
                AtTimeField(time: $edit.time, range: timeRange, calendar: store.calendar)
            }

            label("Made by")
            FlowLayout(spacing: 8) {
                ForEach(MealSource.allCases, id: \.self) { source in
                    FoodChoicePill("\(source.emoji) \(source.label)", isSelected: edit.source == source) { edit.source = source }
                }
            }

            label("Who ate")
            FlowLayout(spacing: 10) {
                ForEach(store.people) { person in
                    WhoButton(person: person, isSelected: edit.eaterIds.contains(person.id ?? -1)) {
                        guard let id = person.id else { return }
                        if edit.eaterIds.contains(id) {
                            if edit.eaterIds.count > 1 { edit.eaterIds.remove(id) }
                        } else {
                            edit.eaterIds.insert(id)
                        }
                    }
                }
            }

            label("Would eat again?")
            HStack(spacing: 8) {
                ForEach(MealRating.allCases, id: \.self) { rating in
                    FoodChoicePill(rating.emoji, isSelected: edit.rating == rating) { edit.rating = rating }
                        .accessibilityLabel(rating.phrase)
                }
            }

            HStack(spacing: 10) {
                if let error {
                    Text(error)
                        .font(.body(13.5, weight: 600))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("Cancel", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                Button("Save", action: onSave)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var timeRange: ClosedRange<Date> {
        MealEdit.timeRange(for: entry, calendar: store.calendar)
    }

    /// This diary's meals, plus the entry's own slot if it was since turned off.
    private var slots: [String] {
        store.slots.contains(edit.slot) ? store.slots : store.slots + [edit.slot]
    }

    private func label(_ title: String) -> some View {
        SheetLabel(title: title, note: nil)
            .padding(.top, 12)
            .padding(.bottom, 7)
    }
}

private struct PreferFullPhotoKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Big polaroids load the full photo instead of the thumbnail.
    var foodPreferFullPhoto: Bool {
        get { self[PreferFullPhotoKey.self] }
        set { self[PreferFullPhotoKey.self] = newValue }
    }
}
