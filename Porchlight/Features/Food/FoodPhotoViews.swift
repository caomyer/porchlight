import AVFoundation
import PhotosUI
import SwiftUI

// Taking, picking and arranging a meal's photos. Shared by the capture sheet, the meal
// detail and its edit form. A meal has up to `AppDatabase.photoLimit` photos; the first
// is the cover, shown wherever many meals appear at once.

// MARK: - Viewfinder

/// The live camera with a shutter, a Photos button and a camera switch. The shutter only
/// takes a photo: it goes to `onShot` and the camera stays live for another angle.
/// Without a camera it shows the dish's emoji on a plate and offers Photos.
struct MealViewfinder: View {
    /// Shown on the plate when there is no camera.
    let emoji: String
    /// Photos the meal already has, to say when it's full.
    let photoCount: Int
    var isBusy = false
    let onShot: (UIImage) -> Void
    let onPick: ([UIImage]) -> Void

    @State private var camera = MealCamera()
    @State private var state: CameraState = .starting
    @State private var deviceID: String?
    @State private var captureAngle: CGFloat = 0
    @State private var flash = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @AppStorage("food.cameraFront") private var useFront = true

    enum CameraState { case starting, live, denied, none }

    private var remaining: Int { max(AppDatabase.photoLimit - photoCount, 0) }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x6A5341), Color(hex: 0x2A201A)], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 330)
            content
            if state == .live { brackets }
            VStack {
                Text(hint)
                    .font(.body(13, weight: 600))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("viewfinder-hint")
                Spacer()
                bottomControls
                    .padding(.bottom, 24)
            }
            Color.white.opacity(flash ? 0.95 : 0).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            .frame(width: 250, height: 250)
            .shadow(color: .black.opacity(0.45), radius: 20, y: 24)
            .offset(y: -20)
            .animation(.spring(duration: 0.3), value: emoji)
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
        if remaining == 0 { return "That's \(AppDatabase.photoLimit) photos, the most a meal can have" }
        switch state {
        case .live: return photoCount > 0 ? "Added to Photos · another angle?" : "Center the plate · tap the shutter"
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
            .padding(.horizontal, 28)
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

/// The top-left corner of a viewfinder bracket; rotated for the other corners.
struct Bracket: Shape {
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

/// A meal's photos as small squares, cover first. Tap one to make it the cover, × to
/// remove it. `trailing` goes after the photos, e.g. a tile to add more.
struct MealPhotoRow<Trailing: View>: View {
    @Binding var items: [MealPhotoItem]
    /// Photos still being saved, shown as placeholders.
    var pending = 0
    var size: CGFloat = 60
    var emptyText: String
    @ViewBuilder var trailing: () -> Trailing

    @Environment(FoodStore.self) private var store

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
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if items.count > 1 {
                Text("Tap a photo to make it the cover")
                    .font(.body(12.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: items)
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
        return Button {
            makeCover(index)
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
        }
        .buttonStyle(.plain)
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
                    .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: -7)
            .accessibilityLabel("Remove photo \(index + 1)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isCover ? "Photo \(index + 1), the cover" : "Photo \(index + 1)")
        .accessibilityHint(isCover ? "" : "Makes it the cover")
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
                    .frame(height: 520)
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
