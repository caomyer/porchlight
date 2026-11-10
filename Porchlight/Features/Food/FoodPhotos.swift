import Foundation
import UIKit

/// Meal photos on disk: Application Support/Porchlight/Photos/meal-<uuid>.jpg plus a
/// square thumbnail. The database stores only the file names.
struct FoodPhotoStore: Sendable {
    let directory: URL

    static let filePrefix = "meal-"
    /// Longest edge of a stored photo, in pixels.
    static let maxPixels: CGFloat = 2048
    static let thumbnailPixels: CGFloat = 360

    /// The app's photo folder.
    static var standard: FoodPhotoStore {
        FoodPhotoStore(directory: AppFiles.folder("Photos"))
    }

    struct Stored: Equatable, Hashable, Sendable {
        var photoFile: String
        var thumbnailFile: String
    }

    func url(for file: String) -> URL {
        directory.appendingPathComponent(file)
    }

    /// Writes a downscaled JPEG and its thumbnail. Safe to call off the main actor.
    func save(_ image: UIImage) throws -> Stored {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = Self.filePrefix + UUID().uuidString.lowercased()
        let stored = Stored(photoFile: name + ".jpg", thumbnailFile: name + "-thumb.jpg")
        guard let photo = Self.resized(image, maxPixels: Self.maxPixels).jpegData(compressionQuality: 0.85),
              let thumbnail = Self.squareThumbnail(image, pixels: Self.thumbnailPixels).jpegData(compressionQuality: 0.8)
        else { throw FoodError.photoUnreadable }
        do {
            try photo.write(to: url(for: stored.photoFile), options: .atomic)
            try thumbnail.write(to: url(for: stored.thumbnailFile), options: .atomic)
        } catch {
            delete([stored.photoFile, stored.thumbnailFile])
            throw error
        }
        return stored
    }

    /// Removes files, ignoring ones that are already gone.
    func delete(_ files: [String?]) {
        for file in files.compactMap({ $0 }) where Self.isOwnFile(file) {
            try? FileManager.default.removeItem(at: url(for: file))
        }
    }

    /// Deletes meal photos no entry points to any more (for example after the
    /// household was deleted, which cascades rows but cannot touch files).
    func sweep(keeping referenced: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        delete(files.filter { Self.isOwnFile($0) && !referenced.contains($0) })
    }

    /// Only our own flat file names, never paths, so a bad row cannot delete anything else.
    static func isOwnFile(_ name: String) -> Bool {
        name.hasPrefix(filePrefix) && !name.contains("/") && !name.contains("..")
    }

    // MARK: Image processing

    static func resized(_ image: UIImage, maxPixels: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor = min(1, maxPixels / max(pixelSize.width, pixelSize.height, 1))
        let target = CGSize(width: (pixelSize.width * factor).rounded(), height: (pixelSize.height * factor).rounded())
        return render(size: target) { image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    static func squareThumbnail(_ image: UIImage, pixels: CGFloat) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let scale = pixels / max(side, 1)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (pixels - drawn.width) / 2, y: (pixels - drawn.height) / 2)
        return render(size: CGSize(width: pixels, height: pixels)) { image.draw(in: CGRect(origin: origin, size: drawn)) }
    }

    private static func render(size: CGSize, _ draw: () -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw() }
    }
}

enum FoodError: Error, Equatable, LocalizedError {
    case noJournal
    case unknownSlot(String)
    case nobodyAte
    case titleTooLong(limit: Int)
    case placeNameTooLong(limit: Int)
    case photoUnreadable
    case mealNotFound
    case tooManyPhotos(limit: Int)

    var errorDescription: String? {
        switch self {
        case .noJournal: "Turn on the food diary in Settings first."
        case let .unknownSlot(slot): "\(slot) is not one of this diary's meals."
        case .nobodyAte: "Pick who ate."
        case let .titleTooLong(limit): "Keep the dish name under \(limit) characters."
        case let .placeNameTooLong(limit): "Keep the restaurant name under \(limit) characters."
        case .photoUnreadable: "That photo could not be saved."
        case .mealNotFound: "That meal was already removed."
        case let .tooManyPhotos(limit): "A meal can have up to \(limit) photos."
        }
    }
}
