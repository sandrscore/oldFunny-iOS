import UIKit
import ImageIO

/// CDN downloads use a separate ephemeral session with no API Authorization,
/// installation cookies, or durable media cache.
actor MediaLoader {
    private let session: URLSession
    private let cache = NSCache<NSURL, UIImage>()
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
        if let image = cache.object(forKey: url as NSURL) { return image }
        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ClientError.unsupportedMedia }
        let count = CGImageSourceGetCount(source)
        // Bounded thumbnail decoding protects memory for tall images and GIFs.
        let maxPixels = count > 1 ? min(800, Int(sqrt(12_000_000.0 / Double(max(1, count))))) : 2400
        func frame(_ index: Int) -> UIImage? {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }
        if count > 1 && count <= 80 {
            var frames = [UIImage](), duration = 0.0
            for index in 0..<count {
                try Task.checkCancellation()
                guard let image = frame(index) else { continue }
                frames.append(image)
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                duration += max(0.02, gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1)
            }
            if !frames.isEmpty, let animated = UIImage.animatedImage(with: frames, duration: duration) { return animated }
        }
        guard let image = frame(0) else { throw ClientError.unsupportedMedia }
        cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }
}
