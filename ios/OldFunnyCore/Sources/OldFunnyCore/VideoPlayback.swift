import Foundation

/// The seek queue in Android revival.VideoControls.Session, independent of a
/// player implementation. A completion is tied to one request, never a page's
/// latest seek, and cannot restart an inactive page.
public struct VideoSeekState: Sendable {
    public struct Request: Equatable, Sendable {
        public let id: UInt64
        public let milliseconds: Int64
    }
    public enum Command: Equatable, Sendable { case pause, seek(Request), play }
    public private(set) var dragging = false
    public private(set) var inFlight: Request?
    public private(set) var pending: Int64?
    public private(set) var position: Int64 = 0
    private var resumeAfterSeek = false, serial: UInt64 = 0
    public init() {}
    public var blocksStart: Bool { dragging || inFlight != nil }
    public static func hasScrubber(duration: Int64) -> Bool { duration > 10_000 }
    public static func target(fraction: Double, duration: Int64) -> Int64 {
        guard fraction.isFinite, duration > 0 else { return 0 }
        if fraction >= 1 { return duration - 1 }
        if fraction <= 0 { return 0 }
        let value = Double(duration) * fraction
        if value >= Double(Int64.max) { return duration - 1 }
        return min(duration - 1, max(0, Int64(value)))
    }
    public static func timestamp(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds) / 1000
        return String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
    }
    public mutating func begin(fraction: Double, duration: Int64, playing: Bool,
                               manuallyPaused: Bool, current: Bool, ready: Bool) -> [Command] {
        guard current, ready, Self.hasScrubber(duration: duration), !dragging, inFlight == nil else { return [] }
        resumeAfterSeek = playing && !manuallyPaused; dragging = true
        return [.pause] + request(fraction: fraction, duration: duration, current: current, ready: ready)
    }
    public mutating func request(fraction: Double, duration: Int64, current: Bool, ready: Bool) -> [Command] {
        guard dragging, current, ready else { return [] }
        position = Self.target(fraction: fraction, duration: duration); pending = position
        return dispatch(current: current, ready: ready)
    }
    public mutating func release(current: Bool, ready: Bool, manuallyPaused: Bool) -> [Command] {
        dragging = false
        if !current { resumeAfterSeek = false }
        return inFlight == nil && pending == nil ? finish(current: current, ready: ready, manuallyPaused: manuallyPaused) : []
    }
    public mutating func completed(_ id: UInt64, finished: Bool, current: Bool,
                                   ready: Bool, manuallyPaused: Bool) -> [Command] {
        guard inFlight?.id == id else { return [] }
        inFlight = nil
        guard finished else { pending = nil; dragging = false; resumeAfterSeek = false; return [] }
        if pending != nil { return dispatch(current: current, ready: ready) }
        return dragging ? [] : finish(current: current, ready: ready, manuallyPaused: manuallyPaused)
    }
    public mutating func suspend() {
        dragging = false; pending = nil; resumeAfterSeek = false
    }
    public mutating func returned(manuallyPaused: Bool) {
        // A new explicit page activation may restore play intent while a prior
        // seek finishes. Merely receiving a completion never makes a page current.
        if inFlight != nil { resumeAfterSeek = !manuallyPaused }
    }
    /// Native looping and enabling sound while playing restart at zero through
    /// the same serialized queue, never a second competing seek operation.
    public mutating func restart(current: Bool, ready: Bool, manuallyPaused: Bool) -> [Command] {
        guard current, ready, !manuallyPaused, !blocksStart else { return [] }
        resumeAfterSeek = true; position = 0; pending = 0
        return [.pause] + dispatch(current: current, ready: ready)
    }
    public mutating func reset() {
        serial &+= 1; dragging = false; inFlight = nil; pending = nil; resumeAfterSeek = false; position = 0
    }
    private mutating func dispatch(current: Bool, ready: Bool) -> [Command] {
        guard current, ready else { pending = nil; resumeAfterSeek = false; return [] }
        guard inFlight == nil, let pending else { return [] }
        self.pending = nil; serial &+= 1
        let request = Request(id: serial, milliseconds: pending); inFlight = request
        return [.seek(request)]
    }
    private mutating func finish(current: Bool, ready: Bool, manuallyPaused: Bool) -> [Command] {
        let resume = resumeAfterSeek && current && ready && !manuallyPaused
        resumeAfterSeek = false; return resume ? [.play] : []
    }
}
