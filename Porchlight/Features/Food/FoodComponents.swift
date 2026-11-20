import SwiftUI
import UIKit

// Small building blocks shared by the food screens.

enum FoodStyle {
    static let polaroidPaper = Color(hex: 0xFFFEFA)
    static let caption = Color(hex: 0x3A332D)
    static let shadow = Color(hex: 0x3C2814)
    /// Small rotations so a grid of polaroids looks hand-placed.
    static let rotations: [Double] = [-2.5, 1.8, -1.2, 2.2, -1.8, 1.2, -2]
}

// MARK: - Illustration

/// A meal's picture: one of its photos (the cover unless `photoIndex` says otherwise),
/// or its emoji on a white plate over a tablecloth tint.
struct MealIllustration: View {
    let entry: JournalEntry
    /// Plate diameter as a fraction of the square's side.
    var plate: CGFloat = 0.5
    var emojiSize: CGFloat = 38
    /// Which photo to show; 0 is the cover.
    var photoIndex = 0

    @Environment(FoodStore.self) private var store
    @Environment(\.foodPreferFullPhoto) private var preferFullPhoto

    var body: some View {
        let photos = store.photos(of: entry)
        let photo = photos.isEmpty ? nil : photos[min(max(photoIndex, 0), photos.count - 1)]
        let tint = Color(hex: UInt32(entry.tint ?? 0xF5EFE4))
        PhotoView(photo.flatMap(request)) { isMissing in
            if isMissing {
                PlateArt(emoji: entry.emoji ?? DishIllustration.fallbackEmoji, tint: tint, plate: plate, emojiSize: emojiSize)
            } else if let photo, preferFullPhoto, let thumbnail = store.thumbnail(of: photo) {
                // The whole shot is still loading (or still arriving by sync): its square's
                // thumbnail, which is already small and decoded, stands in until it's here.
                PhotoView(PhotoRequest(thumbnail)) { _ in tint }
            } else {
                // Still loading: the tablecloth, so the plate never flashes up before the photo.
                tint
            }
        }
    }

    /// The square the wall shows: the thumbnail, or where one photo fills the view the
    /// whole shot's crop (the thumbnail is all a photo without its whole shot has).
    private func request(for photo: MealPhoto) -> PhotoRequest? {
        if preferFullPhoto, let image = store.image(of: photo) {
            return PhotoRequest(image, crop: photo.crop)
        }
        return store.thumbnail(of: photo).map { PhotoRequest($0) }
    }
}

/// An emoji on a plate over a colored tablecloth.
struct PlateArt: View {
    let emoji: String
    var tint: Color = Theme.background
    var plate: CGFloat = 0.5
    var emojiSize: CGFloat = 38

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                tint
                Circle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: side * (plate + 0.06), height: side * (plate + 0.06))
                Circle()
                    .fill(Color.white)
                    .frame(width: side * plate, height: side * plate)
                Text(emoji)
                    .font(.system(size: emojiSize))
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .offset(y: side * 0.01)
        }
    }
}

/// A rounded meal thumbnail for the Today timeline.
struct MealThumbnail: View {
    let entry: JournalEntry
    var size: CGFloat = 34

    var body: some View {
        MealIllustration(entry: entry, plate: 0.62, emojiSize: size * 0.5)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .shadow(color: FoodStyle.shadow.opacity(0.15), radius: 1.5, y: 1)
    }
}

// MARK: - Polaroids

/// A meal as a slightly rotated polaroid with a handwritten caption, who ate it, a 🛵 for
/// delivery or 🍽️ for eating out, and more polaroids peeking out behind when the slot has several.
struct Polaroid: View {
    let entry: JournalEntry
    var rotation: Double = 0
    var emojiSize: CGFloat = 38
    var captionSize: CGFloat = 16
    var plate: CGFloat = 0.51
    var badgeSize: CGFloat = 22
    /// How many more meals share this slot; they peek out behind.
    var extra = 0
    /// The corner badge; "+1" for `extra` by default, e.g. "2/3" in a swipeable stack.
    var badge: String?
    /// Which of the meal's photos to show; 0 is the cover.
    var photoIndex = 0
    /// Marks a meal with several photos with a small camera count. Off where the polaroid
    /// is a keepsake ("On this day") or pages through the photos itself.
    var showsPhotoCount = true

    @Environment(FoodStore.self) private var store

