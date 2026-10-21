import Foundation

/// A frame schedule, without repeated UIImage frames or equalized delays.
/// Frame lookup is logarithmic, including long animations and elapsed jumps.
public struct GIFTimeline: Equatable, Sendable {
    public let ends: [Double]
    public let duration: Double
    /// nil means infinite; a positive value is the number of complete plays.
    public let plays: Int?
    public init(delays: [Double], plays: Int? = nil) throws {
        guard !delays.isEmpty, delays.count <= 10000, plays == nil || plays! > 0 else { throw ClientError.unsupportedMedia }
        var total = 0.0, boundaries = [Double]()
        for delay in delays {
            // Android video/c$h schedules max(20ms, timestamp delta / speed).
            // Missing/invalid zero durations use 100ms rather than a busy loop.
            total += delay.isFinite && delay > 0 ? max(0.02, delay) : 0.1
            guard total.isFinite, total < 86400 else { throw ClientError.unsupportedMedia }
            boundaries.append(total)
        }
        ends = boundaries; duration = total; self.plays = plays
    }
    public func frame(at elapsed: Double) -> Int {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        if let plays, elapsed / duration >= Double(plays) { return ends.count - 1 }
        let time = elapsed.truncatingRemainder(dividingBy: duration)
        var lower = 0, upper = ends.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if time < ends[middle] { upper = middle } else { lower = middle + 1 }
        }
        return min(lower, ends.count - 1)
    }
    public func finished(at elapsed: Double) -> Bool { plays.map { elapsed.isFinite && elapsed / duration >= Double($0) } ?? false }
}

/// Active elapsed time only. Pane/page/background pauses cannot advance the
/// animation, and duplicate lifecycle notifications cannot reset its phase.
public struct GIFClock: Sendable {
    private var accumulated = 0.0
    private var started: Double?
    public init() {}
    public var running: Bool { started != nil }
    public mutating func resume(at now: Double) { if started == nil && now.isFinite { started = now } }
    public mutating func pause(at now: Double) { accumulated = elapsed(at: now); started = nil }
    public func elapsed(at now: Double) -> Double {
        guard let started, now.isFinite else { return accumulated }
        return accumulated + max(0, now - started)
    }
}
