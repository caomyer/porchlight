#if DEBUG
import Foundation
import PencilKit
import UIKit

/// A week of sample meals and handwritten pages for `-sampleHousehold`, relative to today.
enum FoodSamples {
    /// One sample dish: emoji, title, who ate (index into people, nil = everyone), source, tint, rating.
    private struct Dish {
        let emoji: String
        let title: String
        let who: Int?
        let source: MealSource
        let tint: Int
        var rating: MealRating = .again
        var place: PlaceDraft?
    }

    private static let sushiBar = PlaceDraft(name: "Sakura Sushi Bar", address: "412 Valencia St, San Francisco", latitude: 37.765, longitude: -122.422, category: "Restaurant")
    private static let pizzeria = PlaceDraft(name: "Tony's Corner Pizza", address: "1570 Stockton St, San Francisco", latitude: 37.800, longitude: -122.409, category: "Restaurant")
    private static let phoHouse = PlaceDraft(name: "Pho Saigon House", address: "735 Larkin St, San Francisco", latitude: 37.784, longitude: -122.417, category: "Restaurant")

    private static func home(_ emoji: String, _ title: String, _ who: Int?, _ tint: Int, _ rating: MealRating = .again) -> Dish {
        Dish(emoji: emoji, title: title, who: who, source: .home, tint: tint, rating: rating)
    }

    private static func delivery(_ emoji: String, _ title: String, _ who: Int?, _ tint: Int, _ rating: MealRating = .again, from place: PlaceDraft? = nil) -> Dish {
        Dish(emoji: emoji, title: title, who: who, source: .delivery, tint: tint, rating: rating, place: place)
    }

    private static func out(_ emoji: String, _ title: String, _ who: Int?, _ tint: Int, _ rating: MealRating = .again, at place: PlaceDraft) -> Dish {
        Dish(emoji: emoji, title: title, who: who, source: .dineOut, tint: tint, rating: rating, place: place)
    }

    /// The last seven days (six days ago ... today): breakfast, lunch, dinner.
    private static let week: [[Dish?]] = [
        [home("🥞", "Pancakes", nil, 0xF3D9A4, .favorite), home("🥗", "Cobb salad", 1, 0xCFE3C4), home("🍝", "Pesto pasta", nil, 0xE8C9B5)],
        [home("🥣", "Granola", 0, 0xE9DCC4, .fine), nil, home("🍛", "Chicken curry", nil, 0xF1C78F)],
        [home("🥯", "Bagel", 1, 0xE6D3B8, .fine), delivery("🍱", "Bento box", 0, 0xD9E2EE), home("🌮", "Taco night", nil, 0xF2C6A8)],
        [home("🍳", "Eggs & toast", nil, 0xF5E2A6), delivery("🥪", "Banh mi", 1, 0xE8D7C2), home("🍲", "Miso salmon", nil, 0xCBDDE6, .favorite)],
        [home("🥣", "Oatmeal", 0, 0xEADFCB, .fine), out("🍜", "Pho", nil, 0xF0D5B8, at: phoHouse), delivery("🍕", "Pizza", nil, 0xF4C3B4, .meh, from: pizzeria)],
        [nil, home("🥙", "Falafel wrap", 1, 0xDCE6CF), out("🍣", "Sushi night", nil, 0xE5D0DA, .favorite, at: sushiBar)],
        [home("🥑", "Avocado toast", 1, 0xD7E5C2), nil, nil],
    ]

    /// Second dishes in a slot of `week`: day index, slot index, dish.
    private static let extras: [(Int, Int, Dish)] = [
        (5, 2, out("🍡", "Mochi", nil, 0xF2D4DC, .favorite, at: sushiBar)),
        (3, 2, home("🥖", "Garlic bread", nil, 0xEFD9AE, .fine)),
        (6, 0, home("☕", "Oat latte", 0, 0xE6D5C3, .fine)),
    ]

    /// Handwritten lines per day of `week`: text and writer (index into people) or a fixed ink.
    private static let notes: [[(String, Int, PageInk?)]] = [
        [("pancakes ♡", 1, nil), ("cobb salad", 1, nil), ("pesto pasta!", 0, nil)],
        [("granola", 0, nil), ("chicken curry", 1, nil)],
        [("bagel", 1, nil), ("bento (delivery)", 0, nil), ("taco night!!", 1, .ochre)],
        [("eggs & toast", 0, nil), ("banh mi", 1, nil), ("miso salmon ★", 1, .forest)],
        [("oatmeal", 0, nil), ("pho", 1, nil), ("pizza... too much", 0, nil)],
        [("falafel wrap", 1, nil), ("sushi night ♡", 1, .plum)],
        [("avocado toast", 1, nil)],
    ]

