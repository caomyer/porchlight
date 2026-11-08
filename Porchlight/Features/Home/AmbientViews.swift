import SwiftUI
import UIKit

/// Full-screen photo frame shown when the wall is idle, or from the rail.
///
/// Photos come from Settings imports plus `extraPhotoURLs` (meal photos from other features).
/// Without photos it paints a generated landscape. At night it dims to a minimal clock.
/// `glance` is an optional row of glass cards (next event, companion status) shown bottom-right.
struct AmbientView: View {
    var extraPhotoURLs: [URL]
    var onWake: () -> Void
    var glance: AnyView? = nil

    @Environment(HomeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AmbientSettings.nightEnabledKey) private var nightEnabled = true
    @AppStorage(AmbientSettings.nightStartKey) private var nightStart = NightWindow.default.start
    @AppStorage(AmbientSettings.nightEndKey) private var nightEnd = NightWindow.default.end
    @State private var caption: String?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let isNight = isNight(at: context.date)
            ZStack {
                if isNight {
                    NightClock(date: context.date)
                        .transition(.opacity)
                } else {
                    day(date: context.date)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 1.5), value: isNight)
            .onChange(of: isNight, initial: true) { _, night in applyBrightness(night: night) }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onWake)
        .statusBarHidden(true)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { NightBrightness.restore() }
        }
        .onDisappear { NightBrightness.restore() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ambient")
        .accessibilityAction(named: "Wake", onWake)
    }

    private var photos: [URL] { store.photoURLs + extraPhotoURLs }

    private var captions: [URL: String] {
        Dictionary(
            store.snapshot.photos.compactMap { photo in photo.caption.map { (store.photoLibrary.url(for: photo.fileName), "📷 " + $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func isNight(at date: Date) -> Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ambientNight") { return true }
        #endif
        return nightEnabled && NightWindow(start: nightStart, end: nightEnd).contains(date, calendar: store.calendar)
    }

    private func applyBrightness(night: Bool) {
        if night && scenePhase == .active { NightBrightness.dim() } else { NightBrightness.restore() }
    }

    private func day(date: Date) -> some View {
        ZStack(alignment: .bottomLeading) {
            if photos.isEmpty {
                GeneratedLandscapes()
            } else {
                PhotoSlideshow(urls: photos, captions: captions, caption: $caption)
            }
            LinearGradient(
                stops: [.init(color: .black.opacity(0.6), location: 0), .init(color: .black.opacity(0), location: 0.55)],
                startPoint: .bottom,
                endPoint: .top
            )
            .allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 24) {
                // Fraunces carries tall line spacing at this size; pull the date up like the mock.
                VStack(alignment: .leading, spacing: -6) {
                    Clock(date: date, size: 120)
                        .tracking(-2)
                    Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.body(20, weight: 600))
                        .opacity(0.9)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 2)
                Spacer(minLength: 0)
                glance
            }
            .padding(.horizontal, 44)
            .padding(.bottom, 38)
            .foregroundStyle(.white)
        }
        .overlay(alignment: .topTrailing) {
            if let caption, !photos.isEmpty {
                Text(caption)
                    .font(.body(13, weight: 600))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
                    .background(Color.black.opacity(0.22), in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .padding(.top, 24)
                    .padding(.trailing, 28)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1), value: caption)
    }
}

/// A frosted card for the ambient overlay, matching the "Next up" cards in the mock.
/// Other features can use it to build `AmbientView(glance:)`.
struct AmbientGlassCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minWidth: 230, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(Color(hex: 0x14_141C).opacity(0.35), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14)))
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Night

/// A dim clock on near-black for the night hours.
private struct NightClock: View {
    let date: Date

    var body: some View {
        VStack(spacing: 10) {
            Clock(date: date, size: 150)
                .tracking(-2)
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.body(18, weight: 600))
                .opacity(0.6)
        }
        .foregroundStyle(Color(hex: 0x8A7F74).opacity(0.55))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x0A_0908))
    }
}

/// Lowers the screen for the night hours and puts it back after.
@MainActor
enum NightBrightness {
    static let nightLevel: CGFloat = 0.08
    private static var saved: CGFloat?

    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    static func dim() {
        guard saved == nil, let screen else { return }
        saved = screen.brightness
        screen.brightness = min(screen.brightness, nightLevel)
    }

    static func restore() {
        guard let level = saved, let screen else { return }
        screen.brightness = level
        saved = nil
    }
}

