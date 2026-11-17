import PhotosUI
import SwiftUI

/// One meal on the phone (`b5entry`): its photos as a big polaroid to swipe through (the
/// thumbnail shows until the whole shot has loaded or arrived), where it came from, the
/// verdict and who ate it and added it, the day's handwritten page when it has one, and
/// Edit, Add photo and Remove through the same `FoodStore` paths as the wall.
struct PocketMealDetail: View {
    let entryId: JournalEntry.ID
    /// Opens the camera for another photo of this meal.
    let onTakePhoto: (JournalEntry) -> Void

    @Environment(AppModel.self) private var model
    @Environment(FoodStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss
    @State private var photoIndex = 0
    @State private var wholePhoto: MealPhoto?
    @State private var editing = false
    @State private var confirmingRemove = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsPicker = false

    var body: some View {
        Group {
            if let entry = store.snapshot.entries.first(where: { $0.id == entryId }) {
                content(entry)
            } else {
                // Removed, here or on another device.
                Text("This meal was removed.")
                    .phoneFont(.body, 15, weight: 600)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
    }

    private func content(_ entry: JournalEntry) -> some View {
        let photos = store.photos(of: entry)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pager(entry, photos: photos)
                facts(entry)
                dayPage(entry)
                otherDishes(entry)
                actions(entry, photos: photos)
                if let error = store.lastError {
                    Text(error)
                        .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fullScreenCover(item: $wholePhoto) { photo in
            WholePhotoView(photo: photo) { wholePhoto = nil }
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $editing) {
            PocketMealEditor(entry: entry)
        }
        .confirmationDialog("Remove \(entry.title)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove meal", role: .destructive) {
                store.deleteMeal(entry)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(photos.isEmpty ? "It goes from the diary on every device." : "It goes from the diary on every device, with its photos.")
        }
        .photosPicker(isPresented: $showsPicker, selection: $pickerItems, maxSelectionCount: max(AppDatabase.photoLimit - photos.count, 1), selectionBehavior: .ordered, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let images = await PhotoPicking.load(items)
                pickerItems = []
                let before = store.photos(of: entry).count
                if await store.addPhotos(images, to: entry) { photoIndex = before }
            }
        }
        .onAppear { store.lastError = nil }
    }

    // MARK: Photos

    /// The big polaroid; with several photos, swipe it sideways. Tap for the whole photo.
    private func pager(_ entry: JournalEntry, photos: [MealPhoto]) -> some View {
        let count = photos.count
        let index = min(photoIndex, max(count - 1, 0))
        return Polaroid(entry: entry, rotation: -1, emojiSize: 96, captionSize: 26, plate: 0.5, badgeSize: 30, photoIndex: index, showsPhotoCount: false)
            .environment(\.foodPreferFullPhoto, true)
            .frame(maxWidth: 320)
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
                    .padding(.bottom, 58)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .contentShape(Rectangle())
            .onTapGesture { if photos.indices.contains(index) { wholePhoto = photos[index] } }
            .gesture(
                DragGesture(minimumDistance: 16)
                    .onEnded { value in
                        guard count > 1, abs(value.translation.width) > abs(value.translation.height) else { return }
                        let travel = value.predictedEndTranslation.width
                        if abs(value.translation.width) > 40 || abs(travel) > 120 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                photoIndex = (index + (travel < 0 ? 1 : -1) + count) % count
                            }
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count > 1 ? "\(entry.title), photo \(index + 1) of \(count)" : entry.title)
            .accessibilityIdentifier("meal-pager")
            .accessibilityAddTraits(count > 0 ? .isButton : [])
            .accessibilityHint(count > 0 ? "Shows the whole photo" : "")
            .accessibilityAction { if photos.indices.contains(index) { wholePhoto = photos[index] } }
            .accessibilityAdjustableAction { change in
                guard count > 1 else { return }
                switch change {
                case .increment: photoIndex = (index + 1) % count
                case .decrement: photoIndex = (index - 1 + count) % count
                @unknown default: break
                }
            }
    }

    // MARK: Details

    private func facts(_ entry: JournalEntry) -> some View {
        let calendar = store.calendar
        let place = store.place(of: entry)
        let who = PocketFood.eaters(store.eaters(of: entry), everyone: store.ateTogether(entry), householdSize: store.people.count, me: me?.id)
        let added = PocketFood.addedBy(entry.deviceId, devices: model.devices, everyone: model.everyone, me: me?.id)
        return VStack(alignment: .leading, spacing: 2) {
            row(place == nil ? entry.source.emoji : "📍",
                place?.name ?? entry.source.label,
                ([place == nil ? nil : entry.source.label, PocketFood.whenLine(slot: entry.slot, eatenAt: entry.eatenAt, calendar: calendar)].compactMap { $0 }).joined(separator: " · "))
            if let address = place?.address {
                row("🗺️", address, place?.category)
            }
            RowDivider()
            row(entry.rating?.emoji ?? "🍽️",
                entry.rating.map { $0.phrase.prefix(1).uppercased() + $0.phrase.dropFirst() } ?? "No verdict",
                [who, added].compactMap { $0 }.joined(separator: " · "))
        }
        .phoneCard()
    }

    private func row(_ emoji: String, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(emoji)
                .phoneFont(.body, 20)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).phoneFont(.body, 15, weight: 700, relativeTo: .subheadline)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .phoneFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// The day's shared handwritten page, as the wall shows it, when anyone wrote on it.
    @ViewBuilder
    private func dayPage(_ entry: JournalEntry) -> some View {
        if store.snapshot.pages[entry.day] != nil {
            let weekday = entry.dayKey.startDate(in: store.calendar).formatted(Date.FormatStyle(timeZone: store.calendar.timeZone).weekday(.wide))
            VStack(alignment: .leading, spacing: 10) {
                PhoneCardHeader(title: "\(weekday)'s page", meta: "written on the wall")
                DayPageView(day: entry.dayKey, scale: 1.4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.line))
                    .shadow(color: FoodStyle.shadow.opacity(0.18), radius: 5, y: 4)
                    .rotationEffect(.degrees(-1))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityLabel("\(weekday)'s handwritten page")
            }
            .phoneCard()
        }
    }

    /// The slot's other dishes, to switch to.
    @ViewBuilder
    private func otherDishes(_ entry: JournalEntry) -> some View {
        let meals = store.entries(on: entry.dayKey, slot: entry.slot)
        if meals.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                PhoneCardHeader(title: PocketFood.mealName(day: entry.dayKey, slot: entry.slot, calendar: store.calendar), meta: "\(meals.count) dishes")
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(meals) { meal in
                        NavigationLink(value: PocketFoodRoute.meal(meal.id)) {
                            MealThumbnail(entry: meal, size: 52)
                                .padding(3)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(meal.id == entry.id ? Theme.ink : .clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(meal.id == entry.id)
                        .accessibilityLabel(meal.title)
                        .accessibilityAddTraits(meal.id == entry.id ? .isSelected : [])
                    }
                }
            }
            .phoneCard()
        }
    }

    // MARK: Actions

    private func actions(_ entry: JournalEntry, photos: [MealPhoto]) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 4) {
            PhoneChoice(title: "✏️ Edit", isOn: false) {
                store.lastError = nil
                editing = true
            }
            .accessibilityIdentifier("edit-meal")
            if photos.count < AppDatabase.photoLimit {
                Menu {
                    Button { onTakePhoto(entry) } label: { Label("Take a photo", systemImage: "camera") }
                    Button { showsPicker = true } label: { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                } label: {
                    PhoneChoice(title: "➕ Add photo", isOn: false) {}
                        .allowsHitTesting(false)
                }
                .accessibilityLabel("Add photo")
                .accessibilityIdentifier("add-photo")
            }
            PhoneChoice(title: "🗑️ Remove", isOn: false) { confirmingRemove = true }
                .accessibilityIdentifier("remove-meal")
        }
    }
}

