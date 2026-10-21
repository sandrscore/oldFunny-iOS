import Foundation
import CoreGraphics
import ImageIO

// Synthetic media only. No original application or personal image is used.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, "com.compuserve.gif" as CFString, 82, nil) else { fatalError("GIF destination unavailable") }
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for index in 0..<82 {
    let delay: Double = index == 0 ? 1.2 : index == 1 || index == 81 ? 2.4 : 0.02
    guard let context = CGContext(data: nil, width: 320, height: 320, bitsPerComponent: 8, bytesPerRow: 1280,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("GIF context unavailable") }
    let red: CGFloat = index == 0 ? 220 : 40, green: CGFloat = index == 1 ? 220 : 40, blue: CGFloat = index == 81 ? 220 : 40
    context.setFillColor(CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
    guard let image = context.makeImage() else { fatalError("GIF frame unavailable") }
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination), let source = CGImageSourceCreateWithURL(output as CFURL, nil), CGImageSourceGetCount(source) == 82 else { fatalError("GIF fixture did not retain every frame") }
for (index, expected) in [(0, 1.2), (1, 2.4), (81, 2.4)] {
    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
    let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0
    guard abs(delay - expected) < 0.01 else { fatalError("GIF delay metadata changed") }
}
let global = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
let first = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
let metadata: [String: Any] = ["frames": CGImageSourceGetCount(source),
    "global_width": (global?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0,
    "global_height": (global?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0,
    "first_width": (first?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0,
    "first_height": (first?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0]
print(String(decoding: try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), as: UTF8.self))
