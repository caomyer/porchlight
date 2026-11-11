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

/// A meal's photos as small squares, cover first. Tap one to make it the cover or to
/// reframe it, × to remove it. `trailing` goes after the photos, e.g. a tile to add more.
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
    @State private var reframing: Reframing?

    private struct Reframing: Identifiable {
        let index: Int
        let item: MealPhotoItem
        var id: String { item.id }
    }

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
                    .font(.body(13.5, weight: 600))
                    .foregroundStyle(noteColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !items.isEmpty {
                Text(items.count > 1 ? "Tap a photo to make it the cover or reframe it" : "Tap the photo to reframe it")
                    .font(.body(12.5, weight: 600))
                    .foregroundStyle(noteColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: items)
        .wallCover(item: $reframing) { reframing in
            ReframeSheet(item: reframing.item) { crop, thumbnail in
                if items.indices.contains(reframing.index), items[reframing.index].photoFile == reframing.item.photoFile {
                    items[reframing.index] = items[reframing.index].reframed(crop, thumbnailFile: thumbnail)
                } else {
                    store.discard(files: [thumbnail])
                }
                CompanionCover.instantly { self.reframing = nil }
            } onCancel: {
                CompanionCover.instantly { self.reframing = nil }
            }
        }
    }

    private var tiles: some View {
        FlowLayout(spacing: 12, lineSpacing: 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                tile(item, index: index)
            }
            ForEach(0..<pending, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface2)
                    .frame(width: size, height: size)
                    .overlay { ProgressView() }
            }
            trailing()
        }
    }

    private func tile(_ item: MealPhotoItem, index: Int) -> some View {
        let isCover = index == 0
        return Menu {
            if !isCover {
                Button { makeCover(index) } label: { Label("Make cover", systemImage: "star") }
            }
            Button {
                CompanionCover.instantly { reframing = Reframing(index: index, item: item) }
            } label: { Label("Reframe", systemImage: "crop") }
        } label: {
            Color.clear
                .frame(width: size, height: size)
                .overlay {
                    if let image = MealImages.image(at: store.photoURL(item.thumbnailFile)) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Theme.surface2
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isCover ? Theme.accent : .clear, lineWidth: 3)
                }
                // Color.clear takes no touches on its own; the whole square opens the menu.
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .overlay(alignment: .bottom) {
            if isCover {
                Text("COVER")
                    .font(.body(9.5, weight: 800))
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
            Button { remove(index) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.ink, in: Circle())
                    .overlay(Circle().stroke(badgeRing, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: -7)
            .accessibilityLabel("Remove photo \(index + 1)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isCover ? "Photo \(index + 1), the cover" : "Photo \(index + 1)")
        .accessibilityHint(isCover ? "Reframe it" : "Make it the cover or reframe it")
        .accessibilityIdentifier("meal-photo-\(index)")
    }

    private func makeCover(_ index: Int) {
        guard index > 0, items.indices.contains(index) else { return }
        let item = items.remove(at: index)
        items.insert(item, at: 0)
    }

    private func remove(_ index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }
}

// MARK: - Reframing

/// Picks which square of a photo the wall shows: drag the photo along its long side in a
/// square window. Done writes a thumbnail for the new square and hands both back.
struct ReframeSheet: View {
    let item: MealPhotoItem
    let onDone: (PhotoCrop, String) -> Void
    let onCancel: () -> Void

    @Environment(FoodStore.self) private var store
    @State private var position = 0.5
    @State private var dragStart: Double?
    @State private var isSaving = false
    @State private var error: String?

    private static let side: CGFloat = 400

    var body: some View {
        let image = MealImages.image(at: store.photoURL(item.photoFile))
        WallSheet(width: Self.side + 52, onClose: onCancel) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Reframe")
                    .font(.display(28))
                Text("Drag the photo to choose what the polaroid shows.")
                    .font(.body(14, weight: 600))
                    .foregroundStyle(Theme.muted)
                window(image)
                if let error {
                    Text(error).font(.body(13, weight: 600)).foregroundStyle(Theme.accent)
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Done") { Task { await save(image) } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isSaving || image == nil)
                }
            }
        }
        .onAppear { position = item.crop?.position ?? 0.5 }
    }

    private func window(_ image: UIImage?) -> some View {
        let size = image.map(Self.pixelSize) ?? CGSize(width: 1, height: 1)
        let landscape = size.width >= size.height
        let long = Self.side * max(size.width, size.height) / max(min(size.width, size.height), 1)
        let travel = long - Self.side
        return ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: landscape ? long : Self.side, height: landscape ? Self.side : long)
                    .offset(x: landscape ? -travel * position : 0, y: landscape ? 0 : -travel * position)
            }
        }
        .frame(width: Self.side, height: Self.side, alignment: .topLeading)
        .clipped()
        .overlay { ThirdsGrid() }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard travel > 0 else { return }
                    let start = dragStart ?? position
                    dragStart = start
                    let moved = landscape ? value.translation.width : value.translation.height
                    position = min(max(start - Double(moved / travel), 0), 1)
                }
                .onEnded { _ in dragStart = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Photo framing")
        .accessibilityValue("\(Int((position * 100).rounded())) percent")
        .accessibilityIdentifier("reframe-window")
        .accessibilityAdjustableAction { change in
            switch change {
            case .increment: position = min(position + 0.1, 1)
            case .decrement: position = max(position - 0.1, 0)
            @unknown default: break
            }
        }
    }

    private static func pixelSize(_ image: UIImage) -> CGSize {
        image.cgImage.map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    private func save(_ image: UIImage?) async {
        guard let image, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let crop = PhotoCrop.square(in: Self.pixelSize(image), position: position)
        do {
            let thumbnail = try await store.thumbnail(of: item.photoFile, crop: crop)
            onDone(crop, thumbnail)
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

/// A dashed + tile that adds photos from the camera or from Photos. Without a camera it
/// opens Photos directly. New images go to `onAdd`; nothing is attached here.
struct AddPhotoTile: View {
    /// How many more the meal can take.
    let remaining: Int
    var size: CGFloat = 60
    let onAdd: ([UIImage]) -> Void

    @State private var showsCamera = false
    @State private var showsPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Photos added from the camera sheet while it was open.
    @State private var shotsThisTime = 0

    var body: some View {
        Group {
            if MealCamera.hasCamera {
                Menu {
                    Button { showCamera() } label: { Label("Take a photo", systemImage: "camera") }
                    Button { showsPicker = true } label: { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                } label: { tile }
            } else {
                Button { showsPicker = true } label: { tile }
                    .buttonStyle(.plain)
            }
        }
        .disabled(remaining == 0)
        .opacity(remaining == 0 ? 0.4 : 1)
        .accessibilityLabel("Add photo")
        .photosPicker(isPresented: $showsPicker, selection: $pickerItems, maxSelectionCount: max(remaining, 1), selectionBehavior: .ordered, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let images = await PhotoPicking.load(items)
                pickerItems = []
                if !images.isEmpty { onAdd(images) }
            }
        }
        .wallCover(item: Binding(get: { showsCamera ? CameraRequest() : nil }, set: { if $0 == nil { showsCamera = false } })) { _ in
            MealCameraSheet(photoCount: AppDatabase.photoLimit - remaining + shotsThisTime) { image in
                shotsThisTime += 1
                onAdd([image])
            } onDone: {
                CompanionCover.instantly { showsCamera = false }
            }
        }
    }

    private struct CameraRequest: Identifiable {
        var id: Int { 0 }
    }

    private func showCamera() {
        shotsThisTime = 0
        CompanionCover.instantly { showsCamera = true }
    }

    private var tile: some View {
        Image(systemName: "plus")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.muted)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.muted.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .contentShape(Rectangle())
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
