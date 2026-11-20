import AVFoundation
import PhotosUI
import SwiftUI

// Taking, picking and arranging a meal's photos. Shared by the capture sheet, the meal
// detail and its edit form. A meal has up to `AppDatabase.photoLimit` photos; the first
// is the cover, shown wherever many meals appear at once.

// MARK: - Viewfinder

/// A square live camera window, exactly the polaroid a shot becomes, with the shutter, a
/// Photos button and a camera switch below it. The shutter only takes a photo: it goes to
/// `onShot` and the camera stays live for another angle. Without a camera the window shows
/// the dish's emoji on a plate and offers Photos. `below` goes under the controls, on the
/// same dark panel (the capture sheet puts the meal's photos there).
struct MealViewfinder<Below: View>: View {
    /// Shown on the plate when there is no camera.
    let emoji: String
    /// Photos the meal already has, to say when it's full.
    let photoCount: Int
    var isBusy = false
    let onShot: (UIImage) -> Void
    let onPick: ([UIImage]) -> Void
    @ViewBuilder var below: () -> Below

    @State private var camera = MealCamera()
    @State private var state: CameraState = .starting
    @State private var deviceID: String?
    @State private var captureAngle: CGFloat = 0
    @State private var flash = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @AppStorage("food.cameraFront") private var useFront = true

    enum CameraState { case starting, live, denied, none }

    private var remaining: Int { max(AppDatabase.photoLimit - photoCount, 0) }

    static var panel: Color { Color(hex: 0x2A201A) }

    var body: some View {
        VStack(spacing: 0) {
            window
            bottomControls
                .frame(minHeight: 84)
                .padding(.vertical, 16)
            below()
            Spacer(minLength: 0)
        }
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task { await startCamera() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let images = await PhotoPicking.load(items)
                pickerItems = []
                if !images.isEmpty { onPick(images) }
            }
        }
    }

    /// The square the polaroid shows. The preview fills it, so it shows the middle square
    /// of the camera frame, the same square a shot keeps for the wall.
    private var window: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x6A5341), Color(hex: 0x2A201A)], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 330)
            content
            VStack {
                Text(hint)
                    .font(.body(13, weight: 700))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("viewfinder-hint")
                Spacer()
            }
            Color.white.opacity(flash ? 0.95 : 0).allowsHitTesting(false)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if state == .live {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewfinder-window")
    }

    @ViewBuilder
    private var content: some View {
        if state == .live {
            CameraPreview(camera: camera, deviceID: deviceID) { captureAngle = $0 }
        } else {
            // No camera: the plate previews the dish's emoji as you type its name.
            ZStack {
                Circle().fill(Color(hex: 0xFBFAF6))
                Circle().stroke(Color(hex: 0xE7E1D6), lineWidth: 10).padding(26)
                Text(emoji).font(.system(size: 112))
            }
            .frame(width: 220, height: 220)
            .shadow(color: .black.opacity(0.45), radius: 20, y: 18)
            .animation(.spring(duration: 0.3), value: emoji)
        }
    }

    private var hint: String {
        if remaining == 0 { return "That's \(AppDatabase.photoLimit) photos, the most a meal can have" }
        switch state {
        case .live: return photoCount > 0 ? "Added below · another angle?" : "This square is your polaroid"
        case .denied: return "Camera access is off. Turn it on in Settings › Porchlight, or pick photos."
        case .none: return "No camera here. Pick photos, or just write and save."
        case .starting: return ""
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        if state == .live {
            HStack {
                photosButton(compact: true)
                Spacer()
                Button(action: shoot) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 74, height: 74)
                        .padding(5)
                        .background(Color.white.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy || remaining == 0)
                .opacity(remaining == 0 ? 0.4 : 1)
                .accessibilityLabel("Take photo")
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
            .padding(.horizontal, 24)
        } else if state != .starting {
            photosButton(compact: false)
        }
    }

    /// Picks several photos at once, up to the meal's remaining room.
    @ViewBuilder
    private func photosButton(compact: Bool) -> some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: max(remaining, 1), selectionBehavior: .ordered, matching: .images) {
            if compact {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Label("Choose photos", systemImage: "photo.on.rectangle")
                    .font(.body(15, weight: 700))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.92), in: Capsule())
            }
        }
        .disabled(isBusy || remaining == 0)
        .opacity(remaining == 0 ? 0.4 : 1)
        .accessibilityLabel("Choose from Photos")
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

