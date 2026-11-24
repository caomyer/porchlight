import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit
import Vision

/// A companion cut out of its photo on this device and drawn as a sticker: a white outline
/// and a soft shadow on a clear square (docs/design/companion-characters.md, "The photo
/// sticker"). Nothing leaves the device.
///
/// The cut-out is Vision's subject lifting (`VNGenerateForegroundInstanceMaskRequest`,
/// iOS 17). Where it can't run, or takes too long, as it may on the old wall iPad, the
/// photo stays and the screen says so; a sticker is never needed for anything.
enum PhotoSticker {
    /// The sticker's square, in pixels. Shown at most 184 points wide, which is 368 pixels on
    /// the wall; the margin keeps the outline sharp when a screen scales it up.
    static let side = 512
    /// The longest side of the plain cut-out kept for drawing a character, as the relay takes it.
    static let cutoutSide = 1024
    /// Photos are read no larger than this; a companion photo is stored at 800 already, but a
    /// photo picked just now can be a 48 megapixel original.
    static let largestInput: CGFloat = 2048
    /// The longest finding the subject may take before the photo is kept instead.
    static let timeout: Duration = .seconds(15)
    /// How many cut-outs were started since launch: none until someone asks for a sticker
    /// (docs/design/companion-characters.md, "Nothing changes on update").
    static let cutOuts = ActivityCount()

    struct Result: Equatable, Sendable {
        /// The sticker, a PNG `side` pixels square.
        var sticker: Data
        /// The subject alone on clear, a PNG no longer than `cutoutSide`: what a character is
        /// drawn from, and what the consent sheet shows.
        var cutout: Data
        var notes: Set<Note>
    }

    enum Note: Hashable, Sendable {
        /// More than one subject was found; the largest was used.
        case severalSubjects
        /// The subject runs off the photo's edge, so part of it is missing.
        case cutByEdge
    }

    enum Failure: Error, Equatable {
        /// The photo couldn't be read.
        case unreadable
        /// Nothing stands out from the background.
        case noSubject
        /// This device can't cut out a subject, or not in time.
        case unavailable
    }

    /// Cuts the subject out of `photo` and draws the sticker. Runs off the main thread.
    static func make(from photo: Data, finder: SubjectFinder = .current, timeout: Duration = timeout) async throws -> Result {
        cutOuts.add()
        guard let image = image(from: photo) else { throw Failure.unreadable }
        // Only finding the subject is timed: that is what an old device may not do, or not in
        // time. Drawing the sticker is ordinary image work.
        let subject = try await withThrowingTaskGroup(of: Subject.self) { group in
            group.addTask(priority: .userInitiated) { try await finder.find(in: image) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.unavailable
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw Failure.unavailable }
            return first
        }
        return try await Task.detached(priority: .userInitiated) { try render(photo: image, subject: subject) }.value
    }

    /// The photo, upright, no larger than `largestInput` on its long side.
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: largestInput,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: Drawing

