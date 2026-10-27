import UIKit

@MainActor
final class TagBrowser: PostGallerySource {
    let app: AppContext, feed: TagFeed
    var nickname: String { "#" + feed.tag }
    var postSource: String { feed.source }
    var profileOwnerID: String? { nil }
    var galleryIdentifier: String { "tag-gallery" }
    private var pages = ProfilePages()
    var posts: [Post] { pages.posts }
    var loaded: Bool { pages.loaded }
    var hasNext: Bool { pages.next != nil }
    private(set) var loading = false, revision: UInt64 = 0
    private(set) var error: Error?
    var onGridUpdate: (() -> Void)?, onViewerUpdate: (() -> Void)?
    private var active = false, generation = UUID(), task: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    init(app: AppContext, feed: TagFeed) {
        self.app = app; self.feed = feed
        observer = NotificationCenter.default.addObserver(forName: .oldFunnyAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }; cancel(); pages = ProfilePages(); error = nil; revision &+= 1; notify()
                if active { load(replacing: true) }
            }
        }
    }
    deinit { task?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    func setActive(_ value: Bool, consumeRefresh: Bool = true) {
        active = value
        if value { if !loaded { load(replacing: true) } else if posts.isEmpty && hasNext && error == nil { loadNext() } }
        else { cancel() }
    }
    private func cancel() { task?.cancel(); task = nil; generation = UUID(); loading = false }
    func pinsChanged() {}
    func refresh() { load(replacing: true, explicit: true) }
    func retry() { load(replacing: !loaded, explicit: true) }
    func loadNext() { load(replacing: !loaded) }
    private func notify() { onGridUpdate?(); onViewerUpdate?() }
    private func load(replacing: Bool, explicit: Bool = false) {
        guard active, !loading, explicit || error == nil, replacing || hasNext else { return }
        loading = true; error = nil; notify(); let owner = generation, cursor = replacing ? nil : pages.next
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if owner == generation {
                    loading = false; task = nil; notify()
                    if active && posts.isEmpty && hasNext && error == nil { Task { @MainActor [weak self] in await Task.yield(); self?.loadNext() } }
                }
            }
            do {
                let epoch = await app.api.sessionEpoch(), result = try await app.api.tagFeed(feed, next: cursor)
                try Task.checkCancellation(); guard owner == generation, epoch == (await app.api.sessionEpoch()) else { return }
                try pages.apply(result, replacing: replacing); revision &+= 1
            } catch is CancellationError {} catch { if owner == generation { self.error = error } }
        }
    }
}