// MARK: - Photos

/// Crossfades through photos every ~20 seconds, each with a slow Ken Burns pan.
private struct PhotoSlideshow: View {
    let urls: [URL]
    let captions: [URL: String]
    @Binding var caption: String?

    private struct Slide: Equatable {
        var number: Int
        var image: UIImage
    }

    @State private var slide: Slide?

    var body: some View {
        ZStack {
            Color.black
            if let slide {
                KenBurns(seed: slide.number) {
                    Image(uiImage: slide.image)
                        .resizable()
                        .scaledToFill()
                }
                .id(slide.number)
                .transition(.opacity)
            }
        }
        .clipped()
        .task(id: urls) { await run() }
    }

    private func run() async {
        guard !urls.isEmpty else { return }
        // A bit over the iPad Pro 10.5" panel (2224 px) leaves room for the Ken Burns zoom.
        let maxPixels = 2560
        var number = (slide?.number ?? Int.random(in: 0..<urls.count)) + (slide == nil ? 0 : 1)
        var failures = 0
        while !Task.isCancelled {
            let url = urls[number % urls.count]
            if let image = await AmbientPhotoLibrary.loadForDisplay(url, maxPixelSize: maxPixels) {
                failures = 0
                withAnimation(.easeInOut(duration: 2.5)) {
                    slide = Slide(number: number, image: image)
                    caption = captions[url]
                }
                try? await Task.sleep(for: .seconds(AmbientSettings.slideSeconds))
            } else {
                // Skip unreadable files; stop spinning if none can be read.
                failures += 1
                if failures >= urls.count { return }
            }
            number += 1
        }
    }
}

/// Slowly zooms out and drifts its content, a different way for each seed.
private struct KenBurns<Content: View>: View {
    let seed: Int
    @ViewBuilder var content: () -> Content
    @State private var settled = false

    private static var drifts: [CGSize] {
        [CGSize(width: -24, height: -12), CGSize(width: 22, height: -14), CGSize(width: -18, height: 14), CGSize(width: 20, height: 10)]
    }

    var body: some View {
        let drift = Self.drifts[abs(seed) % Self.drifts.count]
        GeometryReader { proxy in
            content()
                .frame(width: proxy.size.width, height: proxy.size.height)
                // Never zoom out so far that the drift uncovers an edge: (scale - 1) / 2 of each side
                // must stay larger than the drift (24 pt on a 1112 pt wide, 834 pt tall screen).
                .scaleEffect(settled ? 1.06 : 1.12)
                .offset(settled ? drift : CGSize(width: -drift.width, height: -drift.height))
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: AmbientSettings.slideSeconds + 6)) { settled = true }
        }
    }
}

// MARK: - Generated landscape

/// Painted hills under a soft sky, used when there are no photos. Cycles through a few skies.
private struct GeneratedLandscapes: View {
    @State private var index = 0

    var body: some View {
        ZStack {
            KenBurns(seed: index) {
                LandscapePainting(palette: LandscapePalette.all[index % LandscapePalette.all.count])
            }
            .id(index)
            .transition(.opacity)
        }
        .clipped()
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AmbientSettings.slideSeconds * 2))
                withAnimation(.easeInOut(duration: 4)) { index += 1 }
            }
        }
    }
}

struct LandscapePalette {
    var sky: [Gradient.Stop]
    var sun: Color
    var haze: Color
    var ground: Color
    var farHills: Color
    var nearHills: Color

    static let dusk = LandscapePalette(
        sky: [.init(color: Color(hex: 0xE9A46B), location: 0), .init(color: Color(hex: 0x7A5A7D), location: 0.55), .init(color: Color(hex: 0x24304A), location: 1)],
        sun: Color(red: 1, green: 206 / 255, blue: 140 / 255).opacity(0.85),
        haze: Color(red: 80 / 255, green: 120 / 255, blue: 170 / 255).opacity(0.9),
        ground: Color(red: 40 / 255, green: 60 / 255, blue: 50 / 255).opacity(0.95),
        farHills: Color(hex: 0x3B4B5E).opacity(0.75),
        nearHills: Color(hex: 0x2A3442)
    )

