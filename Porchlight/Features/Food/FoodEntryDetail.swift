import SwiftUI

/// A logged meal up close: the big polaroid (swipe it to page through the photos), its
/// photos with a way to add more, its details, and ways to fix or remove it. When the
/// slot holds several meals they sit below to switch between, with a way to add another.
struct MealDetailSheet: View {
    let entry: JournalEntry
    /// Opens the capture sheet for another meal in this day's slot.
    var onAddAnother: ((DayKey, String) -> Void)?
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var confirmingDelete = false
    @State private var editing: MealEdit?
    /// The meal shown, when another one of the slot was picked.
    @State private var selectedId: JournalEntry.ID?
    /// The photo on the polaroid; 0 is the cover.
    @State private var photoIndex = 0
    @State private var drag: CGFloat = 0
    /// The photo shown whole, uncropped, over the sheet.
    @State private var wholePhoto: MealPhoto?

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
                // Edit shows the photos in its own row, so the form takes the full width.
                if editing == nil {
                    VStack(spacing: 18) {
                        pager
                        photoStrip
                        slotStrip
                    }
                    .frame(width: 220)
                    .padding(.top, 8)
                }
                if let editing {
                    MealEditForm(
                        entry: current,
                        // Read the live edit, not this render's copy: a change made of two
                        // steps (moving a photo to the front) must see the first step.
                        edit: Binding(get: { self.editing ?? editing }, set: { self.editing = $0 }),
                        error: store.lastError,
                        onCancel: cancelEdit,
                        onSave: save
                    )
                } else {
                    details
                }
            }
        }
        .wallCover(item: $wholePhoto) { photo in
            WholePhotoView(photo: photo) { CompanionCover.instantly { wholePhoto = nil } }
        }
    }

    private var photos: [MealPhoto] { store.photos(of: current) }

    /// The big polaroid. With several photos, swipe it sideways or tap a thumbnail below.
    private var pager: some View {
        let count = photos.count
        let index = min(photoIndex, max(count - 1, 0))
        return Polaroid(entry: current, rotation: -2, emojiSize: 84, captionSize: 22, plate: 0.5, badgeSize: 26, photoIndex: index, showsPhotoCount: false)
            .environment(\.foodPreferFullPhoto, true)
            .frame(width: 220)
            .overlay(alignment: .bottom) {
                if count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<count, id: \.self) { dot in
                            Circle()
                                .fill(Color.white.opacity(dot == index ? 1 : 0.55))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.28), in: Capsule())
                    .padding(.bottom, 52)
                    .rotationEffect(.degrees(-2))
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if count > 0 {
                    Label("Whole photo", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.body(11, weight: 800))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(.leading, 14)
                        .padding(.bottom, 46)
                        .rotationEffect(.degrees(-2))
                        .allowsHitTesting(false)
                }
            }
            .offset(x: drag * 0.4)
            .id(current.id)
            .contentShape(Rectangle())
            .onTapGesture { showWhole(index) }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { if count > 1 { drag = $0.translation.width } }
                    .onEnded { value in
                        guard count > 1 else { return }
                        let travel = value.predictedEndTranslation.width
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if abs(value.translation.width) > 40 || abs(travel) > 120 {
                                photoIndex = (index + (travel < 0 ? 1 : -1) + count) % count
                            }
                            drag = 0
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count > 1 ? "\(current.title), photo \(index + 1) of \(count)" : current.title)
            .accessibilityIdentifier("meal-pager")
            .accessibilityAddTraits(count > 0 ? .isButton : [])
            .accessibilityHint(count > 0 ? "Shows the whole photo" : "")
            .accessibilityAction { showWhole(index) }
            .accessibilityAdjustableAction { change in
                guard count > 1 else { return }
                switch change {
                case .increment: photoIndex = (index + 1) % count
                case .decrement: photoIndex = (index - 1 + count) % count
                @unknown default: break
                }
            }
    }

    private func showWhole(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        CompanionCover.instantly { wholePhoto = photos[index] }
    }

    /// The meal's photos as thumbnails to jump to, and a tile to add more right away.
    private var photoStrip: some View {
        let photos = photos
        return VStack(alignment: .leading, spacing: 8) {
            SheetLabel(title: "Photos", note: photos.isEmpty ? nil : "· \(photos.count)")
            FlowLayout(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { photoIndex = index } } label: {
                        Color.clear
                            .frame(width: 46, height: 46)
                            .overlay {
                                if let image = MealImages.image(at: store.photoURL(photo.thumbnailFile)) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .padding(3)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(index == min(photoIndex, photos.count - 1) ? Theme.ink : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(index + 1)")
                }
                AddPhotoTile(remaining: AppDatabase.photoLimit - photos.count, size: 46) { images in
                    Task {
                        let before = photos.count
                        if await store.addPhotos(images, to: current) {
                            withAnimation(.easeInOut(duration: 0.2)) { photoIndex = before }
                        }
                    }
                }
                .padding(3)
            }
            if let error = store.lastError, editing == nil {
                Text(error).font(.body(12.5, weight: 600)).foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        photoIndex = 0
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
                        editing = MealEdit(entry: entry, eaterIds: store.eaters(of: entry).map(\.id), place: store.place(of: entry), photos: store.photos(of: entry))
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
            photoIndex = 0
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
        guard let editing, editing.savingPhotos == 0 else { return }
        if store.updateMeal(current, editing.draft(for: current, calendar: store.calendar), photos: editing.photos) {
            self.editing = nil
            photoIndex = 0
        }
    }

    /// Leaves the edit. Photos added during it were never attached, and thumbnails made
    /// by reframing a saved photo were never saved, so their files go.
    private func cancelEdit() {
        if let editing {
            let saved = Set(store.photos(of: current).map(\.thumbnailFile))
            let reframed = editing.photos.compactMap { item -> String? in
                guard case let .kept(photo) = item, !saved.contains(photo.thumbnailFile) else { return nil }
                return photo.thumbnailFile
            }
            store.discard(files: MealPhotoItem.unusedFiles(from: editing.photos, to: []) + reframed)
        }
        editing = nil
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

/// A meal photo whole, uncropped, over everything: the full shot the polaroid's square
/// comes from. Tap anywhere to close.
struct WholePhotoView: View {
    let photo: MealPhoto
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var isShown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            if let image = MealImages.image(at: store.photoURL(photo.photoFile)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(48)
                    .accessibilityLabel("Whole photo")
                    .accessibilityIdentifier("whole-photo")
            }
            VStack {
                Spacer()
                Text("Tap anywhere to close")
                    .font(.body(13, weight: 700))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 16)
            }
        }
        .opacity(isShown ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .accessibilityAction(.escape, close)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { isShown = true } }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.15)) { isShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onClose() }
    }
}

