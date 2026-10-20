// Build helper for macOS only. Reuses the approved Android artwork when staged;
// otherwise creates a simple original oldFunny monogram for source-only builds.
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: render_ios_icon.swift input-or-dash output.png") }
let target = URL(fileURLWithPath: args[2])
let size = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
if args[1] != "-", let source = NSImage(contentsOfFile: args[1]) {
    source.draw(in: NSRect(x: 32, y: 32, width: 960, height: 960), from: .zero, operation: .sourceOver, fraction: 1)
} else {
    let text = "oF" as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 510), .foregroundColor: NSColor(calibratedRed: 1, green: 0.82, blue: 0.02, alpha: 1)]
    let measured = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (1024 - measured.width) / 2, y: (1024 - measured.height) / 2), withAttributes: attrs)
}
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
try png.write(to: target, options: .atomic)
