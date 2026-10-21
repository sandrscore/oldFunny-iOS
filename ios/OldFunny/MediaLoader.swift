import UIKit
import ImageIO

private final class CachedMediaImage: NSObject {
    let image: UIImage, animated: Bool
    init(_ image: UIImage, animated: Bool) { self.image = image; self.animated = animated }
}

/// CDN downloads use a separate ephemeral session with no API Authorization,
/// installation cookies, or durable media cache.
actor MediaLoader {
    private let session: URLSession
    private let cache = NSCache<NSURL, CachedMediaImage>()
    init() {
        cache.countLimit = 48; cache.totalCostLimit = 32 * 1024 * 1024
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }
    func exportFile(_ post: Post) async throws -> URL {
        guard let url = post.mediaURL, url.scheme == "https" else { throw ClientError.unsupportedMedia }
        #if CLASSIC_UI_PREVIEW
        if url.host == "preview.invalid" { throw ClientError.unsupportedMedia }
        #endif
        let (temporary, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.intValue ?? 0
        guard (response as? HTTPURLResponse)?.statusCode == 200, size > 0, size <= 150 * 1024 * 1024 else { throw ClientError.unsupportedMedia }
        let mime = response.mimeType?.lowercased() ?? ""
        let suffix: String
        if post.isVideo { guard mime.hasPrefix("video/") || mime == "application/octet-stream" else { throw ClientError.unsupportedMedia }; suffix = "mp4" }
        else {
            switch mime { case "image/gif": suffix = "gif"; case "image/png": suffix = "png"; case "image/jpeg": suffix = "jpg"; case "image/webp": suffix = "webp"; default: throw ClientError.unsupportedMedia }
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("oldFunny-save-" + UUID().uuidString).appendingPathExtension(suffix)
        try FileManager.default.copyItem(at: temporary, to: destination); return destination
    }
    func image(_ url: URL) async throws -> UIImage {
        #if CLASSIC_UI_PREVIEW
        if url.host == "preview.invalid" { return await PreviewFixtures.image(url) }
        #endif
        guard url.scheme == "https" else { throw ClientError.unsupportedMedia }
        if let cached = cache.object(forKey: url as NSURL) { return cached.image }
        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ClientError.unsupportedMedia }
        let count = CGImageSourceGetCount(source)
        // Avatar/grid/comment previews are static bitmaps on Android. Full post
        // animation uses playableImage and its bounded frame decoder.
        let maxPixels = count > 1 ? 800 : 2400
        func frame(_ index: Int) -> UIImage? {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }
        guard let image = frame(0) else { throw ClientError.unsupportedMedia }
        cache.setObject(CachedMediaImage(image, animated: count > 1), forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }
    func playableImage(_ url: URL) async throws -> PlayableImage {
        #if CLASSIC_UI_PREVIEW
        if url.host == "preview.invalid" {
            if url.lastPathComponent == "fixture-animation.gif" {
                guard let file = Bundle.main.url(forResource: "fixture-animation", withExtension: "gif") else { throw ClientError.unsupportedMedia }
                return .gif(try GIFFrames(data: Data(contentsOf: file)))
            }
            return .still(await PreviewFixtures.image(url))
        }
        #endif
        guard url.scheme == "https" else { throw ClientError.unsupportedMedia }
        if let cached = cache.object(forKey: url as NSURL), !cached.animated { return .still(cached.image) }
        let (file, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard (response as? HTTPURLResponse)?.statusCode == 200, size > 0, size <= 30 * 1024 * 1024 else { throw ClientError.unsupportedMedia }
        let data = try Data(contentsOf: file)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ClientError.unsupportedMedia }
        if CGImageSourceGetCount(source) > 1, CGImageSourceGetType(source) as String? == "com.compuserve.gif" { return .gif(try GIFFrames(data: data)) }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw ClientError.unsupportedMedia }
        let image = UIImage(cgImage: cg)
        cache.setObject(CachedMediaImage(image, animated: false), forKey: url as NSURL, cost: cg.bytesPerRow * cg.height)
        return .still(image)
    }
}
