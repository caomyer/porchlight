import Foundation
import ImageIO
import UIKit

/// A meal photo ready to be stored: the whole shot and the square thumbnail the wall shows.
///
/// It lives in memory until a meal saves it, so a capture that is thrown away leaves nothing
/// behind. The image never changes once made and the thumbnail is always the image's `crop`,
/// so two are the same photo exactly when their id and crop are.
struct NewMealPhoto: Hashable, Identifiable, Sendable {
    /// The photo's row id once it is attached to a meal.
    let id: MealPhoto.ID
    let image: Data
    var thumbnail: Data
    /// The square the wall shows; nil is the center square.
    var crop: PhotoCrop?

    static func == (lhs: NewMealPhoto, rhs: NewMealPhoto) -> Bool {
        lhs.id == rhs.id && lhs.crop == rhs.crop
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(crop)
    }
}

/// Making meal photos: the one size that is stored and synced, and its thumbnails.
enum MealPhotoImaging {
    /// Longest edge of a stored photo, in pixels. There is no separate original: this is the photo.
    static let maxPixels: CGFloat = 2048
    static let thumbnailPixels: CGFloat = 360

    /// The whole shot as a JPEG at most `maxPixels` on its long side, with the square
    /// thumbnail of `crop` (the center square when nil). Safe to call off the main actor.
    static func prepare(_ image: UIImage, crop: PhotoCrop? = nil) throws -> NewMealPhoto {
        let upright = resized(image, maxPixels: maxPixels)
        guard let photo = upright.jpegData(compressionQuality: 0.85),
              let thumbnail = thumbnail(of: upright, crop: crop).jpegData(compressionQuality: 0.8)
        else { throw FoodError.photoUnreadable }
        return NewMealPhoto(id: .new(), image: photo, thumbnail: thumbnail, crop: crop)
    }

    /// A new thumbnail of a stored photo for `crop`. Safe to call off the main actor.
    static func thumbnail(ofImage data: Data, crop: PhotoCrop?) throws -> Data {
        guard let image = UIImage(data: data),
              let thumbnail = thumbnail(of: image, crop: crop).jpegData(compressionQuality: 0.8)
        else { throw FoodError.photoUnreadable }
        return thumbnail
    }

    /// An existing JPEG as it should be stored: byte for byte when it is at most `maxPixels`
    /// on its long side, else re-encoded at that size. Nil when it isn't a readable image.
    static func fitted(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        guard CGFloat(max(width, height)) > maxPixels else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixels),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.85)
    }

    // MARK: Image processing

    static func resized(_ image: UIImage, maxPixels: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor = min(1, maxPixels / max(pixelSize.width, pixelSize.height, 1))
        let target = CGSize(width: (pixelSize.width * factor).rounded(), height: (pixelSize.height * factor).rounded())
        return render(size: target) { image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    /// The crop (or the center square) of an upright image, scaled to a thumbnail.
    static func thumbnail(of image: UIImage, crop: PhotoCrop?) -> UIImage {
        guard let crop else { return squareThumbnail(image, pixels: thumbnailPixels) }
        return squareThumbnail(cropped(image, to: crop), pixels: thumbnailPixels)
    }

    /// The part of an upright image inside `crop`.
    static func cropped(_ image: UIImage, to crop: PhotoCrop) -> UIImage {
        let upright = image.imageOrientation == .up ? image : resized(image, maxPixels: max(image.size.width, image.size.height) * image.scale)
        guard let cg = upright.cgImage else { return upright }
        let size = CGSize(width: cg.width, height: cg.height)
        guard let part = cg.cropping(to: crop.rect(in: size)) else { return upright }
        return UIImage(cgImage: part)
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
