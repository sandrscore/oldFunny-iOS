import UIKit
import ImageIO

/// PictureComments' independent 10MiB bitmap cache, two workers, bounded queue,
/// 8MiB compressed payload and power-of-two decode sampling to <=1024 pixels.
/// It never uses the API session or the full-post animation cache.
actor CommentThumbnailLoader {
    private struct Waiting {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private let session: URLSession
    private struct Cached { let image: UIImage; let cost: Int }
    private var cache = [URL: Cached](), order = [URL](), cacheCost = 0
    private let cacheLimit = 10 * 1024 * 1024
    private var active = 0, waiting = [Waiting]()
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }
    private func acquire() async throws {
        try Task.checkCancellation()
        if active < 2 { active += 1; return }
        guard waiting.count < 64 else { throw ClientError.unsupportedMedia }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiting.append(Waiting(id: id, continuation: continuation)) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }
    private func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().continuation.resume() }
    }
    private func cached(_ url: URL) -> UIImage? {
        guard let entry = cache[url] else { return nil }
        order.removeAll { $0 == url }; order.append(url); return entry.image
    }
    private func retain(_ image: UIImage, url: URL, cost: Int) {
        guard cost <= cacheLimit else { return }
        if let old = cache.removeValue(forKey: url) { cacheCost -= old.cost; order.removeAll { $0 == url } }
        while cacheCost + cost > cacheLimit, !order.isEmpty {
            let removed = order.removeFirst()
            if let old = cache.removeValue(forKey: removed) { cacheCost -= old.cost }
        }
        cache[url] = Cached(image: image, cost: cost); cacheCost += cost; order.append(url)
    }
    func image(_ url: URL, userAgent: String) async throws -> UIImage {
        try Task.checkCancellation()
        // HTTP-only legacy thumbnails still require a transport-policy pass;
        // retain their cards/open routes rather than silently dropping them.
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { throw ClientError.unsupportedMedia }
        if let image = cached(url) { return image }
        try await acquire(); defer { release() }; try Task.checkCancellation()
        if let image = cached(url) { return image }
        #if CLASSIC_UI_PREVIEW
        if url.host == "preview.invalid" {
            if url.lastPathComponent == "failed-preview" { throw ClientError.unsupportedMedia }
            // Only data acquisition is fabricated. Exercise the real ImageIO
            // decoder, sampling, worker permits and cache used by comment cards.
            let bitmap = await PreviewFixtures.image(url)
            guard let data = bitmap.pngData(), data.count <= 8 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ClientError.unsupportedMedia }
            return try decode(source, url: url)
        }
        #endif
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/webp,image/*", forHTTPHeaderField: "Accept")
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard (response as? HTTPURLResponse)?.statusCode == 200, size > 0, size <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { throw ClientError.unsupportedMedia }
        return try decode(source, url: url)
    }
    private func decode(_ source: CGImageSource, url: URL) throws -> UIImage {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ClientError.unsupportedMedia }
        var sample = 1
        while width / sample > 1024 || height / sample > 1024 { sample *= 2 }
        let maximum = max(1, max(width, height) / sample)
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary) else { throw ClientError.unsupportedMedia }
        try Task.checkCancellation()
        let image = UIImage(cgImage: cg)
        retain(image, url: url, cost: cg.bytesPerRow * cg.height)
        return image
    }
}