    /// Earlier days, so the streak is long and most dishes are not "new this week".
    private static let history: [[Dish]] = [
        [home("🍳", "Eggs & toast", nil, 0xF5E2A6), home("🍝", "Pesto pasta", nil, 0xE8C9B5)],
        [home("🥣", "Granola", 0, 0xE9DCC4), delivery("🍜", "Pho", nil, 0xF0D5B8), home("🌮", "Taco night", nil, 0xF2C6A8)],
        [home("🥞", "Pancakes", nil, 0xF3D9A4), home("🥙", "Falafel wrap", 1, 0xDCE6CF), delivery("🍕", "Pizza", nil, 0xF4C3B4)],
        [home("🥯", "Bagel", 1, 0xE6D3B8), delivery("🍱", "Bento box", 0, 0xD9E2EE), home("🍛", "Chicken curry", nil, 0xF1C78F)],
        [home("🥑", "Avocado toast", 1, 0xD7E5C2), home("🥗", "Cobb salad", 1, 0xCFE3C4), delivery("🍣", "Sushi night", nil, 0xE5D0DA)],
        [home("🥣", "Oatmeal", 0, 0xEADFCB), delivery("🥪", "Banh mi", 1, 0xE8D7C2)],
    ]

    static func seed(_ database: AppDatabase, household: Household, people: [Person]) throws {
        guard !people.isEmpty else { return }
        let householdId = household.id
        let calendar = household.calendar
        let journal = try database.ensureFoodJournal(householdId: householdId)
        let journalId = journal.id
        let today = DayKey(.now, calendar: calendar)
        let slots = MealSlot.defaultNames
        let times = [8 * 60 + 40, 12 * 60 + 30, 19 * 60]

        @discardableResult
        func add(_ dish: Dish, day: DayKey, slot: Int, later minutes: Int = 0) throws -> JournalEntry {
            let eaters = dish.who.map { [people[min($0, people.count - 1)].id] } ?? people.map(\.id)
            let eatenAt = calendar.date(byAdding: .minute, value: times[slot] + minutes, to: day.startDate(in: calendar)) ?? .now
            let draft = MealDraft(
                day: day, slot: slots[slot], source: dish.source, title: dish.title, emoji: dish.emoji,
                tint: dish.tint, rating: dish.rating, eaterIds: eaters, eatenAt: eatenAt, place: dish.place
            )
            return try database.addMeal(draft, journalId: journalId, now: eatenAt)
        }

        /// Gives a sample meal generated photos, so covers, counts and paging show without a camera.
        func photograph(_ entry: JournalEntry, count: Int, palette: Int) throws {
            let id = entry.id
            let photos = try (0..<count).map { try MealPhotoImaging.prepare(SamplePhoto.image(palette: palette + $0, emoji: entry.emoji ?? "🍽️")) }
            try database.addMealPhotos(entryId: id, photos, now: entry.eatenAt)
        }

        for (index, meals) in history.enumerated() {
            let day = today.adding(days: index - 12, calendar: calendar)
            for (slot, dish) in meals.enumerated() { try add(dish, day: day, slot: slot) }
        }
        for (index, meals) in week.enumerated() {
            let day = today.adding(days: index - 6, calendar: calendar)
            for (slot, dish) in meals.enumerated() {
                guard let dish else { continue }
                let entry = try add(dish, day: day, slot: slot)
                // Today's breakfast has two photos; yesterday's dinner three.
                if index == 6 && slot == 0 { try photograph(entry, count: 2, palette: 0) }
                if index == 5 && slot == 2 { try photograph(entry, count: 3, palette: 2) }
            }
            let lines = notes[index].map { text, writer, ink in
                (text, ink ?? PageInk.defaultInk(for: people[min(writer, people.count - 1)].color))
            }
            let drawing = SampleHandwriting.page(lines: lines)
            try database.savePage(journalId: journalId, day: day, drawing: drawing.dataRepresentation())
        }

        for (index, slot, dish) in extras {
            try add(dish, day: today.adding(days: index - 6, calendar: calendar), slot: slot, later: 25)
        }

        // A memory for "On this day".
        let yearAgo = DayKey(calendar.date(byAdding: .year, value: -1, to: today.startDate(in: calendar)) ?? .now, calendar: calendar)
        let turkey = try add(home("🦃", "Practice turkey", nil, 0xF1CFA0, .favorite), day: yearAgo, slot: 2)
        try photograph(turkey, count: 1, palette: 5)
    }
}