    var body: some View {
        let photoCount = store.photos(of: entry).count
        VStack(spacing: 0) {
            MealIllustration(entry: entry, plate: plate, emojiSize: emojiSize, photoIndex: photoIndex)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(alignment: .bottomLeading) {
                    if showsPhotoCount, photoCount > 1 {
                        PhotoCountChip(count: photoCount, size: captionSize * 0.62)
                            .padding(captionSize * 0.3)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Where it came from, when not (only) home-cooked: "🛵 · 🏢".
                    if entry.sources.kinds != [.home] {
                        Text(MealSources(entry.sources.kinds.filter { $0 != .home }).emoji)
                            .font(.system(size: 11))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.88), in: Capsule())
                            .padding(4)
                    }
                }
            Text(entry.title)
                .font(.hand(captionSize, weight: 700))
                .foregroundStyle(FoodStyle.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .frame(height: captionSize * 1.5)
        }
        .padding([.top, .horizontal], 6)
        .padding(.bottom, max(2, captionSize * 0.15))
        .background(FoodStyle.polaroidPaper, in: RoundedRectangle(cornerRadius: 3))
        .shadow(color: FoodStyle.shadow.opacity(0.12), radius: 1, y: 1)
        .shadow(color: FoodStyle.shadow.opacity(0.22), radius: 8, y: 6)
        .background {
            // The slot's other meals, as paper corners peeking out of the stack.
            ForEach(Array((0..<min(extra, 2)).reversed()), id: \.self) { layer in
                RoundedRectangle(cornerRadius: 3)
                    .fill(FoodStyle.polaroidPaper)
                    .shadow(color: FoodStyle.shadow.opacity(0.18), radius: 2, y: 1)
                    .rotationEffect(.degrees(layer == 0 ? 6 : -5))
                    .offset(x: layer == 0 ? 6 : -4, y: layer == 0 ? 3 : 5)
            }
        }
        .overlay(alignment: .topTrailing) {
            EaterBadge(people: store.eaters(of: entry), everyone: store.ateTogether(entry), size: badgeSize, ringed: true)
                .offset(x: badgeSize * 0.36, y: -badgeSize * 0.36)
        }
        .overlay(alignment: .bottomTrailing) {
            if extra > 0 {
                Text(badge ?? "+\(extra)")
                    .font(.body(10, weight: 800))
                    .foregroundStyle(Theme.surface)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.ink.opacity(0.8), in: Capsule())
                    .offset(x: 4, y: 4)
            }
        }
        .rotationEffect(.degrees(rotation))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(photoCount: photoCount))
    }

    private func accessibilityText(photoCount: Int) -> String {
        var text = "\(entry.slot): \(entry.title)"
        if extra > 0 { text += " and \(extra) more" }
        if photoCount > 1 { text += ", \(photoCount) photos" }
        return text
    }
}

/// "📷 3" in a dark pill: the meal has more photos than the one shown. Open the meal to
/// page through them; in grids, sideways swipes stay for dishes.
struct PhotoCountChip: View {
    let count: Int
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: size * 0.3) {
            Image(systemName: "camera.fill").font(.system(size: size * 0.95, weight: .semibold))
            Text("\(count)").font(.body(size, weight: 800)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, size * 0.55)
        .padding(.vertical, size * 0.32)
        .background(Color.black.opacity(0.58), in: Capsule())
        .accessibilityHidden(true)
    }
}

/// A slot's dishes as a stack of polaroids: swipe sideways to bring the next dish to the
/// top (it wraps around), tap to open the one on top. One dish is a plain button.
struct PolaroidStack: View {
    let entries: [JournalEntry]
    var rotation: Double = 0
    var emojiSize: CGFloat = 38
    var captionSize: CGFloat = 16
    let onOpen: (JournalEntry) -> Void

    @State private var index = 0
    @State private var drag: CGFloat = 0
    /// -1 when the last swipe went left, 1 when right; the outgoing card leaves that way.
    @State private var direction: CGFloat = -1

    /// How far a swipe must travel to change dishes.
    static let threshold: CGFloat = 36

    var body: some View {
        let current = entries[min(index, entries.count - 1)]
        if entries.count == 1 {
            Button { onOpen(current) } label: { card(current) }
                .buttonStyle(.plain)
        } else {
            card(current)
                .id(current.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .offset(x: direction * 70)).combined(with: .scale(scale: 0.96))
                ))
                .offset(x: drag * 0.55)
                .rotationEffect(.degrees(Double(drag) / 14))
                .contentShape(Rectangle())
                .onTapGesture { onOpen(current) }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { drag = $0.translation.width }
                        .onEnded { value in
                            let travel = value.predictedEndTranslation.width
                            if abs(value.translation.width) > Self.threshold || abs(travel) > Self.threshold * 3 {
                                step(travel < 0 ? 1 : -1)
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { drag = 0 }
                            }
                        }
                )
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Swipe left or right for the other dishes")
                .accessibilityAction { onOpen(current) }
                .accessibilityAdjustableAction { change in
                    switch change {
                    case .increment: step(1)
                    case .decrement: step(-1)
                    @unknown default: break
                    }
                }
        }
    }

    private func card(_ entry: JournalEntry) -> some View {
        Polaroid(
            entry: entry,
            rotation: rotation,
            emojiSize: emojiSize,
            captionSize: captionSize,
            extra: entries.count - 1,
            badge: entries.count > 1 ? "\(min(index, entries.count - 1) + 1)/\(entries.count)" : nil
        )
    }

    /// Brings the next (1) or previous (-1) dish to the top.
    private func step(_ offset: Int) {
        direction = offset > 0 ? -1 : 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            index = (index + offset + entries.count) % entries.count
            drag = 0
        }
    }
}