    /// The subject cut from `photo` by its mask, as the sticker and the plain cut-out.
    static func render(photo: CGImage, subject: Subject) throws -> Result {
        let source = CIImage(cgImage: photo)
        let mask = CIImage(cgImage: subject.mask)
            .transformed(by: CGAffineTransform(scaleX: source.extent.width / CGFloat(subject.mask.width),
                                               y: source.extent.height / CGFloat(subject.mask.height)))
        let clear = CIImage(color: .clear).cropped(to: source.extent)
        let cut = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask,
        ])
        // The subject's box, in Core Image's bottom-up coordinates.
        let box = subject.bounds.applying(CGAffineTransform(
            scaleX: source.extent.width / CGFloat(subject.mask.width), y: source.extent.height / CGFloat(subject.mask.height)
        ))
        let flipped = CGRect(x: box.minX, y: source.extent.height - box.maxY, width: box.width, height: box.height)
        let cropped = cut.cropped(to: flipped)
        guard !cropped.extent.isEmpty else { throw Failure.noSubject }

        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        // The plain cut-out, for drawing a character from.
        let cutoutScale = min(1, CGFloat(cutoutSide) / max(cropped.extent.width, cropped.extent.height))
        let plain = cropped.transformed(by: CGAffineTransform(scaleX: cutoutScale, y: cutoutScale))
        let plainExtent = plain.extent.integral
        guard let cutoutImage = context.createCGImage(plain, from: plainExtent),
              let cutout = png(cutoutImage) else { throw Failure.unreadable }

        // The sticker: the subject at 80% of a square, outlined in white, a soft shadow below.
        let side = CGFloat(Self.side)
        let fit = (side * 0.8) / max(cropped.extent.width, cropped.extent.height)
        var placed = cropped.transformed(by: CGAffineTransform(scaleX: fit, y: fit))
        placed = placed.transformed(by: CGAffineTransform(
            translationX: (side - placed.extent.width) / 2 - placed.extent.minX,
            y: (side - placed.extent.height) / 2 - placed.extent.minY
        ))
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let white = placed.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])
        let outline = white.applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": side * 0.018]).cropped(to: canvas)
        let shadow = outline.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.22),
        ]).applyingGaussianBlur(sigma: side * 0.012)
            .transformed(by: CGAffineTransform(translationX: 0, y: -side * 0.01)).cropped(to: canvas)
        let sticker = placed.composited(over: outline).composited(over: shadow).cropped(to: canvas)
        guard let stickerImage = context.createCGImage(sticker, from: canvas), let stickerData = png(stickerImage) else {
            throw Failure.unreadable
        }
        var notes: Set<Note> = []
        if subject.others > 0 { notes.insert(.severalSubjects) }
        if subject.touchesEdge { notes.insert(.cutByEdge) }
        return Result(sticker: stickerData, cutout: cutout, notes: notes)
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

// MARK: - The subject

/// The subject found in a photo: its mask (white where it is), the box around it in the
/// mask's top-down pixels, and what else was found.
struct Subject: @unchecked Sendable {
    var mask: CGImage
    var bounds: CGRect
    /// Other subjects found beside it, at least a fifth of its size.
    var others: Int
    var touchesEdge: Bool
}

/// A grayscale mask, read into numbers: the pure part of finding the subject, so it can be
/// tested with masks drawn in code.
struct MaskGrid: Equatable {
    var width: Int
    var height: Int
    /// 0 to 1 per pixel, rows top first.
    var values: [Float]

