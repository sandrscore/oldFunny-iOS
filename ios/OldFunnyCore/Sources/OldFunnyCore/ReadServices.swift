import Foundation

/// The persistent key is opaque; the authorization marker is transient and is
/// never encoded into read history. A token rotation invalidates old read work.
public struct ReadContext: Equatable, Sendable {
    public let key: String, epoch: UUID, signedIn: Bool, authorizationMarker: String
    public init(key: String, epoch: UUID, signedIn: Bool, authorizationMarker: String) {
        self.key = key; self.epoch = epoch; self.signedIn = signedIn; self.authorizationMarker = authorizationMarker
    }
}
public protocol ReadBackend: Sendable {
    func readContext() async -> ReadContext
    func acknowledgeReads(_ ids: [String], feed: Feed, context: ReadContext) async throws
    func unreadSubscriptions(context: ReadContext) async throws -> Int
    func clearSubscriptionReads(context: ReadContext) async throws
    func readPage(_ feed: Feed, next: String?, context: ReadContext) async throws -> PostPage
}

public struct SavedReadState: Codable, Equatable, Sendable {
    public var version = 1
    public var featuredSeen = "", featuredPending = "", subscriptionsSeen = "", subscriptionsPending = ""
    public var subscriptionsProgress = "-1,0", counterDirty = false
    public init() {}
    public var featured: ReadLedger {
        get { ReadLedger(savedSeen: featuredSeen, savedPending: featuredPending) }
        set { featuredSeen = newValue.savedSeen; featuredPending = newValue.savedPending }
    }
    public var subscriptions: ReadLedger {
        get { ReadLedger(savedSeen: subscriptionsSeen, savedPending: subscriptionsPending) }
        set { subscriptionsSeen = newValue.savedSeen; subscriptionsPending = newValue.savedPending }
    }
    public var progress: SubscriptionUnreadProgress {
        get { SubscriptionUnreadProgress(saved: subscriptionsProgress) }
        set { subscriptionsProgress = newValue.saved }
    }
}
public protocol ReadStateStore: Sendable {
    func load(key: String) throws -> SavedReadState?
    func save(_ state: SavedReadState, key: String) throws
}

/// Atomic, private application-support files. Only bounded IDs and unread
/// progress are encoded; credentials and raw account identifiers have no fields.
public struct FileReadStateStore: ReadStateStore, Sendable {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func file(_ key: String) throws -> URL {
        guard key.utf8.count == 40, key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw ClientError.invalidInput }
        return directory.appendingPathComponent(key + ".json", isDirectory: false)
    }
    public func load(key: String) throws -> SavedReadState? {
        let file = try file(key)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= 1024 * 1024 else { throw ClientError.malformedResponse }
        let state = try JSONDecoder().decode(SavedReadState.self, from: Data(contentsOf: file))
        guard state.version == 1 else { throw ClientError.malformedResponse }
        return state
    }
    public func save(_ state: SavedReadState, key: String) throws {
        let file = try file(key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(state)
        guard data.count <= 1024 * 1024 else { throw ClientError.invalidInput }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        #endif
        var excluded = file; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }
}