extension MealViewfinder where Below == EmptyView {
    init(emoji: String, photoCount: Int, isBusy: Bool = false, onShot: @escaping (UIImage) -> Void, onPick: @escaping ([UIImage]) -> Void) {
        self.init(emoji: emoji, photoCount: photoCount, isBusy: isBusy, onShot: onShot, onPick: onPick) { EmptyView() }
    }
}

enum PhotoPicking {
    /// The picked images that could be read, in picking order.
    static func load(_ items: [PhotosPickerItem]) async -> [UIImage] {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        return images
    }
}

// MARK: - Photos row

/// What the photo row does to a meal's photos, kept apart so it can be tested.
enum MealPhotoOrder {
    /// The photo at `index` becomes the cover; the others keep their order.
    static func makeCover(_ index: Int, in items: [MealPhotoItem]) -> [MealPhotoItem] {
        guard index > 0, items.indices.contains(index) else { return items }
        var reordered = items
        reordered.insert(reordered.remove(at: index), at: 0)
        return reordered
    }

    /// The photos without the one at `index`; the next one up becomes the cover.
    static func remove(_ index: Int, from items: [MealPhotoItem]) -> [MealPhotoItem] {
        guard items.indices.contains(index) else { return items }
        var remaining = items
        remaining.remove(at: index)
        return remaining
    }

    /// The photos with the one reframed, if it is still where it was.
    static func reframe(_ id: MealPhoto.ID, at index: Int, in items: [MealPhotoItem], crop: PhotoCrop, thumbnail: Data) -> [MealPhotoItem] {
        guard items.indices.contains(index), items[index].id == id else { return items }
        var reframed = items
        reframed[index] = items[index].reframed(crop, thumbnail: thumbnail)
        return reframed
    }

    /// "Tap a photo to make it the cover or reframe it", under the row.
    static func hint(count: Int) -> String {
        count > 1 ? "Tap a photo to make it the cover or reframe it" : "Tap the photo to reframe it"
    }

    /// "Photos · 2 of 5", over the row.
    static func heading(count: Int) -> String {
        "Photos · \(count) of \(AppDatabase.photoLimit)"
    }
}

/// A meal's photos as small squares, cover first, on the wall and the phone alike. Tap one
/// to make it the cover or to reframe it, × to remove it. `trailing` goes after the photos,
/// e.g. a tile to add more. In a compact width the squares, words and reframe screen grow
/// with Dynamic Type, and reframing opens as a sheet instead of over the wall.
struct MealPhotoRow<Trailing: View>: View {
    @Binding var items: [MealPhotoItem]
    /// Photos still being saved, shown as placeholders.
    var pending = 0
    var size: CGFloat = 60
    var emptyText: String
    /// Drawn on the camera's dark panel rather than on paper.
    var onDark = false
    @ViewBuilder var trailing: () -> Trailing

    @Environment(FoodStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .body) private var growth: CGFloat = 1
    @State private var reframing: Reframing?
    /// The photo whose choices (Make cover, Reframe) are showing.
    @State private var choosing: MealPhoto.ID?

    private struct Reframing: Identifiable {
        let index: Int
        let item: MealPhotoItem
        var id: MealPhoto.ID { item.id }
    }

    private var isCompact: Bool { sizeClass == .compact }
    /// A square's side: the wall's, or on a phone grown with the text, up to half again.
    private var side: CGFloat { isCompact ? size * min(max(growth, 1), 1.5) : size }
    private var noteColor: Color { onDark ? Color.white.opacity(0.7) : Theme.muted }
    private var badgeRing: Color { onDark ? MealViewfinder<EmptyView>.panel : Theme.surface }