    static let morning = LandscapePalette(
        sky: [.init(color: Color(hex: 0xF2CDA4), location: 0), .init(color: Color(hex: 0x9FB3C8), location: 0.55), .init(color: Color(hex: 0x4D6A86), location: 1)],
        sun: Color(red: 1, green: 238 / 255, blue: 196 / 255).opacity(0.9),
        haze: Color(red: 120 / 255, green: 160 / 255, blue: 200 / 255).opacity(0.75),
        ground: Color(red: 52 / 255, green: 84 / 255, blue: 72 / 255).opacity(0.9),
        farHills: Color(hex: 0x5D768A).opacity(0.75),
        nearHills: Color(hex: 0x3B5163)
    )

    static let twilight = LandscapePalette(
        sky: [.init(color: Color(hex: 0xD18E98), location: 0), .init(color: Color(hex: 0x5C4D7C), location: 0.55), .init(color: Color(hex: 0x1C2240), location: 1)],
        sun: Color(red: 1, green: 192 / 255, blue: 168 / 255).opacity(0.7),
        haze: Color(red: 72 / 255, green: 92 / 255, blue: 164 / 255).opacity(0.85),
        ground: Color(red: 30 / 255, green: 40 / 255, blue: 52 / 255).opacity(0.95),
        farHills: Color(hex: 0x353F5C).opacity(0.8),
        nearHills: Color(hex: 0x222A3E)
    )

    static let all = [dusk, morning, twilight]
}

/// The mock's sky: a vertical gradient with three soft elliptical glows, and two hill silhouettes.
struct LandscapePainting: View {
    let palette: LandscapePalette

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(Gradient(stops: palette.sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            glow(&context, size: size, center: CGPoint(x: 0.7, y: 0.3), radii: CGSize(width: 0.6, height: 0.5), color: palette.sun, fade: 0.6)
            glow(&context, size: size, center: CGPoint(x: 0.2, y: 0.8), radii: CGSize(width: 0.5, height: 0.6), color: palette.haze, fade: 0.7)
            glow(&context, size: size, center: CGPoint(x: 0.5, y: 1.0), radii: CGSize(width: 0.7, height: 0.4), color: palette.ground, fade: 0.7)
            // Hills drawn in a 1112 x 380 box across the bottom 46%, as in the mock's SVG.
            let hillHeight = size.height * 0.46
            var transform = CGAffineTransform(translationX: 0, y: size.height - hillHeight)
                .scaledBy(x: size.width / 1112, y: hillHeight / 380)
            if let far = Self.farHills.copy(using: &transform) {
                context.fill(Path(far), with: .color(palette.farHills))
            }
            if let near = Self.nearHills.copy(using: &transform) {
                context.fill(Path(near), with: .color(palette.nearHills))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ context: inout GraphicsContext, size: CGSize, center: CGPoint, radii: CGSize, color: Color, fade: CGFloat) {
        var layer = context
        layer.translateBy(x: size.width * center.x, y: size.height * center.y)
        layer.scaleBy(x: size.width * radii.width, y: size.height * radii.height)
        let gradient = Gradient(stops: [
            .init(color: color, location: 0),
            .init(color: color.opacity(0), location: fade),
        ])
        layer.fill(Path(CGRect(x: -4, y: -4, width: 8, height: 8)), with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1))
    }

    /// `M0 220 C200 120 380 180 540 140 S860 80 1112 170 V380 H0z`
    private static var farHills: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 220))
        path.addCurve(to: CGPoint(x: 540, y: 140), control1: CGPoint(x: 200, y: 120), control2: CGPoint(x: 380, y: 180))
        // S reflects the previous control point (380,180) about (540,140).
        path.addCurve(to: CGPoint(x: 1112, y: 170), control1: CGPoint(x: 700, y: 100), control2: CGPoint(x: 860, y: 80))
        path.addLine(to: CGPoint(x: 1112, y: 380))
        path.addLine(to: CGPoint(x: 0, y: 380))
        path.closeSubpath()
        return path
    }

    /// `M0 290 C240 220 420 270 620 230 S960 200 1112 260 V380 H0z`
    private static var nearHills: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 290))
        path.addCurve(to: CGPoint(x: 620, y: 230), control1: CGPoint(x: 240, y: 220), control2: CGPoint(x: 420, y: 270))
        path.addCurve(to: CGPoint(x: 1112, y: 260), control1: CGPoint(x: 820, y: 190), control2: CGPoint(x: 960, y: 200))
        path.addLine(to: CGPoint(x: 1112, y: 380))
        path.addLine(to: CGPoint(x: 0, y: 380))
        path.closeSubpath()
        return path
    }
}
