import PencilKit
import SwiftUI

/// A request to snap a meal: for a day, optionally for a given slot.
struct CaptureRequest: Identifiable, Equatable {
    let id = UUID()
    var day: DayKey
    var slot: String?
}

/// Everything the capture form edits, with smart defaults.
@MainActor
@Observable
final class CaptureForm {
    let day: DayKey
    var slot: String {
        didSet { slotWasPicked = true }
    }
    let slotWasGuessed: Bool
    /// Set once someone taps a meal; until then picking a time re-guesses it.
    private(set) var slotWasPicked = false
    /// When it was eaten: now for today, else the meal's usual time that day.
    var time: LogTime {
        didSet { reguessSlot() }
    }
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let enabledSlots: [String]
    var source: MealSource = .home
    var eaterIds: Set<Int64>
    var rating: MealRating = .again
    /// The restaurant, for delivery or eating out.
    var place: PlaceDraft?
    var title = ""
    /// Photos taken or picked so far, saved to disk but not attached until Save. Cover first.
    var photos: [MealPhotoItem] = []
    /// Photos still being written to disk.
    var savingPhotos = 0

    /// The photo files this capture owns until it saves.
    var storedPhotos: [FoodPhotoStore.Stored] {
        photos.compactMap { if case let .added(stored) = $0 { stored } else { nil } }
    }

    /// Room left for more photos, counting ones still being saved.
    var photoRoom: Int { max(AppDatabase.photoLimit - photos.count - savingPhotos, 0) }

    init(request: CaptureRequest, store: FoodStore, now: Date) {
        day = request.day
        let guessed = MealSlot.guess(at: now, calendar: store.calendar, enabled: store.slots) ?? store.slots.first ?? "Lunch"
        let slot = request.slot ?? guessed
        self.slot = slot
        slotWasGuessed = request.slot == nil
        calendar = store.calendar
        enabledSlots = store.slots
        time = request.day == store.today(now) ? .justNow : .at(MealSlot.usualTime(of: slot, on: request.day, calendar: store.calendar))
        slotWasPicked = request.slot != nil
        eaterIds = Set(store.people.compactMap(\.id))
    }

    var emoji: String {
        DishIllustration.suggestEmoji(for: title) ?? DishIllustration.fallbackEmoji
    }

    /// The form never gets shorter than this; it grows to fit a restaurant or a day page.
    static let minimumFormHeight: CGFloat = 620

    /// The meal's day, up to now if that's today.
    func timeRange(now: Date) -> ClosedRange<Date> {
        let start = day.startDate(in: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-60) ?? start
        return start...max(start, min(end, now))
    }

    private func reguessSlot() {
        guard !slotWasPicked, case let .at(date) = time,
              let guess = MealSlot.guess(at: date, calendar: calendar, enabled: enabledSlots), guess != slot else { return }
        slot = guess
        slotWasPicked = false
    }