    /// Whether anything shows as a tile; without, the row is just its hint.
    private var hasTiles: Bool {
        !items.isEmpty || pending > 0 || Trailing.self != EmptyView.self
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasTiles {
                tiles
                    // Room for the × badges and the cover tag that hang off the tiles.
                    .padding(.top, 8)
            }
            if items.isEmpty && pending == 0 {
                Text(emptyText)
                    .sharedFont(.body, 13.5, weight: 600, relativeTo: .subheadline)
                    .foregroundStyle(noteColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !items.isEmpty {
                Text(MealPhotoOrder.hint(count: items.count))
                    .sharedFont(.body, 12.5, weight: 600, relativeTo: .footnote)
                    .foregroundStyle(noteColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: items)
        .wallCover(item: isCompact ? .constant(nil) : $reframing) { reframing in
            reframeSheet(reframing)
        }
        .sheet(item: isCompact ? $reframing : .constant(nil)) { reframing in
            reframeSheet(reframing)
        }
    }

    private func reframeSheet(_ reframing: Reframing) -> some View {
        ReframeSheet(item: reframing.item) { crop, thumbnail in
            items = MealPhotoOrder.reframe(reframing.item.id, at: reframing.index, in: items, crop: crop, thumbnail: thumbnail)
            CompanionCover.instantly { self.reframing = nil }
        } onCancel: {
            CompanionCover.instantly { self.reframing = nil }
        }
    }

    private func reframe(_ item: MealPhotoItem, at index: Int) {
        CompanionCover.instantly { reframing = Reframing(index: index, item: item) }
    }

    private var tiles: some View {
        FlowLayout(spacing: 12, lineSpacing: 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                tile(item, index: index)
            }
            ForEach(0..<pending, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface2)
                    .frame(width: side, height: side)
                    .overlay { ProgressView() }
            }
            trailing()
        }
    }

    /// Tapping a photo: the cover has only Reframe, so it opens straight away; another photo
    /// asks which, Make cover or Reframe, in a dialog at the photo (a popover on the wall, an
    /// action sheet on a phone).
    ///
    /// Not a `Menu`: on iOS 27 a menu takes every touch inside its square, whatever is drawn
    /// over it, so a tap on the × badge, which hangs over the square's corner, opened the
    /// menu instead of removing the photo. A plain button lets the badge above it win.
    private func tile(_ item: MealPhotoItem, index: Int) -> some View {
        let isCover = index == 0
        // A photo whose whole shot was lost has only its square left to show.
        let canReframe = store.image(of: item) != nil
        return Button {
            if !isCover {
                choosing = item.id
            } else if canReframe {
                reframe(item, at: index)
            }
        } label: {
            PhotoView(store.thumbnail(of: item).map { PhotoRequest($0) }) { _ in Theme.surface2 }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isCover ? Theme.accent : .clear, lineWidth: 3)
                }
                // Color.clear takes no touches on its own; the whole square is the button.
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Photo \(index + 1)",
            isPresented: Binding(get: { choosing == item.id }, set: { if !$0 { choosing = nil } }),
            titleVisibility: .hidden
        ) {
            Button("Make cover") { items = MealPhotoOrder.makeCover(index, in: items) }
            if canReframe {
                Button("Reframe") { reframe(item, at: index) }
            }
        }
        .overlay(alignment: .bottom) {
            if isCover {
                // A label, not reading text: the tile already says "the cover" to VoiceOver,
                // so it stays small enough to fit under the photo at any text size.
                Text("COVER")
                    .font(.body(isCompact ? 10.5 : 9.5, weight: 800))
                    .fixedSize()
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent, in: Capsule())
                    .offset(y: 8)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { items = MealPhotoOrder.remove(index, from: items) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                    // Paper on ink, so it reads in the night look too, where ink is light.
                    .foregroundStyle(Theme.surface)
                    .frame(width: 22, height: 22)
                    .background(Theme.ink, in: Circle())
                    .overlay(Circle().stroke(badgeRing, lineWidth: 2))
                    // The badge is small; the place to tap is bigger, but mostly off the
                    // photo, so a tap on the photo still opens its menu.
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 15, y: -15)
            .accessibilityLabel("Remove photo \(index + 1)")
        }
        #if DEBUG
        // Which photo this is and whether it was framed, for UI tests; not in a release.
        .background {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("photo-\(item.id)-\(item.crop == nil ? "centered" : "framed")")
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isCover ? "Photo \(index + 1), the cover" : "Photo \(index + 1)")
        .accessibilityHint(isCover ? "Reframe it" : "Make it the cover or reframe it")
        .accessibilityIdentifier("meal-photo-\(index)")
    }
}