/// A dashed tile for a meal that was not logged; a camera button for today.
struct EmptyPolaroid: View {
    let label: String
    /// Draws the plate on a beige tablecloth (week grid) or keeps it airy (Today card).
    var showsPlate = true
    var captionSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.clear
                if showsPlate {
                    PlateArt(emoji: "", tint: Theme.background, plate: 0.51)
                }
                Image(systemName: "camera")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.muted)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            Text(label)
                .font(.hand(captionSize, weight: 600))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: captionSize * 1.6)
        }
        .padding([.top, .horizontal], 6)
        .padding(.bottom, 2)
        .overlay {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Theme.muted.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Who ate

/// One avatar for a single eater, or a ♥ when everyone ate together.
struct EaterBadge: View {
    let people: [Person]
    let everyone: Bool
    var size: CGFloat = 22
    var ringed = false

    var body: some View {
        Group {
            if everyone || people.count != 1 {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Theme.everyone, in: Circle())
            } else {
                Avatar(person: people[0], size: size)
            }
        }
        .padding(ringed ? 2 : 0)
        .background(ringed ? FoodStyle.polaroidPaper : .clear, in: Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Controls

/// The Week / Month chips in the header (white with a hairline, ink when selected).
struct FoodHeaderChip: View {
    let title: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body(13, weight: 600))
                .foregroundStyle(isSelected ? Theme.surface : Theme.ink)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isSelected ? Theme.ink : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Theme.ink : Theme.line))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A round chevron button for paging weeks and months.
struct PagerButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 34, height: 34)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.line))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A choice pill in sheets ("☀️ Lunch", "Felt tip"): paper gray, ink when selected.
struct FoodChoicePill<Label: View>: View {
    let isSelected: Bool
    /// Tighter, for rows of four or more choices.
    var compact = false
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.body(compact ? 13.5 : 14.5, weight: 700))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Theme.surface : Theme.ink)
                .padding(.horizontal, compact ? 11 : 16)
                .padding(.vertical, 9)
                .background(isSelected ? Theme.ink : Theme.surface2, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension FoodChoicePill where Label == Text {
    init(_ title: String, isSelected: Bool, compact: Bool = false, action: @escaping () -> Void) {
        self.init(isSelected: isSelected, compact: compact, action: action) { Text(title) }
    }
}

/// Uppercase label above a group in a sheet, with an optional quiet note after it.
struct SheetLabel: View {
    let title: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title.uppercased())
                .font(.body(12, weight: 800))
                .tracking(1)
            if let note {
                Text(note).font(.body(12, weight: 600))
            }
        }
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
    }
}

/// The six pen colors. The selected ink gets a ring.
struct InkPalette: View {
    let selected: PageInk?
    var size: CGFloat = 22
    var spacing: CGFloat = 7
    let onSelect: (PageInk) -> Void

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(PageInk.allCases) { ink in
                Button { onSelect(ink) } label: {
                    Circle()
                        .fill(ink.color)
                        .frame(width: size, height: size)
                        .padding(4)
                        .overlay {
                            if ink == selected {
                                Circle().stroke(ink.color, lineWidth: 2).padding(1)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(-4)
                .accessibilityLabel("\(ink.name) pen")
                .accessibilityAddTraits(ink == selected ? .isSelected : [])
            }
        }
    }
}

/// A rounded stat row: tinted square with an emoji, then a bold line and a quiet line.
struct StatRow: View {
    let emoji: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 22))
                .frame(width: 52, height: 52)
                .background(tint.wash(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body(14.5, weight: 700))
                Text(detail)
                    .font(.body(12.5, weight: 600))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Calendar lane

struct MealsLaneLabel: View {
    var body: some View {
        Text("🍽")
            .font(.system(size: 18))
            .accessibilityLabel("Meals")
    }
}

/// Tiny plates for a day: one per slot in the week grid, a compact strip in month cells.
struct MealPlatesCell: View {
    let store: FoodStore
    let day: DayKey
    let style: CalendarLane.Style

    var body: some View {
        let size: CGFloat = style == .week ? 20 : 15
        HStack(spacing: style == .week ? 4 : 3) {
            if style == .week {
                ForEach(store.slots, id: \.self) { slot in
                    let entry = store.entries(on: day, slot: slot).first
                    MiniPlate(emoji: entry?.emoji, size: size)
                }
            } else {
                ForEach(Array(store.entries(on: day).prefix(4).enumerated()), id: \.offset) { _, entry in
                    MiniPlate(emoji: entry.emoji, size: size)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let titles = store.entries(on: day).map(\.title)
        return titles.isEmpty ? "No meals logged" : "Meals: " + ListFormat.join(titles)
    }
}

/// A plate seen from above with a small emoji; a dashed ring when empty.
struct MiniPlate: View {
    let emoji: String?
    var size: CGFloat = 20

    var body: some View {
        if let emoji {
            ZStack {
                Circle().fill(Theme.background)
                Circle().fill(Color.white).padding(size * 0.24)
                Text(emoji).font(.system(size: size * 0.5))
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color(hex: 0x3C2814).opacity(0.08), lineWidth: 1))
        } else {
            Circle()
                .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                .frame(width: size, height: size)
        }
    }
}