/// Fixing a meal from the phone: the same fields as snapping one, and its photos to take
/// off or make the cover, saved through `FoodStore.updateMeal`.
private struct PocketMealEditor: View {
    let entry: JournalEntry

    @Environment(FoodStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var edit: MealEdit?

    var body: some View {
        PhoneSheet(label: PocketFood.mealName(day: entry.dayKey, slot: entry.slot, calendar: store.calendar), title: "Edit meal") {
            if let binding = Binding($edit) {
                let now = CompanionClock.now()
                photos(binding)
                PocketMealFields(
                    title: binding.title, slot: binding.slot, time: binding.time, source: binding.source,
                    place: binding.place, eaterIds: binding.eaterIds, rating: binding.rating,
                    day: entry.dayKey, range: MealEdit.timeRange(for: entry, calendar: store.calendar, now: now), now: now,
                    slots: store.slots.contains(binding.wrappedValue.slot) ? store.slots : store.slots + [binding.wrappedValue.slot]
                )
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let error = store.lastError {
                    Text(error)
                        .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                        .foregroundStyle(Theme.accent)
                }
                Button("Save") { save() }
                    .buttonStyle(PhoneButtonStyle())
                    .accessibilityIdentifier("save-edit")
            }
        }
        .onAppear {
            guard edit == nil else { return }
            edit = MealEdit(entry: entry, eaterIds: store.eaters(of: entry).map(\.id), place: store.place(of: entry), photos: store.photos(of: entry))
        }
    }

    /// The meal's photos, cover first: × takes one off, a long press makes one the cover.
    @ViewBuilder
    private func photos(_ edit: Binding<MealEdit>) -> some View {
        let items = edit.wrappedValue.photos
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Photos").phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
                FlowLayout(spacing: 12, lineSpacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PhotoView(store.thumbnail(of: item).map { PhotoRequest($0) }) { _ in Theme.surface2 }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(index == 0 ? Theme.accent : .clear, lineWidth: 3)
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { edit.wrappedValue.photos.remove(at: index) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(Theme.surface)
                                        .frame(width: 22, height: 22)
                                        .background(Theme.ink, in: Circle())
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 16, y: -16)
                                .accessibilityLabel("Take off photo \(index + 1)")
                            }
                            .contextMenu {
                                if index > 0 {
                                    Button { edit.wrappedValue.photos.insert(edit.wrappedValue.photos.remove(at: index), at: 0) } label: {
                                        Label("Make cover", systemImage: "star")
                                    }
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(index == 0 ? "Photo \(index + 1), the cover" : "Photo \(index + 1)")
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func save() {
        guard let edit else { return }
        if store.updateMeal(entry, edit.draft(for: entry, calendar: store.calendar), photos: edit.photos) {
            dismiss()
        }
    }
}
