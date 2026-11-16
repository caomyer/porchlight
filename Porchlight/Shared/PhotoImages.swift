import Observation
import SwiftUI
import UIKit

/// A picture the wall can show, named by where its bytes are.
///
/// Stored pictures carry their row's byte count, which changes whenever the picture does
/// (a reframed thumbnail, a new companion photo, a row that just arrived by sync), so a
/// cached image is never shown for a picture that has since changed.
enum PhotoSource: Hashable, Sendable {
    case mealThumbnail(MealPhoto.ID, byteCount: Int)
    case mealImage(MealPhoto.ID, byteCount: Int)
    case companion(Companion.ID, byteCount: Int)
    /// Bytes not saved yet, such as a photo just taken or picked.
    case unsaved(Data)
}

/// A picture to show, and which square of it; nil shows it whole.
struct PhotoRequest: Hashable, Sendable {
    var source: PhotoSource
    var crop: PhotoCrop?

    init(_ source: PhotoSource, crop: PhotoCrop? = nil) {
        self.source = source
        self.crop = crop
    }
}

/// Decoded photos, read from their rows (docs/design/sync-icloud.md, "Photos").
///
/// Bytes are read and decoded off the main thread, once per request however many views ask
/// at the same time, and kept in a cache bounded by decoded size, so a month of thumbnails
/// scrolls without reloading and a busy day never grows memory without bound.
@MainActor
@Observable
final class PhotoImages {
    /// About two hundred thumbnails, or a handful of whole shots.
    static let memoryLimit = 96 * 1024 * 1024

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let cache = NSCache<Key, UIImage>()
    @ObservationIgnored private var loading: [PhotoRequest: Task<UIImage?, Never>] = [:]

    init(database: AppDatabase) {
        self.database = database
        cache.totalCostLimit = Self.memoryLimit
    }

    /// The image if it is already decoded, for drawing it in the first frame.
    func cached(_ request: PhotoRequest) -> UIImage? {
        cache.object(forKey: Key(request))
    }

    /// The decoded image, or nil when its bytes are gone or unreadable.
    func image(_ request: PhotoRequest) async -> UIImage? {
        if let hit = cached(request) { return hit }
        if let pending = loading[request] { return await pending.value }
        let database = database
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? database.bytes(of: request.source) else { return nil }
            return Self.decode(data, crop: request.crop)
        }
        loading[request] = task
        let image = await task.value
        loading[request] = nil
        if let image {
            cache.setObject(image, forKey: Key(request), cost: Self.cost(of: image))
        }
        return image
    }

    /// The bytes of a stored picture, read off the main thread, e.g. to reframe it.
    func bytes(of source: PhotoSource) async -> Data? {
        let database = database
        return await Task.detached(priority: .userInitiated) { try? database.bytes(of: source) }.value
    }

    nonisolated private static func decode(_ data: Data, crop: PhotoCrop?) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let shown = crop.map { MealPhotoImaging.cropped(image, to: $0) } ?? image
        return shown.preparingForDisplay() ?? shown
    }

    private static func cost(of image: UIImage) -> Int {
        image.cgImage.map { $0.bytesPerRow * $0.height } ?? Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    }

    /// NSCache needs an object key.
    private final class Key: NSObject {
        let request: PhotoRequest

        init(_ request: PhotoRequest) {
            self.request = request
        }

        override var hash: Int { request.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            (object as? Key)?.request == request
        }
    }
}

extension AppDatabase {
    /// The bytes behind a picture, nil when its row is gone (or hasn't arrived yet).
    func bytes(of source: PhotoSource) throws -> Data? {
        let (table, key, id): (String, String, String)
        switch source {
        case let .mealThumbnail(photoId, _): (table, key, id) = ("journalEntryPhotoThumb", "photoId", photoId.description)
        case let .mealImage(photoId, _): (table, key, id) = ("journalEntryPhotoImage", "photoId", photoId.description)
        case let .companion(companionId, _): (table, key, id) = ("companionPhoto", "companionId", companionId.description)
        case let .unsaved(data): return data
        }
        return try writer.read { db in
            try Data.fetchOne(db, sql: "SELECT image FROM \"\(table)\" WHERE \"\(key)\" = ?", arguments: [id])
        }
    }
}

/// A photo decoded through `PhotoImages`: drawn at once when it is cached, else `placeholder`
/// until it loads. `placeholder` is told whether there is nothing to load (no source, or
/// bytes that are gone), so a view can tell "still loading" from "no picture".
struct PhotoView<Content: View, Placeholder: View>: View {
    let request: PhotoRequest?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: (_ isMissing: Bool) -> Placeholder

    @Environment(PhotoImages.self) private var images
    /// What this view loaded, held here too in case the cache lets go of it.
    @State private var loaded: (request: PhotoRequest, image: UIImage)?
    @State private var missing: PhotoRequest?

    var body: some View {
        if let request, let image = images.cached(request) ?? (loaded?.request == request ? loaded?.image : nil) {
            content(Image(uiImage: image))
        } else {
            placeholder(request == nil || missing == request)
                .task(id: request) {
                    guard let request else { return }
                    if let image = await images.image(request) {
                        loaded = (request, image)
                    } else {
                        missing = request
                    }
                }
        }
    }
}

extension PhotoView where Content == AnyView {
    /// Fills its frame with the photo, like `scaledToFill`, cropped to the frame.
    init(_ request: PhotoRequest?, @ViewBuilder placeholder: @escaping (_ isMissing: Bool) -> Placeholder) {
        self.init(request: request, content: { image in
            AnyView(Color.clear.overlay { image.resizable().scaledToFill() }.clipped())
        }, placeholder: placeholder)
    }
}
