// Generates synthetic media in CI only. No source clip, credentials or artwork.
// Sparse keyframes make an inaccurate seek visible to the real player tests.
import AppKit
import AVFoundation
import CoreVideo
import Foundation

guard CommandLine.arguments.count == 3 else { fatalError("Usage: render_ios_video_fixture.swift output.mp4 audio.wav") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let silent = destination.deletingLastPathComponent().appendingPathComponent("fixture-silent.mp4")
try? FileManager.default.removeItem(at: silent)
try? FileManager.default.removeItem(at: destination)
let writer = try AVAssetWriter(outputURL: silent, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 250_000, AVVideoMaxKeyFrameIntervalKey: 150,
        AVVideoMaxKeyFrameIntervalDurationKey: 10, AVVideoExpectedSourceFrameRateKey: 15]
])
input.expectsMediaDataInRealTime = false
let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360,
    kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
])
writer.add(input)
guard writer.startWriting() else { throw writer.error! }
writer.startSession(atSourceTime: .zero)
for frame in 0..<186 { // 12.4s at 15fps
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed { throw writer.error! }
        Thread.sleep(forTimeInterval: 0.001)
    }
    var raw: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &raw) == kCVReturnSuccess, let buffer = raw else { fatalError("No pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 640, height: 360,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    context.setFillColor(CGColor(gray: 0.2, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
    context.setFillColor(CGColor(gray: 0.7, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: Double(frame + 1) / 186 * 640, height: 30))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let text = String(format: "OFFLINE  %05.2fs", Double(frame) / 15) as NSString
    text.draw(at: CGPoint(x: 65, y: 155), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 42, weight: .medium), .foregroundColor: NSColor.white])
    NSGraphicsContext.restoreGraphicsState(); CVPixelBufferUnlockBaseAddress(buffer, [])
    guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 15)) else { throw writer.error! }
}
input.markAsFinished(); writer.endSession(atSourceTime: CMTime(value: 124, timescale: 10))
let done = DispatchSemaphore(value: 0); writer.finishWriting { done.signal() }; done.wait()
guard writer.status == .completed else { throw writer.error! }
// Convert the synthesized PCM tone to AAC first, then passthrough both tracks.
// Re-encoding the video here would silently remove the sparse-keyframe fixture.
let audioSource = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[2]))
let audioURL = destination.deletingLastPathComponent().appendingPathComponent("fixture-tone.m4a")
try? FileManager.default.removeItem(at: audioURL)
let audioExport = AVAssetExportSession(asset: audioSource, presetName: AVAssetExportPresetAppleM4A)!
audioExport.outputURL = audioURL; audioExport.outputFileType = .m4a
let audioDone = DispatchSemaphore(value: 0); audioExport.exportAsynchronously { audioDone.signal() }; audioDone.wait()
guard audioExport.status == .completed else { throw audioExport.error! }
let video = AVURLAsset(url: silent), audio = AVURLAsset(url: audioURL)
let composition = AVMutableComposition()
let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
let range = CMTimeRange(start: .zero, duration: CMTime(value: 124, timescale: 10))
try videoTrack.insertTimeRange(range, of: video.tracks(withMediaType: .video)[0], at: .zero)
try audioTrack.insertTimeRange(range, of: audio.tracks(withMediaType: .audio)[0], at: .zero)
let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
export.outputURL = destination; export.outputFileType = .mp4
let exported = DispatchSemaphore(value: 0); export.exportAsynchronously { exported.signal() }; exported.wait()
guard export.status == .completed else { throw export.error! }
let checked = AVURLAsset(url: destination)
let reader = try AVAssetReader(asset: checked)
let samples = AVAssetReaderTrackOutput(track: checked.tracks(withMediaType: .video)[0], outputSettings: nil)
reader.add(samples); reader.startReading()
var syncTimes = [Double]()
while let sample = samples.copyNextSampleBuffer() {
    let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
    if attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true { syncTimes.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds) }
}
guard reader.status == .completed, zip(syncTimes, syncTimes.dropFirst()).contains(where: { $1 - $0 >= 8 }) else { fatalError("Fixture lost its sparse keyframes: \(syncTimes)") }
try? FileManager.default.removeItem(at: silent)
try? FileManager.default.removeItem(at: audioURL)
print("Generated offline 12.4s H264/AAC fixture; keyframes: \(syncTimes)")
