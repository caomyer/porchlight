import AVFoundation
import PencilKit
import PhotosUI
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
    var photo: UIImage?

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
                    .onTapGesture(perform: onClose)
                if let form {
                    sheet(form)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
        }
    }

    private func sheet(_ form: CaptureForm) -> some View {
        HStack(alignment: .top, spacing: 28) {
            Viewfinder(form: form, isSaving: isSaving) { image in
                form.photo = image
                Task { await save(form) }
            }
            .frame(width: 370)
            .frame(maxHeight: .infinity)
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
            Button(action: onClose) {
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

    private func save(_ form: CaptureForm) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let now = Date.now
        do {
            let entry = try await store.addMeal(
                form.draft(now: now, calendar: store.calendar, today: store.today(now)),
                photo: form.photo
            )
            error = nil
            withAnimation(.easeInOut(duration: 0.3)) { saved = entry }
        } catch {
            self.error = error.userMessage
        }
    }
}

// MARK: - Viewfinder

private struct Viewfinder: View {
    let form: CaptureForm
    let isSaving: Bool
    let onShot: (UIImage) -> Void

    @State private var camera = MealCamera()
    @State private var state: CameraState = .starting
    @State private var deviceID: String?
    @State private var captureAngle: CGFloat = 0
    @State private var flash = false
    @State private var pickerItem: PhotosPickerItem?
    @AppStorage("food.cameraFront") private var useFront = true

    enum CameraState { case starting, live, denied, none }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x6A5341), Color(hex: 0x2A201A)], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 330)
            content
            if state == .live || form.photo != nil {
                brackets
            }
            VStack {
                Text(hint)
                    .font(.body(13, weight: 600))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
                    .padding(.horizontal, 24)
                Spacer()
                bottomControls
                    .padding(.bottom, 24)
            }
            Color.white.opacity(flash ? 0.95 : 0).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task { await startCamera() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    form.photo = image
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let photo = form.photo {
            Image(uiImage: photo).resizable().scaledToFill()
                .frame(width: 370, height: 600)
                .clipped()
        } else if state == .live {
            CameraPreview(camera: camera, deviceID: deviceID) { captureAngle = $0 }
        } else {
            // No camera: the plate previews the dish's emoji as you type its name.
            ZStack {
                Circle().fill(Color(hex: 0xFBFAF6))
                Circle().stroke(Color(hex: 0xE7E1D6), lineWidth: 10).padding(26)
                Text(form.emoji).font(.system(size: 112))
            }
            .frame(width: 250, height: 250)
            .shadow(color: .black.opacity(0.45), radius: 20, y: 24)
            .offset(y: -20)
            .animation(.spring(duration: 0.3), value: form.emoji)
        }
    }

    private var brackets: some View {
        let corner = 34.0
        return ZStack {
            ForEach(0..<4, id: \.self) { index in
                Bracket()
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                    .frame(width: corner, height: corner)
                    .rotationEffect(.degrees(Double(index) * 90))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading][index])
            }
        }
        .frame(width: 258, height: 312)
        .offset(y: -24)
        .allowsHitTesting(false)
    }

    private var hint: String {
        switch state {
        case .live where form.photo == nil: "Center the plate · tap the shutter"
        case .denied: "Camera access is off. Turn it on in Settings › Porchlight, or pick a photo."
        case .none where form.photo == nil: "No camera here. Pick a photo, or just write and save."
        default: ""
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        if form.photo != nil {
            Button { form.photo = nil } label: {
                Label("Retake", systemImage: "arrow.counterclockwise")
                    .font(.body(14, weight: 700))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.9), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        } else if state == .live {
            HStack {
                Color.clear.frame(width: 48, height: 48)
                Spacer()
                Button(action: shoot) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 74, height: 74)
                        .padding(5)
                        .background(Color.white.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel("Take photo and save")
                Spacer()
                if MealCamera.canSwitch {
                    Button(action: switchCamera) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch camera")
                } else {
                    Color.clear.frame(width: 48, height: 48)
                }
            }
            .padding(.horizontal, 28)
        } else if state != .starting {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
                    .font(.body(15, weight: 700))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.92), in: Capsule())
            }
        }
    }

    private func startCamera() async {
        guard MealCamera.hasCamera else { state = .none; return }
        guard await MealCamera.requestAccess() else { state = .denied; return }
        do {
            try await camera.start(position: useFront ? .front : .back)
            deviceID = camera.device?.uniqueID
            state = .live
        } catch {
            state = .none
        }
    }

    private func switchCamera() {
        useFront.toggle()
        Task {
            try? await camera.start(position: useFront ? .front : .back)
            deviceID = camera.device?.uniqueID
        }
    }

    private func shoot() {
        withAnimation(.easeOut(duration: 0.05)) { flash = true }
        withAnimation(.easeOut(duration: 0.45).delay(0.05)) { flash = false }
        let angle = captureAngle
        Task {
            if let image = try? await camera.capture(rotationAngle: angle) {
                onShot(image)
            }
        }
    }
}

/// The top-left corner of a viewfinder bracket; rotated for the other corners.
private struct Bracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 10
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
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

            label("Meal")
            HStack(alignment: .center, spacing: 8) {
                FlowLayout(spacing: 8) {
                    ForEach(store.slots, id: \.self) { slot in
                        FoodChoicePill("\(MealSlot.named(slot).emoji) \(slot)", isSelected: form.slot == slot) { form.slot = slot }
                    }
                }
                Spacer(minLength: 4)
                AtTimeField(time: $form.time, range: form.timeRange(now: .now), calendar: store.calendar)
            }

            label("From")
            HStack(spacing: 8) {
                ForEach(MealSource.allCases, id: \.self) { source in
                    FoodChoicePill("\(source.emoji) \(source.label)", isSelected: form.source == source) { form.source = source }
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
                    Text(MealCamera.hasCamera ? "Tap the shutter, or just write and tap Save." : "Pick a photo or just write, then tap Save.")
                        .font(.body(13.5, weight: 600))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onSave) {
                    if isSaving { ProgressView().tint(Theme.accentInk) } else { Text("Save") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
            }
            .foregroundStyle(Theme.muted)
        }
        .padding(.top, 14)
        .frame(minHeight: CaptureForm.minimumFormHeight, alignment: .topLeading)
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
        }
        return "\(what) \(who). It's on the calendar now, next to the rest of your day."
    }
}
