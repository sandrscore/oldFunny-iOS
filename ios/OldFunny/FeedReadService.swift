import UIKit

/// Application-owned read worker. Visibility belongs to the displayed feed;
/// durable queueing and request ordering belong to ReadCoordinator.
@MainActor
final class FeedReadService {
    let coordinator: ReadCoordinator
    private(set) var currentContext: ReadContext?
    private(set) var unreadSubscriptions: Int?
    private(set) var clearing = false
    private var worker: Task<Void, Never>?, retry: Task<Void, Never>?
    private var requested = false, counterRequested = false, active = false
    private var observers = [NSObjectProtocol]()
    init(api: APIClient, directory: URL) {
        coordinator = ReadCoordinator(backend: api, store: FileReadStateStore(directory: directory))
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification, .oldFunnyAccountChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let name = notification.name
                Task { @MainActor [weak self] in self?.lifecycle(name) }
            })
        }
    }
    deinit { worker?.cancel(); retry?.cancel(); observers.forEach { NotificationCenter.default.removeObserver($0) } }
    private func lifecycle(_ name: Notification.Name) {
        if name == UIApplication.willResignActiveNotification {
            active = false; retry?.cancel(); retry = nil
            worker?.cancel(); requested = true
            // An uncertain cancelled ACK stays pending and is safe to retry.
        } else {
            active = UIApplication.shared.applicationState == .active
            retry?.cancel(); retry = nil
            if name == .oldFunnyAccountChanged { worker?.cancel(); currentContext = nil; unreadSubscriptions = nil; notify() }
            requestSync(refreshCounter: true)
        }
    }
    func activate() {
        active = UIApplication.shared.applicationState == .active
        requestSync(refreshCounter: true)
    }
    private func notify() { NotificationCenter.default.post(name: .oldFunnyReadsChanged, object: self) }
    private func publish() async throws {
        let (context, state) = try await coordinator.currentSnapshot()
        currentContext = context
        unreadSubscriptions = context.signedIn ? state.progress.remaining : nil
        notify()
    }
    func page(_ feed: Feed, next: String?) async throws -> (PostPage, ReadContext) {
        let (page, context) = try await coordinator.scopedPage(feed, next: next)
        let (live, _) = try await coordinator.currentSnapshot()
        guard context.key == live.key, context.epoch == live.epoch, context.signedIn == live.signedIn else { throw ClientError.sessionChanged }
        try await publish()
        // A successful foreground GET may have refreshed the token or restored
        // connectivity since the failed worker. Retry its durable IDs now.
        retry?.cancel(); retry = nil
        requestSync()
        return (page, live)
    }
    func viewed(_ id: String, feed: Feed, context: ReadContext) async throws {
        if try await coordinator.viewed(id, feed: feed, expected: context) {
            try await publish() // The badge changes after durable save, before ACK.
            requestSync()
        }
    }
    func requestSync(refreshCounter: Bool = false) {
        requested = true; counterRequested = counterRequested || refreshCounter
        guard active, worker == nil, retry == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            var failed = false
            while active && requested && !Task.isCancelled {
                requested = false
                let refresh = counterRequested; counterRequested = false
                do {
                    if refresh { try await coordinator.refreshCounter() }
                    let more = try await coordinator.flush()
                    try await publish()
                    if more { requested = true }
                } catch {
                    if error as? ClientError == .sessionChanged && !Task.isCancelled {
                        // Rebind immediately after a token/account generation
                        // change; the ten-second delay is for network failures.
                        requested = true; try? await publish(); await Task.yield()
                        continue
                    }
                    failed = !Task.isCancelled; requested = true
                    // Queue and credit remain durable. Display a restored badge
                    // even when the server is unavailable.
                    try? await publish()
                    break
                }
                await Task.yield()
            }
            worker = nil
            if failed && active {
                retry = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                    guard let self else { return }; retry = nil; requestSync()
                }
            } else if active && requested { requestSync() }
        }
    }
    func clearSubscriptions(expected: ReadContext) async throws {
        guard !clearing else { return }
        let live = try await coordinator.context()
        guard live == expected else { throw ClientError.sessionChanged }
        clearing = true; notify()
        defer { clearing = false; notify() }
        try await coordinator.clearSubscriptions(expected: expected)
        let after = try await coordinator.context()
        guard after == expected else { throw ClientError.sessionChanged }
        try await publish()
    }
}

extension Notification.Name {
    static let oldFunnyReadsChanged = Notification.Name("oldFunnyReadsChanged")
}