// MARK: - Reframing

/// Picks which square of a photo the wall shows: drag the photo in a square window, and
/// pinch (or use the zoom row) to zoom in. Done makes a thumbnail for the new square and
/// hands both back; nothing is saved until the meal is. Over the wall it is a sheet of its
/// own; in a compact width it fills a phone sheet, its window as wide as the screen.
struct ReframeSheet: View {
    let item: MealPhotoItem
    let onDone: (PhotoCrop, Data) -> Void
    let onCancel: () -> Void

    @Environment(FoodStore.self) private var store
    @Environment(PhotoImages.self) private var images
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var image: UIImage?
    @State private var zoom = 1.0
    @State private var center = CGPoint(x: 0.5, y: 0.5)
    @State private var dragStart: CGPoint?
    @State private var pinchStart: Double?
    @State private var isSaving = false
    @State private var error: String?
    /// The phone's window: the sheet's width, less its margins.
    @State private var compactSide: CGFloat = 320

    private static let side: CGFloat = 400
    static let maxZoom = 4.0

    var body: some View {
        let size = image.map(Self.pixelSize) ?? CGSize(width: 1, height: 1)
        if sizeClass == .compact {
            compact(size: size)
        } else {
            WallSheet(width: Self.side + 52, onClose: onCancel) {
                VStack(alignment: .leading, spacing: 14) {
                    title
                    window(image, size: size, side: Self.side)
                    zoomRow(size: size)
                    errorLine
                    HStack(spacing: 10) {
                        Spacer()
                        Button("Cancel", action: onCancel)
                            .buttonStyle(SecondaryButtonStyle())
                        doneButton
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            .task { await load() }
        }
    }

    /// The phone's layout: everything in one column that scrolls at large text sizes.
    private func compact(size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                title
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: 0)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { compactSide = min($0, 520) }
                window(image, size: size, side: compactSide)
                zoomRow(size: size)
                errorLine
                doneButton
                    .buttonStyle(PhoneButtonStyle())
                Button("Cancel", action: onCancel)
                    .buttonStyle(PhoneButtonStyle(kind: .ghost))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Dragging the photo must not drag the sheet away.
        .interactiveDismissDisabled()
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .task { await load() }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reframe")
                .sharedFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                .accessibilityAddTraits(.isHeader)
            Text("Drag the photo, and pinch to zoom, to choose what the polaroid shows.")
                .sharedFont(.body, 14, weight: 600, relativeTo: .subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if let error {
            Text(error)
                .sharedFont(.body, 13, weight: 600, relativeTo: .footnote)
                .foregroundStyle(Theme.accent)
        }
    }

    private var doneButton: some View {
        Button("Done") { Task { await save(image) } }
            .disabled(isSaving || image == nil)
            .accessibilityIdentifier("reframe-done")
    }

    /// Decodes the whole shot, then starts from the square the photo shows now.
    private func load() async {
        guard image == nil, let source = store.image(of: item), let loaded = await images.image(PhotoRequest(source)) else { return }
        let size = Self.pixelSize(loaded)
        let crop = item.crop ?? .centeredSquare(in: size)
        zoom = min(max(crop.zoom(in: size), 1), Self.maxZoom)
        center = crop.center
        image = loaded
    }

    private func crop(in size: CGSize) -> PhotoCrop {
        .square(in: size, zoom: zoom, center: center)
    }

    private func window(_ image: UIImage?, size: CGSize, side: CGFloat) -> some View {
        let crop = crop(in: size)
        // Points per photo pixel, so the crop's square fills the window.
        let scale = side / max(crop.width * size.width, 1)
        return ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: size.width * scale, height: size.height * scale)
                    .offset(x: -crop.x * size.width * scale, y: -crop.y * size.height * scale)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .background(Theme.surface2)
        .clipped()
        .overlay { ThirdsGrid() }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStart ?? center
                    dragStart = start
                    let moved = CGPoint(
                        x: start.x - value.translation.width / (size.width * scale),
                        y: start.y - value.translation.height / (size.height * scale)
                    )
                    // Keep the center where the square can actually be, so a drag past an
                    // edge doesn't have to be undone before the square moves back.
                    center = PhotoCrop.square(in: size, zoom: zoom, center: moved).center
                }
                .onEnded { _ in dragStart = nil }
                .simultaneously(with:
                    MagnifyGesture()
                        .onChanged { value in
                            let start = pinchStart ?? zoom
                            pinchStart = start
                            setZoom(start * value.magnification, size: size)
                        }
                        .onEnded { _ in pinchStart = nil }
                )
        )
        .accessibilityElement()
        .accessibilityLabel("Photo framing")
        .accessibilityValue("\(Int((crop.center.x * 100).rounded())) percent across, \(Int((crop.center.y * 100).rounded())) percent down, zoom \(String(format: "%.1f", zoom))")
        .accessibilityIdentifier("reframe-window")
        .accessibilityAdjustableAction { change in
            // Slides along the photo's long side, like the old drag.
            let step = 0.1
            let landscape = size.width >= size.height
            let delta = change == .increment ? step : -step
            let moved = landscape ? CGPoint(x: center.x + delta, y: center.y) : CGPoint(x: center.x, y: center.y + delta)
            center = PhotoCrop.square(in: size, zoom: zoom, center: moved).center
        }
    }

