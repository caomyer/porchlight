import SwiftUI

/// A logged meal up close: the big polaroid, its details, and ways to fix or remove it.
/// When the slot holds several meals they sit under the polaroid to switch between,
/// with a way to add another.
struct MealDetailSheet: View {
    let entry: JournalEntry
    /// Opens the capture sheet for another meal in this day's slot.
    var onAddAnother: ((DayKey, String) -> Void)?
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var confirmingDelete = false
    @State private var editing: MealEdit?
    /// The meal shown, when another one of the slot was picked.
    @State private var selectedId: Int64?

    /// The entry as it is now, so saved edits show right away.
    private var current: JournalEntry {
        let id = selectedId ?? entry.id
        return store.snapshot.entries.first { $0.id == id } ?? entry
    }

    /// Every meal logged in the shown meal's slot that day, in time order.
    private var slotMeals: [JournalEntry] {
        store.entries(on: current.dayKey, slot: current.slot)
    }

    var body: some View {
        WallSheet(width: 640, staysAboveKeyboard: true, onClose: onClose) {
            HStack(alignment: .top, spacing: 26) {
                VStack(spacing: 18) {
                    Polaroid(entry: current, rotation: -2, emojiSize: 84, captionSize: 22, plate: 0.5, badgeSize: 26)
                        .environment(\.foodPreferFullPhoto, true)
                        .frame(width: 220)
                        .id(current.id)
                    if editing == nil { slotStrip }
                }
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

    /// The slot's other meals as thumbnails, and a tile to add one more.
    @ViewBuilder
    private var slotStrip: some View {
        let meals = slotMeals
        if meals.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                SheetLabel(title: current.slot, note: "· \(meals.count) dishes")
                FlowLayout(spacing: 8) {
                    ForEach(meals) { meal in
                        Button { select(meal) } label: {
                            MealThumbnail(entry: meal, size: 46)
                                .padding(3)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(meal.id == current.id ? Theme.ink : .clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(meal.title)
                        .accessibilityAddTraits(meal.id == current.id ? .isSelected : [])
                    }
                    if onAddAnother != nil { addTile }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if onAddAnother != nil {
            Button(action: addAnother) {
                Label("Another \(current.slot.lowercased()) dish", systemImage: "plus")
                    .font(.body(14, weight: 700))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var addTile: some View {
        Button(action: addAnother) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 46, height: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Theme.muted.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add another \(current.slot.lowercased()) dish")
    }

    private func select(_ meal: JournalEntry) {
        selectedId = meal.id
        confirmingDelete = false
    }

    private func addAnother() {
        onAddAnother?(current.dayKey, current.slot)
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
                if let place = store.place(of: entry) {
                    placeDetail(place)
                }
                if let rating = entry.rating {
                    detail(rating.emoji, rating.phrase.prefix(1).uppercased() + rating.phrase.dropFirst())
                }
                HStack(spacing: 10) {
                    EaterBadge(people: store.eaters(of: entry), everyone: store.ateTogether(entry), size: 26)
                    Text(whoText).font(.body(16, weight: 600))
                }
            }
            .padding(.top, 18)
            HStack {
                if !confirmingDelete {
                    Button {
                        store.lastError = nil
                        editing = MealEdit(entry: entry, eaterIds: store.eaters(of: entry).compactMap(\.id), place: store.place(of: entry))
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                if confirmingDelete {
                    Button("Keep it") { confirmingDelete = false }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Remove meal") { remove(entry) }
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

    /// Removes the meal; the sheet stays open on the slot's next meal if there is one.
    private func remove(_ entry: JournalEntry) {
        let rest = slotMeals.filter { $0.id != entry.id }
        store.deleteMeal(entry)
        confirmingDelete = false
        if let next = rest.first {
            selectedId = next.id
        } else {
            onClose()
        }
    }

    private func placeDetail(_ place: FoodPlace) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("📍").font(.system(size: 18)).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body(16, weight: 600))
                let more = [place.category, place.address].compactMap { $0 }.joined(separator: " · ")
                if !more.isEmpty {
                    Text(more)
                        .font(.body(13.5, weight: 600))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
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
    var place: PlaceDraft?

    init(entry: JournalEntry, eaterIds: [Int64], place: FoodPlace? = nil) {
        title = entry.title
        slot = entry.slot
        source = entry.source
        rating = entry.rating
        self.eaterIds = Set(eaterIds)
        time = .at(entry.eatenAt)
        self.place = place.map(PlaceDraft.init)
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
            eatenAt: eatenAt,
            place: source.hasPlace ? place : nil
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

            label("From")
            FlowLayout(spacing: 8) {
                ForEach(MealSource.allCases, id: \.self) { source in
                    FoodChoicePill("\(source.emoji) \(source.label)", isSelected: edit.source == source) { edit.source = source }
                }
            }
            if edit.source.hasPlace {
                RestaurantField(place: $edit.place, prompt: edit.source == .dineOut ? "Where? Search restaurants" : "From where? Search restaurants")
                    .padding(.top, 10)
                    .zIndex(1)
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
