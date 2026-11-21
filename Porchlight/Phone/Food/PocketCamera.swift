import PhotosUI
import SwiftUI
import UIKit

/// The phone's camera for meals: a polaroid whose photo is the live camera, captioned
/// with the meal it is for, a shutter under it, and Photos as the other way in.
///
/// It says what the camera is for before iOS asks, and with access turned off it says how
/// to turn it back on; Photos (and saving without a photo) work either way. Each shot or
/// pick goes to `onImages`; nothing is stored here.
struct PocketCameraStep: View {
    var small: String?
    let title: String
    /// The polaroid's caption: "Sunday dinner".
    let caption: String
    /// How many more photos the meal can take.
    let remaining: Int
    /// "Back" when it was opened from a meal's details, else "Close".
    var closeLabel = "Close"
    let onImages: ([UIImage]) -> Void
    /// Saves without a photo; nil where a photo is the point (adding one to a meal).
    var onNoPhoto: (() -> Void)?
    let onClose: () -> Void

    @Environment(\.scenePhase) private var phase
    @State private var access: CameraAccess?
    @State private var isAsking = false
    @State private var camera = MealCamera()
    @State private var isLive = false
    @State private var deviceID: String?
    @State private var captureAngle: CGFloat = 0
    @State private var flash = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isTaking = false
    /// Sample shots taken, so each looks a little different.
    @State private var shots = 0
    @PhoneMetric private var shutter: CGFloat = 72

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: closeLabel == "Back" ? "chevron.left" : "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                            .background(Theme.surface2, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(closeLabel)
                    .accessibilityIdentifier("close-camera")
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 0) {
                    if let small {
                        Text(small)
                            .phoneFont(.body, 12.5, weight: 700, relativeTo: .footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    Text(title)
                        .phoneFont(.display, 28, weight: 600, relativeTo: .largeTitle)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                polaroid
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        // A full-screen cover stands outside the tabs: keep scrolled text out from
        // under the clock, as the welcome screens do.
        .clipped()
        .background(Theme.background)
        .paperUnderStatusBar()
        .task(id: phase) {
            // Coming back from Settings may have changed the answer.
            if phase == .active { access = CameraAccess.current() }
        }
        .task(id: access) { await startIfAllowed() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let images = await PhotoPicking.load(items)
                pickerItems = []
                if !images.isEmpty { onImages(images) }
            }
        }
    }

    // MARK: The polaroid

    private var polaroid: some View {
        VStack(spacing: 0) {
            window
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            Text(handwritten: caption, centered: true)
                .phoneFont(.hand, 22, weight: 700, relativeTo: .title3)
                .foregroundStyle(FoodStyle.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .padding([.top, .horizontal], 10)
        .padding(.bottom, 4)
        .background(FoodStyle.polaroidPaper, in: RoundedRectangle(cornerRadius: 3))
        .shadow(color: FoodStyle.shadow.opacity(0.12), radius: 1, y: 1)
        .shadow(color: FoodStyle.shadow.opacity(0.22), radius: 10, y: 8)
        .rotationEffect(.degrees(-1))
        .frame(maxWidth: 300)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(windowLabel)
        .accessibilityIdentifier("viewfinder")
    }

    @ViewBuilder
    private var window: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x6A5341), Color(hex: 0x2A201A)], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 260)
            switch access {
            case .allowed?:
                #if DEBUG
                if SampleCamera.isOn {
                    Color.clear.overlay {
                        Image(uiImage: SampleCamera.shot(shots)).resizable().scaledToFill()
                    }
                    .clipped()
                }
                #endif
                if isLive {
                    CameraPreview(camera: camera, deviceID: deviceID) { captureAngle = $0 }
                }
            case .notDetermined?: symbol("camera")
            case .denied?: symbol("camera.slash")
            case .noCamera?: symbol("photo.on.rectangle")
            case nil: EmptyView()
            }
            Color.white.opacity(flash ? 0.95 : 0).allowsHitTesting(false)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 54, weight: .light))
            .foregroundStyle(.white.opacity(0.8))
    }

    private var windowLabel: String {
        switch access {
        case .allowed?: "Camera, framing the photo as the polaroid shows it"
        default: "Camera off"
        }
    }

    // MARK: Below the polaroid

    @ViewBuilder
    private var controls: some View {
        switch access {
        case .allowed?:
            VStack(spacing: 14) {
                shutterButton
                if remaining == 0 {
                    note("That's \(AppDatabase.photoLimit) photos, the most a meal can have.")
                }
                otherWays
            }
        case .notDetermined?:
            explanation(
                "Snap meals with the camera?",
                "Porchlight uses it only while this screen is open, and each photo goes to your household's food diary.",
                button: Button("Allow camera") { ask() }
                    .buttonStyle(PhoneButtonStyle())
                    .disabled(isAsking)
                    .accessibilityIdentifier("allow-camera")
            )
        case .denied?:
            explanation(
                "Camera access is off",
                "In Settings, open Porchlight and turn on Camera. You can still pick from Photos.",
                button: Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(PhoneButtonStyle(kind: .ghost))
                .accessibilityIdentifier("open-settings")
            )
        case .noCamera?:
            VStack(spacing: 12) {
                note("There's no camera here. Pick from Photos instead.")
                otherWays
            }
        case nil:
            EmptyView()
        }
    }

    private func explanation(_ heading: String, _ body: String, button: some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .phoneFont(.display, 20, weight: 600, relativeTo: .title3)
            Text(body)
                .phoneFont(.body, 14, weight: 500)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            button
            otherWays
        }
        .phoneCard()
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .phoneFont(.body, 13.5, weight: 600, relativeTo: .footnote)
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var shutterButton: some View {
        Button(action: shoot) {
            Circle()
                .fill(Color.white)
                .frame(width: shutter, height: shutter)
                .overlay(Circle().strokeBorder(Theme.ink.opacity(0.12), lineWidth: 1))
                .padding(5)
                .background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isTaking || remaining == 0 || !canShoot)
        .opacity(remaining == 0 ? 0.4 : 1)
        .accessibilityLabel("Take photo")
        .accessibilityIdentifier("shutter")
    }

    /// "🖼️ From Photos" and "✍️ No photo".
    private var otherWays: some View {
        FlowLayout(spacing: 8, lineSpacing: 4) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: max(remaining, 1), selectionBehavior: .ordered, matching: .images) {
                WayPill(title: "🖼️ From Photos")
            }
            .disabled(remaining == 0)
            .accessibilityIdentifier("from-photos")
            if let onNoPhoto {
                Button(action: onNoPhoto) { WayPill(title: "✍️ No photo") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("no-photo")
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// One of the other ways in, under the shutter.
    private struct WayPill: View {
        let title: String

        var body: some View {
            Text(title)
                .phoneFont(.body, 13.5, weight: 700, relativeTo: .subheadline)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    // MARK: Camera

    private var canShoot: Bool {
        #if DEBUG
        if SampleCamera.isOn { return true }
        #endif
        return isLive
    }

    private func ask() {
        isAsking = true
        Task {
            access = await CameraAccess.request()
            isAsking = false
        }
    }

    private func startIfAllowed() async {
        guard access == .allowed, !isLive, MealCamera.hasCamera else { return }
        #if DEBUG
        if SampleCamera.isOn { return }
        #endif
        do {
            // The phone points at the plate, not at whoever holds it.
            try await camera.start(position: .back)
            deviceID = camera.device?.uniqueID
            isLive = true
        } catch {
            access = .noCamera
        }
    }

    private func shoot() {
        withAnimation(.easeOut(duration: 0.05)) { flash = true }
        withAnimation(.easeOut(duration: 0.45).delay(0.05)) { flash = false }
        #if DEBUG
        if SampleCamera.isOn {
            let image = SampleCamera.shot(shots)
            shots += 1
            onImages([image])
            return
        }
        #endif
        isTaking = true
        let angle = captureAngle
        Task {
            defer { isTaking = false }
            if let image = try? await camera.capture(rotationAngle: angle) {
                onImages([image])
            }
        }
    }
}