/// Shared worker serialization preserves ordering between read acknowledgements,
/// counter refresh, explicit clearing and feed reads despite actor reentrancy.
public actor ReadCoordinator {
    private let backend: any ReadBackend, store: any ReadStateStore
    private var selected: ReadContext?, state = SavedReadState()
    private var clearFlight: (id: UUID, context: ReadContext, task: Task<Void, Error>)?
    private var busy = false
    private struct Waiting { let id: UUID; let continuation: CheckedContinuation<Void, Error> }
    private var waiting = [Waiting]()
    public init(backend: any ReadBackend, store: any ReadStateStore) { self.backend = backend; self.store = store }
    private func prepare() async throws -> ReadContext {
        let current = await backend.readContext()
        if selected != current {
            let restored = try store.load(key: current.key) ?? SavedReadState()
            state = restored; selected = current
        }
        return current
    }
    private func check(_ context: ReadContext) async throws {
        let live = await backend.readContext()
        guard selected == context, live == context else { throw ClientError.sessionChanged }
        try Task.checkCancellation()
    }
    private func persist(_ updated: SavedReadState, context: ReadContext) throws {
        guard selected == context else { throw ClientError.sessionChanged }
        try store.save(updated, key: context.key); state = updated
    }
    private func acquire() async throws {
        try Task.checkCancellation()
        if !busy { busy = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiting.append(Waiting(id: id, continuation: continuation)) }
            }
        } onCancel: { Task { await self.cancelWait(id) } }
    }
    private func cancelWait(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }
    private func release() {
        if waiting.isEmpty { busy = false }
        else { waiting.removeFirst().continuation.resume() }
    }
    public func snapshot() async throws -> SavedReadState { _ = try await prepare(); return state }
    public func currentSnapshot() async throws -> (ReadContext, SavedReadState) {
        let context = try await prepare(); try await check(context); return (context, state)
    }
    public func context() async throws -> ReadContext { try await prepare() }
    @discardableResult public func viewed(_ id: String, feed: Feed, expected: ReadContext? = nil) async throws -> Bool {
        let context = try await prepare()
        guard expected == nil || expected == context else { throw ClientError.sessionChanged }
        try await check(context)
        guard feed == .featured || (feed == .subscriptions && context.signedIn) else { return false }
        var updated = state, ledger = feed == .featured ? state.featured : state.subscriptions
        guard ledger.viewed(id) else { return false }
        if feed == .featured { updated.featured = ledger }
        else { updated.subscriptions = ledger; var progress = updated.progress; progress.viewed(); updated.progress = progress; updated.counterDirty = true }
        // Save before any caller can schedule an acknowledgement.
        try persist(updated, context: context); return true
    }
    /// Returns true when another bounded worker job is needed. A failed request
    /// throws with its pending IDs and locally credited badge unchanged.
    @discardableResult public func flush() async throws -> Bool {
        let context = try await prepare(); try await acquire(); defer { release() }
        try await check(context); return try await flushLocked(context)
    }
    private func flushLocked(_ context: ReadContext) async throws -> Bool {
        for feed in [Feed.featured, .subscriptions] {
            if feed == .subscriptions && !context.signedIn { continue }
            for _ in 0..<4 {
                try await check(context)
                let batch = (feed == .featured ? state.featured : state.subscriptions).batch
                if batch.isEmpty { break }
                try await backend.acknowledgeReads(batch, feed: feed, context: context)
                try await check(context)
                var updated = state, ledger = feed == .featured ? state.featured : state.subscriptions
                ledger.acknowledged(batch)
                if feed == .featured { updated.featured = ledger }
                else { updated.subscriptions = ledger; updated.counterDirty = true }
                try persist(updated, context: context)
            }
        }
        if context.signedIn && state.counterDirty {
            let count = try await backend.unreadSubscriptions(context: context); try await check(context)
            var updated = state, progress = updated.progress
            try progress.merge(server: count); updated.progress = progress
            if updated.subscriptions.pending.isEmpty { updated.counterDirty = false }
            try persist(updated, context: context)
        }
        return !state.featured.pending.isEmpty || (context.signedIn && !state.subscriptions.pending.isEmpty)
    }
    public func refreshCounter() async throws {
        let context = try await prepare(); guard context.signedIn else { return }
        var updated = state; updated.counterDirty = true; try persist(updated, context: context)
        _ = try await flush()
    }
    public func clearSubscriptions(expected: ReadContext? = nil) async throws {
        let context = try await prepare(); guard context.signedIn else { throw ClientError.signInRequired }
        guard expected == nil || expected == context else { throw ClientError.sessionChanged }
        if let flight = clearFlight, flight.context == context { try await flight.task.value; return }
        let id = UUID(), task = Task { try await self.performClear(context) }
        clearFlight = (id, context, task)
        defer { if clearFlight?.id == id { clearFlight = nil } }
        try await task.value
    }
    private func performClear(_ context: ReadContext) async throws {
        try await acquire(); defer { release() }; try await check(context)
        try await backend.clearSubscriptionReads(context: context); try await check(context)
        var updated = state, progress = updated.progress; progress.clearConfirmed(); updated.progress = progress
        // Explicit bulk success preserves both per-post history and pending IDs.
        try persist(updated, context: context)
    }
    public func page(_ feed: Feed, next: String? = nil) async throws -> PostPage {
        let context = try await prepare(); try await acquire(); defer { release() }; try await check(context)
        if feed != .collective {
            do { _ = try await flushLocked(context) }
            catch is CancellationError { throw CancellationError() }
            catch { try await check(context) } // Retain offline pending IDs; feed browsing may still work.
        }
        var cursor = next, cursors = Set<String>(); if let next { cursors.insert(next) }
        for index in 0..<6 {
            let page = try await backend.readPage(feed, next: cursor, context: context); try await check(context)
            guard feed == .featured else { return page }
            let seen = Set(state.featured.seen); var unique = Set<String>()
            let posts = page.posts.filter { !seen.contains($0.id) && unique.insert($0.id).inserted }
            var following = page.paging.next
            if let value = following, !cursors.insert(value).inserted { following = nil }
            let result = PostPage(posts: posts, paging: try Paging(next: following))
            if !posts.isEmpty || page.posts.isEmpty || following == nil || index == 5 { return result }
            cursor = following
        }
        throw ClientError.malformedResponse
    }
}

extension APIClient: ReadBackend {
    public func acknowledgeReads(_ ids: [String], feed: Feed, context: ReadContext) async throws {
        guard readContext() == context else { throw ClientError.sessionChanged }
        try await markRead(ids: ids, feed: feed, session: context.epoch)
        guard readContext() == context else { throw ClientError.sessionChanged }
    }
    public func readPage(_ feed: Feed, next: String?, context: ReadContext) async throws -> PostPage {
        guard readContext() == context else { throw ClientError.sessionChanged }
        let page = try await self.feed(feed, next: next)
        guard readContext() == context else { throw ClientError.sessionChanged }; return page
    }
    public func unreadSubscriptions(context: ReadContext) async throws -> Int { try await subscriptionUnread(session: context) }
    public func clearSubscriptionReads(context: ReadContext) async throws { try await markSubscriptionsViewed(session: context) }
}
