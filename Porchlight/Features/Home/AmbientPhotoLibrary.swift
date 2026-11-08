import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Image files for Ambient mode, kept in Application Support/Porchlight/Ambient.
///
/// Picked photos are downsized once on import (they are shown full-screen, never zoomed),
/// so the wall never decodes a 48 MP original. The database holds only file names.
actor AmbientPhotoLibrary {
    static let shared = AmbientPhotoLibrary(folder: AmbientPhotoLibrary.defaultFolder)

    /// Longest edge of a stored photo, in pixels. Covers the iPad Pro 10.5" (2224 x 1668) with Ken Burns room.
    static let maxPixelSize = 2600

    struct Stored: Sendable {
        var fileName: String
        var caption: String?
    }

    enum ImportError: Error, LocalizedError {
        case unreadable

        var errorDescription: String? { "That photo couldn't be read. Try another one." }
    }

    nonisolated let folder: URL

    init(folder: URL) {
        self.folder = folder
    }

    private static var defaultFolder: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Porchlight/Ambient", isDirectory: true)
    }

    nonisolated func url(for fileName: String) -> URL {
        folder.appendingPathComponent(fileName)
    }

    /// Downsizes image data (JPEG, HEIC, PNG...) to a JPEG file. The caption is the month it was taken.
    func store(_ data: Data) throws -> Stored {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = Self.downsampled(source, maxPixelSize: Self.maxPixelSize),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.86) else {
            throw ImportError.unreadable
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileName = UUID().uuidString + ".jpg"
        try jpeg.write(to: url(for: fileName), options: .atomic)
        return Stored(fileName: fileName, caption: Self.caption(for: source))
    }

    nonisolated func removeFile(named fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// Deletes image files no photo row points to (left behind by a reset household).
    func removeFiles(notIn keep: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !keep.contains(file) {
            removeFile(named: file)
        }
    }

    /// Decodes an image at most `maxPixelSize` on its longest edge, honoring EXIF orientation.
    nonisolated static func downsampled(_ source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Loads a stored (or extra) photo sized for the screen. Runs off the main actor.
    nonisolated static func loadForDisplay(_ url: URL, maxPixelSize: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = downsampled(source, maxPixelSize: maxPixelSize) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }

    /// "Aug 2026" from the EXIF capture date, when there is one.
    private static func caption(for source: CGImageSource) -> String? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = parser.date(from: raw) else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }
}