    func draft(now: Date, calendar: Calendar, today: DayKey) -> MealDraft {
        let range = timeRange(now: now)
        let eatenAt = min(max(time.start(now: now), range.lowerBound), range.upperBound)
        return MealDraft(
            day: day,
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

/// The "Snap a meal" sheet: live camera (or a photo picker), the meal form with a way to
/// write on the day's shared page, then a polaroid that develops and drops in.
struct CaptureSheet: View {
    let request: CaptureRequest
    var doneTitle = "Back to diary"
    /// Starts a fresh capture for the same meal ("Snap another"), e.g. a second dish.
    var onAnother: ((CaptureRequest) -> Void)?
    /// Debug screenshots only: start on the "Saved" overlay for this entry.
    var previewSaved: JournalEntry?
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var form: CaptureForm?
    @State private var saved: JournalEntry?
    @State private var isSaving = false
    @State private var error: String?
    /// The restaurant field (low in the form) is being typed into.
    @State private var lowFieldFocused = false
    /// The day's shared page is open for writing, over the form.
    @State private var writingNotes = false
    /// Closing would throw away photos that were never saved; asking first.
    @State private var confirmingDiscard = false

    var body: some View {
        ZStack {
            if let saved {
                SavedOverlay(
                    entry: saved,
                    doneTitle: doneTitle,
                    onAnother: onAnother.map { another in { another(CaptureRequest(day: saved.dayKey, slot: saved.slot)) } },
                    onDone: onClose
                )
                    .transition(.opacity)
            } else {
                Color(hex: 0x14_0F0A).opacity(0.38)
                    .ignoresSafeArea()
                    .onTapGesture(perform: requestClose)
                if let form {
                    sheet(form)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    if confirmingDiscard {
                        discardPrompt(form)
                            .transition(.opacity)
                            .zIndex(2)
                    }
                    if writingNotes {
                        WriteDaySheet(day: form.day, today: store.today()) {
                            withAnimation(.easeInOut(duration: 0.2)) { writingNotes = false }
                        }
                        .transition(.opacity)
                        .zIndex(1)
                    }
                }
            }
        }
        // The dish name field is near the top, well above the keyboard; re-centering the
        // tall sheet above the keyboard would push that field off screen. The restaurant
        // field sits lower, so while it is typed into the sheet does move up.
        .onPreferenceChange(KeyboardAvoidanceKey.self) { lowFieldFocused = $0 }
        .ignoresSafeArea(lowFieldFocused ? [] : .keyboard)
        .animation(.easeOut(duration: 0.25), value: lowFieldFocused)
        .onAppear {
            if form == nil { form = CaptureForm(request: request, store: store, now: .now) }
            if let previewSaved { saved = previewSaved }
            #if DEBUG
            // `-debugCaptureShots N` adds N generated photos as if the shutter took them.
            let shots = UserDefaults.standard.integer(forKey: "debugCaptureShots")
            if shots > 0, let form, form.photos.isEmpty, form.savingPhotos == 0 {
                add((0..<shots).map { SamplePhoto.image(palette: $0, emoji: "🍝") }, to: form)
            }
            #endif
        }
    }

    private func sheet(_ form: CaptureForm) -> some View {
        HStack(alignment: .top, spacing: 28) {
            MealViewfinder(
                emoji: form.emoji,
                photoCount: form.photos.count + form.savingPhotos,
                isBusy: isSaving,
                onShot: { add([$0], to: form) },
                onPick: { add($0, to: form) }
            ) {
                // New shots line up right under the camera that took them.
                VStack(alignment: .leading, spacing: 4) {
                    Text("PHOTOS · \(form.photos.count) OF \(AppDatabase.photoLimit)")
                        .font(.body(11.5, weight: 800))
                        .tracking(1)
                        .foregroundStyle(Color.white.opacity(0.75))
                    MealPhotoRow(
                        items: Binding(get: { form.photos }, set: { form.photos = $0 }),
                        pending: form.savingPhotos,
                        size: 52,
                        emptyText: MealCamera.hasCamera ? "Your shots and picks from Photos line up here." : "Photos you pick line up here.",
                        onDark: true
                    ) { EmptyView() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 370)
            .frame(maxHeight: .infinity, alignment: .top)
            CaptureFormView(form: form, isSaving: isSaving, error: error, onWriteNotes: { writingNotes = true }) {
                Task { await save(form) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.leading, 22)
        .padding(.trailing, 28)
        .padding(.vertical, 22)
        // The viewfinder stretches to the form's height, whatever the form holds.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 920)
        .animation(.easeInOut(duration: 0.2), value: form.source.hasPlace)
        .background(SurfaceShape(cornerRadius: 28, elevation: 2.5))
        .overlay(alignment: .topTrailing) {
            Button(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(20)
            .accessibilityLabel("Close")
        }
    }

    /// Saves each image to disk off the main actor and adds it to the form's photos, up to
    /// the limit. Nothing is attached to a meal until Save.
    private func add(_ images: [UIImage], to form: CaptureForm) {
        for image in images.prefix(form.photoRoom) {
            form.savingPhotos += 1
            Task {
                defer { form.savingPhotos -= 1 }
                do {
                    let stored = try await store.savePhoto(image)
                    if form.photos.count < AppDatabase.photoLimit, saved == nil {
                        withAnimation(.easeOut(duration: 0.2)) { form.photos.append(.added(stored)) }
                    } else {
                        store.discard([stored])
                    }
                } catch {
                    self.error = error.userMessage
                }
            }
        }
    }

    private func save(_ form: CaptureForm) async {
        guard !isSaving, form.savingPhotos == 0 else { return }
        isSaving = true
        defer { isSaving = false }
        let now = Date.now
        do {
            let entry = try store.addMeal(form.draft(now: now, calendar: store.calendar, today: store.today(now)), photos: form.storedPhotos)
            error = nil
            withAnimation(.easeInOut(duration: 0.3)) { saved = entry }
        } catch {
            self.error = error.userMessage
        }
    }

    /// Closes right away unless that would lose photos that were never saved.
    private func requestClose() {
        if saved == nil, let form, !form.storedPhotos.isEmpty {
            withAnimation(.easeOut(duration: 0.15)) { confirmingDiscard = true }
        } else {
            onClose()
        }
    }

    private func discardPrompt(_ form: CaptureForm) -> some View {
        let count = form.storedPhotos.count
        return ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
                .onTapGesture { confirmingDiscard = false }
            VStack(alignment: .leading, spacing: 10) {
                Text(count == 1 ? "Discard 1 photo?" : "Discard \(count) photos?")
                    .font(.display(26))
                Text("This meal isn't saved yet, so its photos would go too.")
                    .font(.body(15, weight: 600))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    Spacer()
                    Button("Keep editing") { withAnimation(.easeOut(duration: 0.15)) { confirmingDiscard = false } }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Discard") {
                        store.discard(form.storedPhotos)
                        form.photos = []
                        onClose()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 10)
            }
            .padding(26)
            .frame(width: 440)
            .background(SurfaceShape(cornerRadius: 24, elevation: 2.5))
        }
    }
}

// MARK: - Form

private struct CaptureFormView: View {
    @Bindable var form: CaptureForm
    let isSaving: Bool
    let error: String?
    let onWriteNotes: () -> Void
    let onSave: () -> Void

    @Environment(FoodStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(form.slotWasGuessed ? "\(form.slot), probably" : form.slot)
                .font(.display(30))
                .lineLimit(1)
            Text(subtitle)
                .font(.body(14, weight: 600))
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)

            HStack(spacing: 10) {
                Text(form.emoji).font(.system(size: 22))
                TextField("What was it? e.g. Dan dan noodles", text: $form.title)
                    .font(.body(17, weight: 600))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
            }
            .fieldStyle()
            .padding(.top, 12)

            // The time rides on the label line, so the meals get the row's full width.
            LogTimeField(
                time: $form.time,
                range: form.timeRange(now: .now),
                suggestions: MealSlot.timeSuggestions(slot: form.slot, day: form.day, calendar: store.calendar),
                accessibilityLabel: "Time eaten",
                identifier: "time-eaten",
                calendar: store.calendar
            ) {
                SheetLabel(title: "Meal", note: nil)
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
            FlowLayout(spacing: 8) {
                ForEach(store.slots, id: \.self) { slot in
                    FoodChoicePill("\(MealSlot.named(slot).emoji) \(slot)", isSelected: form.slot == slot) { form.slot = slot }
                }
            }

            label("From")
            FlowLayout(spacing: 8) {
                ForEach(MealSource.allCases, id: \.self) { source in
                    FoodChoicePill("\(source.emoji) \(source.label)", isSelected: form.source == source, compact: true) { form.source = source }
                }
            }
            if form.source.hasPlace {
                RestaurantField(place: $form.place, prompt: form.source == .dineOut ? "Where? Search restaurants" : "From where? Search restaurants")
                    .padding(.top, 10)
                    .zIndex(1)
            }

            label("Who ate")
            HStack(spacing: 10) {
                ForEach(store.people) { person in
                    WhoButton(person: person, isSelected: form.eaterIds.contains(person.id ?? -1)) {
                        guard let id = person.id else { return }
                        if form.eaterIds.contains(id) {
                            if form.eaterIds.count > 1 { form.eaterIds.remove(id) }
                        } else {
                            form.eaterIds.insert(id)
                        }
                    }
                }
            }

            label("Would eat again?")
            HStack(spacing: 8) {
                ForEach(MealRating.allCases, id: \.self) { rating in
                    FoodChoicePill(rating.emoji, isSelected: form.rating == rating) { form.rating = rating }
                        .accessibilityLabel(rating.phrase)
                }
            }

            label("Day notes", note: "optional · one page per day, shared by everyone")
            DayNotesRow(day: form.day, pageName: pageName, onWrite: onWriteNotes)

            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if let error {
                    Text(error)
                        .font(.body(13.5, weight: 600))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                } else {
                    Image(systemName: "camera").font(.system(size: 13, weight: .semibold))
                    Text(footnote)
                        .font(.body(13.5, weight: 600))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onSave) {
                    if isSaving { ProgressView().tint(Theme.accentInk) } else { Text("Save") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving || form.savingPhotos > 0)
            }
            .foregroundStyle(Theme.muted)
        }
        .padding(.top, 14)
        .frame(minHeight: CaptureForm.minimumFormHeight, alignment: .topLeading)
        .onChange(of: form.photos) { old, new in
            // A photo removed from the row was never saved; its files go now.
            store.discard(files: MealPhotoItem.unusedFiles(from: old, to: new))
        }
    }

    private var footnote: String {
        switch form.photos.count {
        case 0: MealCamera.hasCamera ? "Shoot, pick from Photos, or just write and save." : "Pick photos or just write, then tap Save."
        case 1: "1 photo ready. Fill in anything else, then Save."
        default: "\(form.photos.count) photos ready. Fill in anything else, then Save."
        }
    }

    private var subtitle: String {
        let today = store.today()
        if form.day != today {
            return "For " + form.day.startDate(in: store.calendar).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return form.slotWasGuessed ? "Guessed from the time of day" : "Today"
    }

    private var pageName: String {
        form.day == store.today() ? "today's page" : "the day's page"
    }

    private func label(_ title: String, note: String? = nil) -> some View {
        SheetLabel(title: title, note: note)
            .padding(.top, 12)
            .padding(.bottom, 7)
    }
}

struct WhoButton: View {
    let person: Person
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let color = person.color.color
        Button(action: action) {
            HStack(spacing: 8) {
                Avatar(person: person, size: 32)
                Text(person.name)
                    .font(.body(14, weight: 700))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 5)
            .background(isSelected ? color.wash(0.12) : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? color : Theme.line, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(color, in: Circle())
                        .offset(x: 4, y: -5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The day's shared page as a small paper preview, with a way to write on it.
/// Notes belong to the day, not to a meal, so everyone writes on the same page.
struct DayNotesRow: View {
    let day: DayKey
    /// e.g. "today's page".
    let pageName: String
    let onWrite: () -> Void

    @Environment(FoodStore.self) private var store

    static let previewScale: CGFloat = 0.62

    var body: some View {
        let hasInk = store.snapshot.pages[day.rawValue] != nil
        HStack(spacing: 16) {
            Button(action: onWrite) {
                DayPageView(day: day, scale: Self.previewScale, numberColor: day == store.today() ? Theme.accent : Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.line))
                    .shadow(color: FoodStyle.shadow.opacity(0.22), radius: 6, y: 5)
                    .rotationEffect(.degrees(-1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(pageName)")
            VStack(alignment: .leading, spacing: 10) {
                Text(hasInk ? "Anyone can add to \(pageName)." : "Nothing written on \(pageName) yet.")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onWrite) {
                    Label("Write on \(pageName)", systemImage: "pencil.and.scribble")
                        .font(.body(14, weight: 700))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Saved

/// "Saved to Saturday": the polaroid develops from sepia to color and drops in.
private struct SavedOverlay: View {
    let entry: JournalEntry
    let doneTitle: String
    var onAnother: (() -> Void)?
    let onDone: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var dropped = false
    @State private var developed = false

    var body: some View {
        VStack(spacing: 0) {
            Polaroid(entry: entry, rotation: 0, emojiSize: 92, captionSize: 22, plate: 0.5, badgeSize: 26)
                .environment(\.foodPreferFullPhoto, true)
                .frame(width: 220)
                .grayscale(developed ? 0 : 1)
                .colorMultiply(developed ? .white : Color(hex: 0xEBD2A8))
                .brightness(developed ? 0 : 0.18)
                .contrast(developed ? 1 : 0.55)
                .rotationEffect(.degrees(dropped ? -3 : 9))
                .offset(y: dropped ? 0 : -140)
                .opacity(dropped ? 1 : 0)
            Text("Saved to \(dayName)")
                .font(.display(46))
                .padding(.top, 28)
            Text(summary)
                .font(.body(18, weight: 600))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .padding(.top, 8)
            HStack(spacing: 12) {
                if let onAnother {
                    Button(action: onAnother) {
                        Label("Snap another \(entry.slot.lowercased()) dish", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button(doneTitle, action: onDone)
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PersonColor.ochre.color.wash(0.2, over: Theme.background))
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.62)) { dropped = true }
            withAnimation(.easeOut(duration: 1.8)) { developed = true }
        }
    }

    private var dayName: String {
        entry.dayKey.startDate(in: store.calendar).formatted(.dateTime.weekday(.wide))
    }

    private var summary: String {
        let people = store.eaters(of: entry)
        let who = store.ateTogether(entry) ? "for everyone" : "for " + ListFormat.join(people.map(\.name))
        let slot = entry.slot.lowercased()
        let place = store.place(of: entry)?.name
        let what = switch entry.source {
        case .home: "Home-cooked \(slot)"
        case .delivery: place.map { "\(slot.prefix(1).uppercased() + slot.dropFirst()) delivered from \($0)" } ?? "Delivered \(slot)"
        case .dineOut: place.map { "\(slot.prefix(1).uppercased() + slot.dropFirst()) out at \($0)" } ?? "\(slot.prefix(1).uppercased() + slot.dropFirst()) out"
        case .company: "\(slot.prefix(1).uppercased() + slot.dropFirst()) at work"
        }
        return "\(what) \(who). It's on the calendar now, next to the rest of your day."
    }
}