/// A generated "photo" of a dish: a table, a plate seen from above and the dish's emoji,
/// lit warm, so sample meals can have photos without a camera.
enum SamplePhoto {
    private static let tables: [(UInt32, UInt32)] = [
        (0x6D4A32, 0x3D2A1E), (0x8A6A4A, 0x4A3424), (0x5A6B55, 0x2F3A2C),
        (0x9B5D3C, 0x522F1E), (0x444F63, 0x232A38), (0x7C6A4D, 0x3E3424),
    ]

    static func image(palette: Int, emoji: String) -> UIImage {
        let size = CGSize(width: 1600, height: 1200)
        let (top, bottom) = tables[abs(palette) % tables.count]
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [UIColor(rgb: top).cgColor, UIColor(rgb: bottom).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.8, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            // Each angle sits the plate a little differently.
            let shift = CGFloat((palette % 3) - 1) * 90
            let plate = CGRect(x: 380 + shift, y: 160, width: 860, height: 860)
            cg.setShadow(offset: CGSize(width: 0, height: 30), blur: 60, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            UIColor(white: 0.96, alpha: 1).setFill()
            cg.fillEllipse(in: plate)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(white: 0.88, alpha: 1).setStroke()
            cg.setLineWidth(26)
            cg.strokeEllipse(in: plate.insetBy(dx: 70, dy: 70))
            let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: 420)])
            let textSize = text.size()
            text.draw(at: CGPoint(x: plate.midX - textSize.width / 2, y: plate.midY - textSize.height / 2))
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// Turns sample text into real PencilKit strokes: the text is rendered in Caveat,
/// thinned to one-pixel center lines, and each line becomes a stroke. Debug-only:
/// real ink always comes from Apple Pencil.
enum SampleHandwriting {
    /// Pixels per page point while tracing.
    private static let resolution: CGFloat = 5
    private static let fontSize: CGFloat = 20
    private static let strokeWidth: CGFloat = 1.45

    static func page(lines: [(String, PageInk)]) -> PKDrawing {
        var strokes: [PKStroke] = []
        for (index, line) in lines.enumerated() {
            let band = PageGeometry.lineRect(index)
            let tilt: CGFloat = index.isMultiple(of: 2) ? -0.8 : 0.6
            strokes += self.strokes(for: line.0, ink: line.1, origin: CGPoint(x: PageGeometry.margin, y: band.minY), tiltDegrees: tilt)
        }
        return PKDrawing(strokes: strokes)
    }

    private static func strokes(for text: String, ink: PageInk, origin: CGPoint, tiltDegrees: CGFloat) -> [PKStroke] {
        let font = UIFont.variable(.hand, size: fontSize * resolution, weight: 560)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.black])
        let textSize = attributed.size()
        let width = Int(textSize.width.rounded(.up)) + 8
        let height = Int(PageGeometry.lineHeight * resolution)
        guard width > 8, let bitmap = render(attributed, width: width, height: height, baseline: 16.5 * resolution, font: font) else { return [] }

        var grid = Skeleton(width: width, height: height, pixels: bitmap)
        grid.thin()
        let paths = grid.traceLines()  // single points are dots ("...", "!")

        let angle = tiltDegrees * .pi / 180
        let pivot = CGPoint(x: 0, y: CGFloat(height) / 2)
        let rotate = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: angle).translatedBy(x: -pivot.x, y: -pivot.y)
        let toPage = rotate
            .concatenating(CGAffineTransform(scaleX: 1 / resolution, y: 1 / resolution))
            .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
        let inkType = PKInk(.monoline, color: ink.uiColor)
        return paths.map { pixels in
            let points = smoothed(simplified(pixels)).enumerated().map { index, point in
                PKStrokePoint(
                    location: point.applying(toPage),
                    timeOffset: TimeInterval(index) * 0.01,
                    size: CGSize(width: strokeWidth, height: strokeWidth),
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            }
            return PKStroke(ink: inkType, path: PKStrokePath(controlPoints: points, creationDate: .now))
        }
    }

    private static func render(_ text: NSAttributedString, width: Int, height: Int, baseline: CGFloat, font: UIFont) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Flip to UIKit coordinates and draw white text.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            let white = NSMutableAttributedString(attributedString: text)
            white.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: white.length))
            white.draw(at: CGPoint(x: 4, y: baseline - font.ascender))
            UIGraphicsPopContext()
            return true
        }
        return drawn ? pixels : nil
    }

    /// Keeps every few pixels of a traced line (pixel chains are dense and stair-stepped).
    private static func simplified(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 4 else { return points }
        var result = stride(from: 0, to: points.count, by: 3).map { points[$0] }
        if result.last != points.last { result.append(points[points.count - 1]) }
        return result
    }

    private static func smoothed(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result = points
        for index in 1..<(points.count - 1) {
            let a = points[index - 1], b = points[index], c = points[index + 1]
            result[index] = CGPoint(x: (a.x + 2 * b.x + c.x) / 4, y: (a.y + 2 * b.y + c.y) / 4)
        }
        return result
    }
}