/// The editable details of a logged meal.
struct MealEdit: Equatable {
    var title: String
    var slot: String
    var source: MealSource
    var rating: MealRating?
    var eaterIds: Set<Person.ID>
    var time: LogTime
    var place: PlaceDraft?
    /// The meal's photos as they will be saved, cover first.
    var photos: [MealPhotoItem]
    /// New photos still being written to disk.
    var savingPhotos = 0

    init(entry: JournalEntry, eaterIds: [Person.ID], place: FoodPlace? = nil, photos: [MealPhoto] = []) {
        title = entry.title
        slot = entry.slot
        source = entry.source
        rating = entry.rating
        self.eaterIds = Set(eaterIds)
        time = .at(entry.eatenAt)
        self.place = place.map(PlaceDraft.init)
        self.photos = photos.map(MealPhotoItem.kept)
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

            label("Photos")
            MealPhotoRow(items: $edit.photos, pending: edit.savingPhotos, size: 52, emptyText: "No photos yet. Add one from the camera or Photos.") {
                AddPhotoTile(remaining: AppDatabase.photoLimit - edit.photos.count - edit.savingPhotos, size: 52, onAdd: add)
            }
            .onChange(of: edit.photos) { old, new in
                // A new photo removed again was never attached; its files go now.
                store.discard(files: MealPhotoItem.unusedFiles(from: old, to: new))
            }

            // The time rides on the label line, so the meals get the row's full width.
            LogTimeField(
                time: $edit.time,
                range: timeRange,
                suggestions: MealSlot.timeSuggestions(slot: edit.slot, day: entry.dayKey, calendar: store.calendar),
                accessibilityLabel: "Time eaten",
                identifier: "time-eaten",
                calendar: store.calendar
            ) {
                SheetLabel(title: "Meal", note: nil)
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
            FlowLayout(spacing: 8) {
                ForEach(slots, id: \.self) { slot in
                    FoodChoicePill("\(MealSlot.named(slot).emoji) \(slot)", isSelected: edit.slot == slot) { edit.slot = slot }
                }
            }

            label("From")
            FlowLayout(spacing: 8) {
                ForEach(MealSource.allCases, id: \.self) { source in
                    FoodChoicePill("\(source.emoji) \(source.label)", isSelected: edit.source == source, compact: true) { edit.source = source }
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
                    WhoButton(person: person, isSelected: edit.eaterIds.contains(person.id)) {
                        let id = person.id
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
                    .disabled(edit.savingPhotos > 0)
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Saves new images to disk and adds them to the edit; they attach on Save.
    private func add(_ images: [UIImage]) {
        let room = AppDatabase.photoLimit - edit.photos.count - edit.savingPhotos
        for image in images.prefix(max(room, 0)) {
            edit.savingPhotos += 1
            Task {
                defer { edit.savingPhotos -= 1 }
                if let stored = try? await store.savePhoto(image) {
                    edit.photos.append(.added(stored))
                }
            }
        }
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
