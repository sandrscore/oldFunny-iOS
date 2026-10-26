import Foundation

/// Visibility shared by the two Android observers. Loading media qualifies for
/// Subscriptions04, while Featured requires rendered pixels and a later timer.
public struct ReadVisibility: Equatable, Sendable {
    public var settled: Bool, foreground: Bool, windowVisible: Bool, mediaPanel: Bool
    public var drawerOpen: Bool, advertisement: Bool, rendered: Bool
    public init(settled: Bool, foreground: Bool, windowVisible: Bool, mediaPanel: Bool,
                drawerOpen: Bool, advertisement: Bool, rendered: Bool) {
        self.settled = settled; self.foreground = foreground; self.windowVisible = windowVisible
        self.mediaPanel = mediaPanel; self.drawerOpen = drawerOpen; self.advertisement = advertisement; self.rendered = rendered
    }
    public func qualifies(for feed: Feed) -> Bool {
        guard settled, foreground, windowVisible, mediaPanel, !drawerOpen, !advertisement else { return false }
        switch feed { case .featured: return rendered; case .subscriptions: return true; case .collective: return false }
    }
}

/// Exactly FeaturedReads.Exposure's continuous 1800ms interval. Visibility loss,
/// another account/post or a backwards clock starts a fresh interval.
public struct FeaturedReadExposure: Sendable {
    public static let durationMilliseconds: Int64 = 1800
    private var id: String?, scope: String?, since: Int64 = 0, reported = false
    public init() {}
    public mutating func reset() { id = nil; scope = nil; reported = false }
    public mutating func sample(postID: String, scope: String?, now: Int64, visible: Bool) -> Bool {
        guard visible, ReadLedger.validID(postID), let scope else { reset(); return false }
        if id != postID || self.scope != scope || now < since {
            id = postID; self.scope = scope; since = now; reported = false
        }
        let elapsed = now.subtractingReportingOverflow(since)
        guard !reported, elapsed.overflow || elapsed.partialValue >= Self.durationMilliseconds else { return false }
        reported = true; return true
    }
}

/// FIFO seen/pending order, bounds and CSV persistence match FeaturedReads.Ledger.
/// Storage/session ownership belongs to the account-scoped coordinator; this
/// value contains IDs only and cannot persist a credential.
public struct ReadLedger: Equatable, Sendable {
    public static let historyLimit = 2048, batchLimit = 30
    public private(set) var seen: [String], pending: [String]
    public init(savedSeen: String? = nil, savedPending: String? = nil) {
        seen = Self.load(savedSeen); pending = Self.load(savedPending)
        var known = Set(seen)
        for id in pending where known.insert(id).inserted { seen.append(id) }
        Self.trim(&seen)
    }
    public static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 80 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }
    private static func load(_ text: String?) -> [String] {
        guard let text, text.utf16.count <= historyLimit * 81 else { return [] }
        var ids = [String](), known = Set<String>()
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let id = String(part)
            if validID(id), known.insert(id).inserted { ids.append(id) }
        }
        trim(&ids); return ids
    }
    private static func trim(_ ids: inout [String]) {
        if ids.count > historyLimit { ids.removeFirst(ids.count - historyLimit) }
    }
    @discardableResult public mutating func viewed(_ id: String) -> Bool {
        guard Self.validID(id), !seen.contains(id) else { return false }
        seen.append(id); if !pending.contains(id) { pending.append(id) }
        Self.trim(&seen); Self.trim(&pending); return true
    }
    public var batch: [String] { Array(pending.prefix(Self.batchLimit)) }
    public mutating func acknowledged(_ ids: [String]) { let accepted = Set(ids); pending.removeAll { accepted.contains($0) } }
    public var savedSeen: String { seen.joined(separator: ",") }
    public var savedPending: String { pending.joined(separator: ",") }
}

/// SubscriptionsReads04.Progress: unchanged server counters retain local credit;
/// server drops retire matching credit so acknowledgement cannot decrement twice.
public struct SubscriptionUnreadProgress: Equatable, Sendable {
    public private(set) var server = -1, credit = 0
    public init(saved: String? = nil) {
        guard let saved else { return }
        let parts = saved.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let count = Int32(parts[0]), let read = Int32(parts[1]),
              count >= -1, read >= 0, count < 0 || read <= count else { return }
        server = Int(count); credit = Int(read)
    }
    public var remaining: Int? { server < 0 ? nil : max(0, server - credit) }
    @discardableResult public mutating func merge(server count: Int) throws -> Int {
        guard count >= 0, count <= Int32.max else { throw ClientError.invalidInput }
        if server >= 0, count < server { credit = max(0, credit - (server - count)) }
        server = count; credit = min(credit, server); return max(0, server - credit)
    }
    public mutating func viewed() {
        if server < 0 || (remaining ?? 0) > 0 { credit = min(Int(Int32.max), credit + 1) }
    }
    /// Call only after the explicit Subscriptions mark-all server success.
    /// Ordinary menu navigation does not call this method.
    public mutating func clearConfirmed() { if server < 0 { server = 0 }; credit = server }
    public var saved: String { "\(server),\(credit)" }
}
