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
    var slot: String
    let slotWasGuessed: Bool
    var source: MealSource = .home
    var eaterIds: Set<Int64>
    var rating: MealRating = .again
    var title = ""
    var photo: UIImage?
    /// Today's page; the note strip writes on `noteLine` of it.
    let note: PageEditor
    let noteLine: Int
    /// An ink picked in this sheet; otherwise the single eater's own pen.
    var chosenInk: PageInk?

    init(request: CaptureRequest, store: FoodStore, now: Date) {
        day = request.day
        let guessed = MealSlot.guess(at: now, calendar: store.calendar, enabled: store.slots) ?? store.slots.first ?? "Lunch"
        slot = request.slot ?? guessed
        slotWasGuessed = request.slot == nil
        eaterIds = Set(store.people.compactMap(\.id))
        let drawing = store.pageDrawing(for: request.day)
        note = PageEditor(day: request.day, drawing: drawing)
        noteLine = PageGeometry.nextFreeLine(strokeBounds: drawing.strokeBounds)
    }

    var emoji: String {
        DishIllustration.suggestEmoji(for: title) ?? DishIllustration.fallbackEmoji
    }

    func ink(people: [Person], fallback: PageInk) -> PageInk {
        if let chosenInk { return chosenInk }
        if eaterIds.count == 1, let person = people.first(where: { $0.id == eaterIds.first }) {
            return PageInk.defaultInk(for: person.color)
        }
        return fallback
    }

    func draft(now: Date, calendar: Calendar, today: DayKey) -> MealDraft {
        let eatenAt: Date
        if day == today {
            eatenAt = now
        } else {
            let minute = MealSlot.named(slot).typicalMinute ?? 12 * 60
            eatenAt = calendar.date(byAdding: .minute, value: minute, to: day.startDate(in: calendar)) ?? now
        }
        return MealDraft(
            day: day,
            slot: slot,
            source: source,
            title: title,
            rating: rating,
            eaterIds: Array(eaterIds),
            noteLine: note.hasChanges ? noteLine : nil,
            eatenAt: eatenAt
        )
    }
}

/// The "Snap a meal" sheet: live camera (or a photo picker), the meal form, an optional
/// Apple Pencil note on today's page, then a polaroid that develops and drops in.
struct CaptureSheet: View {
    let request: CaptureRequest
    var doneTitle = "Back to diary"
    let onClose: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var form: CaptureForm?
    @State private var saved: JournalEntry?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        ZStack {
            if let saved {
                SavedOverlay(entry: saved, doneTitle: doneTitle, onDone: onClose)
                    .transition(.opacity)
            } else {
                Color(hex: 0x14_0F0A).opacity(0.38)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                if let form {
                    sheet(form)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .onAppear {
            if form == nil { form = CaptureForm(request: request, store: store, now: .now) }
        }
    }

    private func sheet(_ form: CaptureForm) -> some View {
        HStack(alignment: .top, spacing: 28) {
            Viewfinder(form: form, isSaving: isSaving) { image in
                form.photo = image
                Task { await save(form) }
            }
            .frame(width: 370, height: 560)
            CaptureFormView(form: form, isSaving: isSaving, error: error) {
                Task { await save(form) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.leading, 22)
        .padding(.trailing, 28)
        .padding(.vertical, 22)
        .frame(width: 920)
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
                photo: form.photo,
                page: form.note.hasChanges ? form.note.drawing : nil
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
                .frame(width: 370, height: 560)
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
            .padding(.top, 14)

            label("Meal")
            FlowLayout(spacing: 8) {
                ForEach(store.slots, id: \.self) { slot in
                    ChoicePill("\(MealSlot.named(slot).emoji) \(slot)", isSelected: form.slot == slot) { form.slot = slot }
                }
            }

            label("Made by")
            HStack(spacing: 8) {
                ForEach(MealSource.allCases, id: \.self) { source in
                    ChoicePill("\(source.emoji) \(source.label)", isSelected: form.source == source) { form.source = source }
                }
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
                    ChoicePill(rating.emoji, isSelected: form.rating == rating) { form.rating = rating }
                        .accessibilityLabel(rating.phrase)
                }
            }

            label("Note", note: "optional · Apple Pencil · lands on line \(form.noteLine + 1) of \(pageName)")
            NoteStrip(form: form)
            InkPalette(selected: form.ink(people: store.people, fallback: store.ink)) { form.chosenInk = $0 }
                .padding(.top, 10)

            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if let error {
                    Text(error)
                        .font(.body(13.5, weight: 600))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                } else {
                    Image(systemName: "camera").font(.system(size: 13, weight: .semibold))
                    Text(MealCamera.hasCamera ? "Tap the shutter to save. No photo? Just write and tap Save." : "Pick a photo or just write, then tap Save.")
                        .font(.body(13.5, weight: 600))
                        .lineLimit(2)
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
        .frame(maxHeight: .infinity, alignment: .topLeading)
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
            .padding(.top, 14)
            .padding(.bottom, 8)
    }
}

private struct WhoButton: View {
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

/// One ruled line of the day's page, zoomed into a writing strip, with a mini page
/// beside it that shows where the note lands.
private struct NoteStrip: View {
    let form: CaptureForm

    @Environment(FoodStore.self) private var store
    @Environment(\.displayScale) private var displayScale

    static let width: CGFloat = 334

    var body: some View {
        let viewport = PageViewport.strip(line: form.noteLine, width: Self.width)
        let height = viewport.stripHeight
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                PagePaper(number: dayNumber, scale: viewport.scale, numberColor: Theme.accent)
                    .frame(width: PageGeometry.size.width * viewport.scale, height: PageGeometry.size.height * viewport.scale)
                    .offset(y: -viewport.origin.y * viewport.scale)
                PageCanvas(
                    editor: form.note,
                    revision: form.note.revision,
                    viewport: viewport,
                    ink: form.ink(people: store.people, fallback: store.ink),
                    tip: store.tip,
                    isErasing: false,
                    allowsFinger: store.allowsFingerDrawing
                )
                .frame(width: Self.width, height: height)
            }
            .frame(width: Self.width, height: height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line))
            .overlay(alignment: .topTrailing) {
                if form.note.canUndo {
                    Button { form.note.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 26, height: 26)
                            .background(Theme.surface2, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel("Undo note")
                }
            }

            DayPageView(
                day: form.day,
                scale: 0.5,
                numberColor: Theme.accent,
                image: form.note.drawing.pageImage(scale: 0.5, displayScale: displayScale)
            )
            .overlay(alignment: .topLeading) {
                let line = PageGeometry.lineRect(form.noteLine)
                Rectangle()
                    .fill(Theme.accent.opacity(0.22))
                    .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1.5))
                    .frame(width: line.width * 0.5, height: line.height * 0.5)
                    .offset(y: line.minY * 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .shadow(color: FoodStyle.shadow.opacity(0.25), radius: 6, y: 5)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.line))
        }
    }

    private var dayNumber: String { String(Int(form.day.rawValue.suffix(2)) ?? 0) }
}

// MARK: - Saved

/// "Saved to Saturday": the polaroid develops from sepia to color and drops in.
private struct SavedOverlay: View {
    let entry: JournalEntry
    let doneTitle: String
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
            Button(doneTitle, action: onDone)
                .buttonStyle(SecondaryButtonStyle())
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
        let how = entry.source == .home ? "Home-cooked" : "Delivered"
        let note = entry.noteLine != nil ? ", plus a handwritten note" : ""
        return "\(how) \(entry.slot.lowercased()) \(who)\(note). It's on the calendar now, next to the rest of your day."
    }
}