/// A binary image thinned to one-pixel-wide center lines (Zhang-Suen), then traced into polylines.
private struct Skeleton {
    let width: Int
    let height: Int
    var on: [Bool]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        on = pixels.map { $0 > 110 }
    }

    private func at(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && on[y * width + x]
    }

    /// Zhang-Suen thinning on a flat buffer (no per-pixel allocations, so it stays quick in debug builds).
    mutating func thin() {
        let w = width, h = height
        on.withUnsafeMutableBufferPointer { px in
            var remove: [Int] = []
            remove.reserveCapacity(1024)
            var changed = true
            while changed {
                changed = false
                for pass in 0..<2 {
                    remove.removeAll(keepingCapacity: true)
                    for y in 1..<(h - 1) {
                        let row = y * w
                        for x in 1..<(w - 1) where px[row + x] {
                            let i = row + x
                            let p2 = px[i - w], p3 = px[i - w + 1], p4 = px[i + 1], p5 = px[i + w + 1]
                            let p6 = px[i + w], p7 = px[i + w - 1], p8 = px[i - 1], p9 = px[i - w - 1]
                            let ring = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
                            var count = 0, transitions = 0
                            for k in 0..<8 {
                                if ring[k] { count += 1 } else if ring[k + 1] { transitions += 1 }
                            }
                            guard count >= 2, count <= 6, transitions == 1 else { continue }
                            if pass == 0 {
                                guard !(p2 && p4 && p6), !(p4 && p6 && p8) else { continue }
                            } else {
                                guard !(p2 && p4 && p8), !(p2 && p6 && p8) else { continue }
                            }
                            remove.append(i)
                        }
                    }
                    for index in remove { px[index] = false }
                    if !remove.isEmpty { changed = true }
                }
            }
        }
    }

    private func neighborIndices(_ index: Int) -> [Int] {
        let x = index % width, y = index / width
        var result: [Int] = []
        for dy in -1...1 {
            for dx in -1...1 where !(dx == 0 && dy == 0) && at(x + dx, y + dy) {
                result.append((y + dy) * width + x + dx)
            }
        }
        return result
    }

    /// Walks the skeleton into polylines: from end points first, then around loops.
    func traceLines() -> [[CGPoint]] {
        var visited = Set<Int>()
        var lines: [[CGPoint]] = []
        func point(_ index: Int) -> CGPoint { CGPoint(x: index % width, y: index / width) }

        func walk(from start: Int) -> [CGPoint] {
            var path = [point(start)]
            visited.insert(start)
            var current = start
            var previous: Int?
            while true {
                let candidates = neighborIndices(current).filter { !visited.contains($0) }
                guard !candidates.isEmpty else { break }
                // Prefer continuing straight: pick the 4-connected neighbor first.
                let next = candidates.min { a, b in
                    distance(a, current) < distance(b, current) || (distance(a, current) == distance(b, current) && turn(previous, current, a) < turn(previous, current, b))
                }!
                visited.insert(next)
                path.append(point(next))
                previous = current
                current = next
            }
            return path
        }

        let skeleton = on.indices.filter { on[$0] }
        let ends = skeleton.filter { neighborIndices($0).count == 1 }
        for end in ends where !visited.contains(end) { lines.append(walk(from: end)) }
        for index in skeleton where !visited.contains(index) { lines.append(walk(from: index)) }
        return lines
    }

    private func distance(_ a: Int, _ b: Int) -> Int {
        abs(a % width - b % width) + abs(a / width - b / width)
    }

    /// How sharply the path would turn going previous -> current -> next (0 = straight).
    private func turn(_ previous: Int?, _ current: Int, _ next: Int) -> Int {
        guard let previous else { return 0 }
        let dx1 = current % width - previous % width, dy1 = current / width - previous / width
        let dx2 = next % width - current % width, dy2 = next / width - current / width
        return abs(dx1 - dx2) + abs(dy1 - dy2)
    }
}
#endif