    /// − zoom slider +, for one finger, a mouse or VoiceOver.
    private func zoomRow(size: CGSize) -> some View {
        let button: CGFloat = sizeClass == .compact ? 44 : 40
        return HStack(spacing: 12) {
            Button { setZoom(zoom / 1.25, size: size) } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: button, height: button)
                    .background(Theme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(zoom <= 1.001)
            .accessibilityLabel("Zoom out")
            Slider(value: Binding(get: { zoom }, set: { setZoom($0, size: size) }), in: 1...Self.maxZoom)
                .tint(Theme.accent)
                .accessibilityLabel("Zoom")
                .accessibilityValue(String(format: "%.1f times", zoom))
                .accessibilityIdentifier("reframe-zoom")
            Button { setZoom(zoom * 1.25, size: size) } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: button, height: button)
                    .background(Theme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(zoom >= Self.maxZoom - 0.001)
            .accessibilityLabel("Zoom in")
        }
        .foregroundStyle(Theme.ink)
    }

    private func setZoom(_ value: Double, size: CGSize) {
        zoom = min(max(value, 1), Self.maxZoom)
        center = PhotoCrop.square(in: size, zoom: zoom, center: center).center
    }

    private static func pixelSize(_ image: UIImage) -> CGSize {
        image.cgImage.map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    private func save(_ image: UIImage?) async {
        guard let image, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let crop = crop(in: Self.pixelSize(image))
        do {
            guard let source = store.image(of: item), let data = await images.bytes(of: source) else { throw FoodError.photoUnreadable }
            onDone(crop, try await store.thumbnail(ofImage: data, crop: crop))
        } catch {
            self.error = error.userMessage
        }
    }
}

/// Rule-of-thirds lines, as on a camera.
private struct ThirdsGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for third in [1.0 / 3, 2.0 / 3] {
                    path.move(to: CGPoint(x: proxy.size.width * third, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width * third, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: proxy.size.height * third))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * third))
                }
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Adding photos

