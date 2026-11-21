import SwiftUI

/// "Snap a meal" on the phone: the camera first, then the meal's details under the new
/// polaroid, then back to the diary with a toast. The meal is guessed from the time, who
/// ate it starts as me, and it is saved through `FoodStore.addMeal`, which stamps this
/// device, with photos made by `MealPhotoImaging.prepare` like the wall's.
struct PocketSnap: View {
    let request: CaptureRequest
    /// The saved meal, who ate it and where it came from, for the diary's toast.
    let onSaved: (JournalEntry, _ eaterIds: Set<Person.ID>, _ place: PlaceDraft?) -> Void

    @Environment(FoodStore.self) private var store
    @Environment(\.me) private var me
    @Environment(\.dismiss) private var dismiss
    @State private var form: CaptureForm?
    @State private var showsDetails = false
    /// The details were shown once, so the camera's close goes back to them.
    @State private var sawDetails = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmingDiscard = false

    var body: some View {
        Group {
            if let form {
                if showsDetails {
                    PocketSnapDetails(
                        form: form, isSaving: isSaving, error: error,
                        onAddPhoto: { show(details: false) },
                        onClose: requestClose
                    ) { save(form) }
                } else {
                    PocketCameraStep(
                        small: smallLine(form),
                        title: "Snap a meal",
                        caption: PocketFood.mealName(day: form.day, slot: form.slot, calendar: store.calendar),
                        remaining: form.photoRoom,
                        closeLabel: sawDetails ? "Back" : "Close",
                        onImages: { add($0, to: form) },
                        onNoPhoto: sawDetails ? nil : { show(details: true) },
                        onClose: { sawDetails ? show(details: true) : requestClose() }
                    )
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear(perform: setUp)
        .confirmationDialog(discardTitle, isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("This meal isn't saved yet, so its photos would go too.")
        }
    }

    private func setUp() {
        guard form == nil else { return }
        let form = CaptureForm(request: request, store: store, now: CompanionClock.now())
        // A personal phone credits its person (rule 1); others who ate are a tap away.
        if let me, store.people.contains(where: { $0.id == me.id }) { form.eaterIds = [me.id] }
        self.form = form
        #if DEBUG
        if UserDefaults.standard.string(forKey: "debugFoodView") == "details" { show(details: true) }
        #endif
    }

    /// "Dinner · guessed from the time", or the day it is for.
    private func smallLine(_ form: CaptureForm) -> String {
        if form.day != store.today(CompanionClock.now()) {
            return "\(form.slot) · " + form.day.startDate(in: store.calendar).formatted(Date.FormatStyle(timeZone: store.calendar.timeZone).weekday(.wide).month(.abbreviated).day())
        }
        return form.slotWasGuessed ? "\(form.slot) · guessed from the time" : form.slot
    }

    private func show(details: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            showsDetails = details
            if details { sawDetails = true }
        }
    }

    /// Makes each image into a photo off the main actor, then shows the details. Nothing
    /// is attached to a meal until Save.
    private func add(_ images: [UIImage], to form: CaptureForm) {
        let images = Array(images.prefix(form.photoRoom))
        guard !images.isEmpty else { return }
        form.savingPhotos += images.count
        show(details: true)
        for image in images {
            Task {
                defer { form.savingPhotos -= 1 }
                do {
                    let photo = try await store.preparePhoto(image)
                    if form.photos.count < AppDatabase.photoLimit {
                        withAnimation(.easeOut(duration: 0.2)) { form.photos.append(.added(photo)) }
                    }
                } catch {
                    self.error = error.userMessage
                }
            }
        }
    }

    private func save(_ form: CaptureForm) {
        guard !isSaving, form.savingPhotos == 0 else { return }
        isSaving = true
        defer { isSaving = false }
        let now = CompanionClock.now()
        do {
            let entry = try store.addMeal(form.draft(now: now, calendar: store.calendar, today: store.today(now)), photos: form.newPhotos)
            error = nil
            onSaved(entry, form.eaterIds, form.sources.hasPlace ? form.place : nil)
            dismiss()
        } catch {
            self.error = error.userMessage
        }
    }

    private var discardTitle: String {
        let count = form?.newPhotos.count ?? 0
        return count == 1 ? "Discard 1 photo?" : "Discard \(count) photos?"
    }

    /// Closes right away unless that would lose photos that were never saved.
    private func requestClose() {
        if let form, !form.newPhotos.isEmpty {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }
}

/// The meal's details under its new polaroid (`b5details`): what it was, which meal and
/// when, where it came from, who ate and the verdict, then "Save to Sunday dinner".
private struct PocketSnapDetails: View {
    @Bindable var form: CaptureForm
    let isSaving: Bool
    let error: String?
    let onAddPhoto: () -> Void
    let onClose: () -> Void
    let onSave: () -> Void

    @Environment(FoodStore.self) private var store

    var body: some View {
        let now = CompanionClock.now()
        let mealName = PocketFood.mealName(day: form.day, slot: form.slot, calendar: store.calendar)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                            .background(Theme.surface2, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("close-snap")
                    Spacer()
                }
                cover(mealName: mealName)
                VStack(alignment: .leading, spacing: 14) {
                    Text(PocketFood.whenLine(slot: form.slot, eatenAt: form.draft(now: now, calendar: store.calendar, today: store.today(now)).eatenAt, calendar: store.calendar).uppercased())
                        .phoneFont(.body, 11, weight: 800, relativeTo: .caption)
                        .tracking(1.1)
                        .foregroundStyle(Theme.muted)
                    PocketMealFields(
                        dishes: $form.dishes,
                        slot: $form.slot,
                        time: $form.time,
                        sources: $form.sources,
                        sourcesGuessed: $form.sourcesGuessed,
                        place: $form.place,
                        eaterIds: $form.eaterIds,
                        rating: Binding(get: { form.rating }, set: { form.rating = $0 ?? .again }),
                        day: form.day,
                        range: form.timeRange(now: now),
                        now: now,
                        slots: store.slots
                    )
                    if let error {
                        Text(error)
                            .phoneFont(.body, 13, weight: 600, relativeTo: .footnote)
                            .foregroundStyle(Theme.accent)
                    }
                    Button(action: onSave) {
                        if isSaving { ProgressView().tint(Theme.accentInk) } else { Text("Save to \(mealName)") }
                    }
                    .buttonStyle(PhoneButtonStyle())
                    .disabled(isSaving || form.savingPhotos > 0)
                    .accessibilityIdentifier("save-meal")
                }
                .padding(18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        // As across the app, a drag down into the keyboard takes it away; scrolling the form
        // while typing keeps it, and Done on the dish field puts it away.
        .scrollDismissesKeyboard(.interactively)
        .keepsDishFieldInView(proxy)
        }
        // A full-screen cover stands outside the tabs: keep scrolled text out from
        // under the clock, as the welcome screens do.
        .clipped()
        .background(Theme.background)
        .paperUnderStatusBar()
    }

    /// The new polaroid, and how many photos it has with a way to take another.
    private func cover(mealName: String) -> some View {
        let title = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    if let first = form.photos.first, let thumbnail = store.thumbnail(of: first) {
                        PhotoView(PhotoRequest(thumbnail)) { _ in Theme.surface2 }
                    } else if form.savingPhotos > 0 {
                        Theme.surface2.overlay { ProgressView() }
                    } else {
                        PlateArt(emoji: form.emoji, tint: Color(hex: UInt32(DishIllustration.suggestTint(for: title))), plate: 0.5, emojiSize: 60)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                Text(title.isEmpty ? mealName : title)
                    .phoneFont(.hand, 20, weight: 700, relativeTo: .title3)
                    .foregroundStyle(FoodStyle.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .padding([.top, .horizontal], 8)
            .padding(.bottom, 2)
            .background(FoodStyle.polaroidPaper, in: RoundedRectangle(cornerRadius: 3))
            .shadow(color: FoodStyle.shadow.opacity(0.22), radius: 8, y: 6)
            .rotationEffect(.degrees(-1.5))
            .frame(maxWidth: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(form.photos.isEmpty ? "No photo yet" : "The new photo")
            photoRow
        }
        .frame(maxWidth: .infinity)
    }

    /// The new meal's photos in the wall's photo row: tap one to make it the cover or
    /// reframe it, × to take it off, + for the camera again.
    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MealPhotoOrder.heading(count: form.photos.count))
                .phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
            MealPhotoRow(
                items: Binding(get: { form.photos }, set: { form.photos = $0 }),
                pending: form.savingPhotos, size: 56,
                emptyText: "No photo yet. Add one from the camera or Photos."
            ) {
                if form.photoRoom > 0 {
                    Button(action: onAddPhoto) { AddPhotoTileLabel(size: 56) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(form.photos.isEmpty ? "Add a photo" : "Another photo")
                        .accessibilityIdentifier("another-photo")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// A meal's details as the phone edits them, for a new meal and for fixing one: the same
/// fields as the wall's capture form, laid out for a compact width.
struct PocketMealFields: View {
    @Binding var dishes: DishLinesEdit
    @Binding var slot: String
    @Binding var time: LogTime
    @Binding var sources: MealSources
    /// The kinds are still the new meal's guess (`MealSources.tapped`); false when editing.
    var sourcesGuessed: Binding<Bool> = .constant(false)
    @Binding var place: PlaceDraft?
    @Binding var eaterIds: Set<Person.ID>
    @Binding var rating: MealRating?
    let day: DayKey
    let range: ClosedRange<Date>
    let now: Date
    let slots: [String]
    /// The meal being edited, so its own visit isn't "last time here".
    var entryId: JournalEntry.ID? = nil

    @Environment(FoodStore.self) private var store
    @Environment(\.me) private var me

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Where first: the dishes' kitchen follows from it, so suggestions and "Last
            // time here" know where we are before the first letter.
            group("Where") {
                ForEach(MealSource.allCases, id: \.self) { kind in
                    PhoneChoice(title: "\(kind.emoji) \(kind.label)", isOn: sources.contains(kind)) {
                        sources = sources.tapped(kind, replacingGuess: sourcesGuessed.wrappedValue)
                        sourcesGuessed.wrappedValue = false
                    }
                        .accessibilityHint(sources.tapHint(kind, guessed: sourcesGuessed.wrappedValue))
                        .accessibilityIdentifier("source-\(kind.rawValue)")
                }
            }
            if sources.hasPlace {
                RestaurantField(place: $place, prompt: sources.placePrompt)
                    .zIndex(1)
            }
            dishLines
            LogTimeField(
                time: $time, range: range, now: now,
                suggestions: MealSlot.timeSuggestions(slot: slot, day: day, calendar: store.calendar),
                accessibilityLabel: "Time eaten", identifier: "time-eaten", calendar: store.calendar
            ) {
                label("When")
            }
            group("Meal") {
                ForEach(slots, id: \.self) { name in
                    PhoneChoice(title: "\(MealSlot.named(name).emoji) \(name)", isOn: slot == name) { slot = name }
                }
            }
            group("Who ate") {
                ForEach(people) { person in
                    PersonPill(person: person, title: person.id == me?.id ? "You" : nil, isOn: eaterIds.contains(person.id)) {
                        toggle(person.id)
                    }
                }
            }
            // With dishes, the faces are on them.
            if dishes.isEmpty {
                group("Would eat again?") {
                    ForEach(MealRating.allCases, id: \.self) { choice in
                        PhoneChoice(title: choice.emoji, isOn: rating == choice) { rating = choice }
                            .accessibilityLabel(choice.phrase)
                    }
                }
            }
        }
    }

    private var dishLines: some View {
        let known = store.place(matching: sources.hasPlace ? place : nil)
        return DishLinesField(
            style: .phone,
            edit: $dishes,
            kitchen: DishFormKitchen.of(sources: sources, place: sources.hasPlace ? place : nil, known: known),
            lastTime: known.flatMap { store.book.lastTime(at: $0.id, excluding: entryId)?.dishes } ?? []
        )
    }

    /// You first, then everyone else in the household's order.
    private var people: [Person] {
        store.people.filter { $0.id == me?.id } + store.people.filter { $0.id != me?.id }
    }

    /// Someone always ate it: the last one can't be taken off.
    private func toggle(_ id: Person.ID) {
        if eaterIds.contains(id) {
            if eaterIds.count > 1 { eaterIds.remove(id) }
        } else {
            eaterIds.insert(id)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).phoneFont(.body, 14, weight: 700, relativeTo: .subheadline)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            FlowLayout(spacing: 6, lineSpacing: 0) { content() }
        }
    }
}
