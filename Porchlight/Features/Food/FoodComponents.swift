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

// MARK: - Photos

/// Loads and caches meal photos from disk (thumbnails are tiny; full photos are downscaled JPEGs).
@MainActor
enum MealImages {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    static func image(at url: URL?) -> UIImage? {
        guard let url else { return nil }
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

// MARK: - Illustration

/// A meal's picture: its photo, or its emoji on a white plate over a tablecloth tint.
struct MealIllustration: View {
    let entry: JournalEntry
    /// Plate diameter as a fraction of the square's side.
    var plate: CGFloat = 0.5
    var emojiSize: CGFloat = 38

    @Environment(FoodStore.self) private var store
    @Environment(\.foodPreferFullPhoto) private var preferFullPhoto

    var body: some View {
        let file = preferFullPhoto ? (entry.photoFile ?? entry.thumbnailFile) : (entry.thumbnailFile ?? entry.photoFile)
        if let image = MealImages.image(at: store.photoURL(file)) {
            Color.clear
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipped()
        } else {
            PlateArt(emoji: entry.emoji ?? DishIllustration.fallbackEmoji, tint: Color(hex: UInt32(entry.tint ?? 0xF5EFE4)), plate: plate, emojiSize: emojiSize)
        }
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

/// A meal as a slightly rotated polaroid with a handwritten caption, who ate it and a 🛵 for delivery.
struct Polaroid: View {
    let entry: JournalEntry
    var rotation: Double = 0
    var emojiSize: CGFloat = 38
    var captionSize: CGFloat = 16
    var plate: CGFloat = 0.51
    var badgeSize: CGFloat = 22
    /// How many more meals share this slot ("+1").
    var extra = 0

    @Environment(FoodStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            MealIllustration(entry: entry, plate: plate, emojiSize: emojiSize)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(alignment: .topLeading) {
                    if entry.source == .delivery {
                        Text("🛵")
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
        .overlay(alignment: .topTrailing) {
            EaterBadge(people: store.eaters(of: entry), everyone: store.ateTogether(entry), size: badgeSize, ringed: true)
                .offset(x: badgeSize * 0.36, y: -badgeSize * 0.36)
        }
        .overlay(alignment: .bottomTrailing) {
            if extra > 0 {
                Text("+\(extra)")
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
        .accessibilityLabel("\(entry.slot): \(entry.title)")
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
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.body(14.5, weight: 700))
                .foregroundStyle(isSelected ? Theme.surface : Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? Theme.ink : Theme.surface2, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension FoodChoicePill where Label == Text {
    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.init(isSelected: isSelected, action: action) { Text(title) }
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
        HStack(spacing: 4) {
            Text("🍽").font(.system(size: 12))
            Text("Meals").font(.body(11, weight: 700)).foregroundStyle(Theme.muted)
        }
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