/// Makes new images into photos off the main actor, up to the room a meal has left, and
/// hands each over as it is ready. The wall's and the phone's editors add photos this way;
/// they attach when the meal is saved.
@MainActor
enum MealPhotoAdding {
    static func add(
        _ images: [UIImage], room: Int, store: FoodStore,
        saving: @escaping (Int) -> Void, append: @escaping (MealPhotoItem) -> Void
    ) {
        for image in images.prefix(max(room, 0)) {
            saving(1)
            Task {
                defer { saving(-1) }
                if let photo = try? await store.preparePhoto(image) {
                    append(.added(photo))
                }
            }
        }
    }
}

/// The dashed + square of the photo row, for a tile that adds photos its own way.
struct AddPhotoTileLabel: View {
    var size: CGFloat = 60

    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .body) private var growth: CGFloat = 1

    var body: some View {
        let side = sizeClass == .compact ? size * min(max(growth, 1), 1.5) : size
        Image(systemName: "plus")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.muted)
            .frame(width: side, height: side)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.muted.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .contentShape(Rectangle())
    }
}

/// A dashed + tile that adds photos from the camera or from Photos. Over the wall, without
/// a camera it opens Photos directly; on a phone the camera step says what to do when the
/// camera is off. New images go to `onAdd`; nothing is attached here.
struct AddPhotoTile: View {
    /// How many more the meal can take.
    let remaining: Int
    var size: CGFloat = 60
    let onAdd: ([UIImage]) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showsCamera = false
    @State private var showsPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Photos added from the camera sheet while it was open.
    @State private var shotsThisTime = 0

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        Group {
            if MealCamera.hasCamera || isCompact {
                Menu {
                    Button { showCamera() } label: { Label("Take a photo", systemImage: "camera") }
                    Button { showsPicker = true } label: { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                } label: { AddPhotoTileLabel(size: size) }
            } else {
                Button { showsPicker = true } label: { AddPhotoTileLabel(size: size) }
                    .buttonStyle(.plain)
            }
        }
        .disabled(remaining == 0)
        .opacity(remaining == 0 ? 0.4 : 1)
        .accessibilityLabel("Add photo")
        .accessibilityIdentifier("add-photo-tile")
        .photosPicker(isPresented: $showsPicker, selection: $pickerItems, maxSelectionCount: max(remaining, 1), selectionBehavior: .ordered, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let images = await PhotoPicking.load(items)
                pickerItems = []
                if !images.isEmpty { onAdd(images) }
            }
        }
        .wallCover(item: Binding(get: { showsCamera && !isCompact ? CameraRequest() : nil }, set: { if $0 == nil { showsCamera = false } })) { _ in
            MealCameraSheet(photoCount: AppDatabase.photoLimit - remaining + shotsThisTime) { image in
                shotsThisTime += 1
                onAdd([image])
            } onDone: {
                CompanionCover.instantly { showsCamera = false }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { showsCamera && isCompact }, set: { if !$0 { showsCamera = false } })) {
            // The phone's own camera step, as when snapping a meal.
            PocketCameraStep(
                title: "Add photos", caption: "", remaining: remaining,
                onImages: { images in
                    onAdd(images)
                    showsCamera = false
                },
                onClose: { showsCamera = false }
            )
            .background(Theme.background.ignoresSafeArea())
        }
    }

    private struct CameraRequest: Identifiable {
        var id: Int { 0 }
    }

    private func showCamera() {
        shotsThisTime = 0
        if isCompact { showsCamera = true } else { CompanionCover.instantly { showsCamera = true } }
    }
}

/// The camera on its own, for adding photos to a meal that is already saved. Each shot
/// goes to `onShot` right away; Done closes it.
struct MealCameraSheet: View {
    let photoCount: Int
    let onShot: (UIImage) -> Void
    let onDone: () -> Void

    var body: some View {
        WallSheet(width: 460, onClose: onDone) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add photos")
                    .font(.display(28))
                MealViewfinder(emoji: DishIllustration.fallbackEmoji, photoCount: photoCount, onShot: onShot, onPick: { $0.forEach(onShot) })
                HStack {
                    Text(photoCount == 0 ? "Each photo is added as you take it." : "\(photoCount) of \(AppDatabase.photoLimit) photos")
                        .font(.body(13.5, weight: 600))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Done", action: onDone)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }
}