    /// The box around everything above `threshold`, in pixels, top first; nil if nothing is.
    func bounds(threshold: Float = 0.5) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where values[y * width + x] > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// How much of the picture the subject covers, 0 to 1.
    func coverage(threshold: Float = 0.5) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.filter { $0 > threshold }.count) / Double(values.count)
    }

    /// Whether the subject runs off the picture's edge: it covers a stretch of the border
    /// row or column, not just a stray pixel or two.
    func touchesEdge(threshold: Float = 0.5) -> Bool {
        func share(_ points: [Int]) -> Double {
            Double(points.filter { values[$0] > threshold }.count) / Double(max(points.count, 1))
        }
        let top = Array(0..<width), bottom = Array((height - 1) * width..<height * width)
        let left = (0..<height).map { $0 * width }, right = (0..<height).map { $0 * width + width - 1 }
        return [top, bottom, left, right].contains { share($0) > 0.04 }
    }

    /// Which of several subjects to keep: the largest, with how many others are at least a
    /// fifth of its size (a second pet, a person holding it). Nil when none covers enough of
    /// the photo to be a subject at all.
    static func pick(_ instances: [MaskGrid], threshold: Float = 0.5) -> (index: Int, others: Int)? {
        let sizes = instances.map { $0.coverage(threshold: threshold) }
        guard let largest = sizes.indices.max(by: { sizes[$0] < sizes[$1] }), sizes[largest] >= 0.01 else { return nil }
        let others = sizes.indices.filter { $0 != largest && sizes[$0] >= sizes[largest] / 5 }.count
        return (largest, others)
    }

    /// A mask as a grayscale picture, for cutting the photo with it.
    func image() -> CGImage? {
        let bytes = values.map { UInt8(max(0, min(1, $0)) * 255) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

/// Finds the subject in a photo. Vision on a device; a drawn stand-in in UI tests, where the
/// simulator may not run subject lifting.
struct SubjectFinder: Sendable {
    let find: @Sendable (CGImage) async throws -> Subject

    func find(in image: CGImage) async throws -> Subject {
        try await find(image)
    }

    static var current: SubjectFinder {
        #if DEBUG
        if let shape = UserDefaults.standard.string(forKey: "debugStickerSubject") { return .drawn(shape) }
        #endif
        return .vision
    }

    /// Vision's subject lifting, iOS 17. Each instance is read at a small size to pick the
    /// largest; the chosen one's mask is read at the photo's own size for the cut.
    static let vision = SubjectFinder { image in
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
        } catch {
            throw PhotoSticker.Failure.unavailable
        }
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw PhotoSticker.Failure.noSubject }
        var instances: [Int] = []
        var grids: [MaskGrid] = []
        for instance in result.allInstances.sorted() {
            guard let buffer = try? result.generateScaledMaskForImage(forInstances: [instance], from: handler),
                  let grid = MaskGrid(buffer, longest: 256) else { continue }
            instances.append(instance)
            grids.append(grid)
        }
        guard let pick = MaskGrid.pick(grids) else { throw PhotoSticker.Failure.noSubject }
        guard let buffer = try? result.generateScaledMaskForImage(forInstances: [instances[pick.index]], from: handler),
              let full = MaskGrid(buffer, longest: max(image.width, image.height)),
              let bounds = full.bounds(), let mask = full.image() else { throw PhotoSticker.Failure.noSubject }
        return Subject(mask: mask, bounds: bounds, others: pick.others, touchesEdge: grids[pick.index].touchesEdge())
    }

    #if DEBUG
    /// A stand-in subject for UI tests: "middle" (a round subject in the middle), "edge" (one
    /// running off the bottom), "two" (two subjects), "none" or "slow" (never answers).
    static func drawn(_ shape: String) -> SubjectFinder {
        SubjectFinder { image in
            if shape == "slow" { try await Task.sleep(for: .seconds(3600)) }
            if shape == "unavailable" { throw PhotoSticker.Failure.unavailable }
            let grid = MaskGrid.drawn(shape, width: 160, height: 160 * image.height / max(image.width, 1))
            guard let grid, let bounds = grid.bounds(), let mask = grid.image() else { throw PhotoSticker.Failure.noSubject }
            let scale = CGFloat(image.width) / CGFloat(grid.width)
            let full = CGRect(x: bounds.minX * scale, y: bounds.minY * scale, width: bounds.width * scale, height: bounds.height * scale)
            let upscaled = MaskGrid.scaled(mask, width: image.width, height: image.height) ?? mask
            return Subject(mask: upscaled, bounds: full, others: shape == "two" ? 1 : 0, touchesEdge: grid.touchesEdge())
        }
    }
    #endif
}

extension MaskGrid {
    /// A Vision mask (one 32-bit float per pixel), read at most `longest` pixels on its long side.
    init?(_ buffer: CVPixelBuffer, longest: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let sourceWidth = CVPixelBufferGetWidth(buffer), sourceHeight = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let step = max(1, Int((Double(max(sourceWidth, sourceHeight)) / Double(longest)).rounded(.up)))
        let width = max(1, sourceWidth / step), height = max(1, sourceHeight / step)
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * step * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<width { values[y * width + x] = row[x * step] }
        }
        self.init(width: width, height: height, values: values)
    }

    /// A mask drawn in code: shapes for tests and the UI tests' stand-in finder.
    static func drawn(_ shape: String, width: Int, height: Int) -> MaskGrid? {
        guard width > 0, height > 0 else { return nil }
        var values = [Float](repeating: 0, count: width * height)
        func disc(_ cx: Double, _ cy: Double, _ r: Double) {
            for y in 0..<height {
                for x in 0..<width {
                    let dx = (Double(x) + 0.5) / Double(width) - cx, dy = (Double(y) + 0.5) / Double(height) - cy
                    if dx * dx + dy * dy <= r * r { values[y * width + x] = 1 }
                }
            }
        }
        switch shape {
        case "middle": disc(0.5, 0.5, 0.3)
        case "edge": disc(0.5, 0.95, 0.3)
        case "two": disc(0.3, 0.5, 0.2); disc(0.72, 0.5, 0.16)
        case "none": break
        default: return nil
        }
        return MaskGrid(width: width, height: height, values: values)
    }

    /// A mask picture redrawn at another size.
    static func scaled(_ mask: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// A count of something done since launch, safe from any thread: how tests prove a thing
/// was never done.
final class ActivityCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func add() { lock.withLock { value += 1 } }
}
