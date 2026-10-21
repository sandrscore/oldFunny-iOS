import UIKit
import ImageIO

enum PlayableImage {
    case still(UIImage)
    case gif(GIFFrames)
}

/// Compressed source plus at most three decoded frames. The decoder runs on
/// this actor, never on the main display-link callback.
actor GIFFrames {
    nonisolated let timeline: GIFTimeline
    private let source: CGImageSource, maxPixels: Int
    private var frames = [Int: UIImage](), order = [Int]()
    init(data: Data) throws {
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "com.compuserve.gif",
              CGImageSourceGetCount(source) > 1, CGImageSourceGetCount(source) <= 10000 else { throw ClientError.unsupportedMedia }
        self.source = source
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        guard width > 0, height > 0, width <= 30000, height <= 100000 else { throw ClientError.unsupportedMedia }
        maxPixels = max(1, Int(min(2048, max(width, height) * min(1, sqrt(2_000_000 / (width * height))))))
        var delays = [Double]()
        for index in 0..<CGImageSourceGetCount(source) {
            if index % 128 == 0 { try Task.checkCancellation() }
            let frame = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            delays.append((gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1)
        }
        // Android video/c$h uses GifVideo.readFrameLooped for the gallery.
        // Match its looping playback rather than stopping on a source loop tag.
        timeline = try GIFTimeline(delays: delays)
    }
    func frame(_ index: Int) throws -> UIImage {
        try Task.checkCancellation()
        guard timeline.ends.indices.contains(index) else { throw ClientError.unsupportedMedia }
        if let cached = frames[index] { order.removeAll { $0 == index }; order.append(index); return cached }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCache: false
        ] as CFDictionary) else { throw ClientError.unsupportedMedia }
        try Task.checkCancellation()
        let frame = UIImage(cgImage: image); frames[index] = frame; order.append(index)
        while order.count > 3 { frames.removeValue(forKey: order.removeFirst()) }
        return frame
    }
    func trim(keeping index: Int?) { frames = frames.filter { $0.key == index }; order = order.filter { $0 == index } }
}

@MainActor
private final class GIFDisplayLinkTarget: NSObject {
    weak var owner: GIFPlayback?
    @objc func tick(_ link: CADisplayLink) { owner?.refresh() }
}

/// Keeps phase through retained panels and pages, without retaining every frame
/// or tying animation speed to the decoder's completion rate.
@MainActor
final class GIFPlayback {
    var isCurrent: (() -> Bool)?, onFailure: (() -> Void)?
    private weak var image: UIImageView?
    private let asset: GIFFrames, target = GIFDisplayLinkTarget()
    private var clock = GIFClock(), link: CADisplayLink?, task: Task<Void, Never>?
    private var generation = UUID(), displayed: Int?, loading = false, failed = false
    private var observers = [NSObjectProtocol]()
    #if CLASSIC_UI_PREVIEW
    private var pixel = "unavailable"
    #endif
    init(asset: GIFFrames, image: UIImageView) {
        self.asset = asset; self.image = image; target.owner = self
        image.accessibilityLabel = "Animated post"
        let link = CADisplayLink(target: target, selector: #selector(GIFDisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common); link.isPaused = true; self.link = link
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.suspend() } })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self else { return }; await self.asset.trim(keeping: self.displayed) }
        })
        #if CLASSIC_UI_PREVIEW
        image.isAccessibilityElement = true; image.accessibilityIdentifier = "post-gif"
        #endif
    }
    deinit { link?.invalidate(); task?.cancel(); observers.forEach { NotificationCenter.default.removeObserver($0) } }
    private var current: Bool { image?.window != nil && UIApplication.shared.applicationState == .active && isCurrent?() == true }
    func suspend() {
        clock.pause(at: CACurrentMediaTime()); link?.isPaused = true; task?.cancel(); task = nil; loading = false; generation = UUID()
        let asset = asset, frame = displayed; Task { await asset.trim(keeping: frame) }
        trace()
    }
    func refresh() {
        guard !failed, current else { if clock.running { suspend() }; return }
        clock.resume(at: CACurrentMediaTime()); link?.isPaused = false
        let elapsed = clock.elapsed(at: CACurrentMediaTime()), frame = asset.timeline.frame(at: elapsed)
        if asset.timeline.finished(at: elapsed), displayed == frame { link?.isPaused = true; clock.pause(at: CACurrentMediaTime()) }
        guard displayed != frame, !loading else { trace(); return }
        loading = true; let owner = generation
        task = Task { [weak self, asset] in
            do {
                let bitmap = try await asset.frame(frame); try Task.checkCancellation()
                guard let self, owner == generation, current else { return }
                image?.image = bitmap; displayed = frame; loading = false; task = nil
                #if CLASSIC_UI_PREVIEW
                pixel = sampledPixel(bitmap)
                #endif
                trace()
            } catch is CancellationError {} catch {
                guard let self, owner == generation else { return }; loading = false; failed = true; suspend(); onFailure?()
            }
        }
    }
    private func trace() {
        #if CLASSIC_UI_PREVIEW
        let elapsed = Int(clock.elapsed(at: CACurrentMediaTime()) * 1000)
        image?.accessibilityValue = "frame=\(displayed ?? -1); elapsed=\(elapsed); count=\(asset.timeline.ends.count); duration=\(Int(asset.timeline.duration * 1000)); running=\(clock.running); pixel=\(pixel)"
        #endif
    }
    #if CLASSIC_UI_PREVIEW
    private func sampledPixel(_ image: UIImage) -> String {
        guard let cg = image.cgImage else { return "unavailable" }
        var bytes = [UInt8](repeating: 0, count: 4)
        let valid = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return true
        }
        return valid ? "\(bytes[0]),\(bytes[1]),\(bytes[2])" : "unavailable"
    }
    #endif
}
