import UIKit

/// One source/order/cursor shared by a profile grid and its swipe gallery.
/// Criteria changes reuse scanned metadata and never fall back to an unfiltered
/// endpoint. Reads and updates are fenced by both query and account generation.
@MainActor
final class ProfileBrowser {
    let app: AppContext, userID: String
    let nickname: String, featured: Bool
    private var pages = ProfilePages()
    private(set) var posts = [Post]()
    private(set) var criteria: ProfileSearchCriteria?
    private(set) var loading = false, filtering = false
    private(set) var revision: UInt64 = 0
    private(set) var queryRevision: UInt64 = 0
    private(set) var error: Error?
    var needsRefresh = false
    var onGridUpdate: (() -> Void)?, onViewerUpdate: (() -> Void)?
    private var active = false, generation = UUID(), readGeneration = UUID()
    private var task: Task<Void, Never>?, filterTask: Task<Void, Never>?
    private var filterWork: Task<[Post], Error>?
    private var accountObserver: NSObjectProtocol?
    var hasNext: Bool { pages.next != nil }
    var loaded: Bool { pages.loaded }
    init(app: AppContext, userID: String, nickname: String, featured: Bool = false, search: Bool = false) {
        self.app = app; self.userID = userID; self.nickname = nickname; self.featured = featured
        criteria = search ? ProfileSearchCriteria() : nil
        accountObserver = NotificationCenter.default.addObserver(forName: .oldFunnyAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resetAccount() }
        }
    }
    deinit { task?.cancel(); filterTask?.cancel(); filterWork?.cancel(); if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) } }
    func setActive(_ value: Bool, consumeRefresh: Bool = true) {
        active = value
        if value {
            if needsRefresh && consumeRefresh { needsRefresh = false; load(replacing: true, explicit: true) }
            else if !pages.loaded { load(replacing: true) }
            else { continueIfSparse() }
        } else {
            task?.cancel(); task = nil; readGeneration = UUID(); loading = false
        }
    }
    private func resetAccount() {
        task?.cancel(); filterTask?.cancel(); filterWork?.cancel(); generation = UUID()
        readGeneration = UUID(); pages = ProfilePages(); posts = []; revision &+= 1; queryRevision &+= 1; loading = false; filtering = false; error = nil
        notify(); if active { load(replacing: true) }
    }
    func refresh() { load(replacing: true, explicit: true) }
    func retry() { load(replacing: !pages.loaded, explicit: true) }
    func loadNext() { load(replacing: !pages.loaded) }
    func setCriteria(_ value: ProfileSearchCriteria) {
        guard criteria != value else { return }
        task?.cancel(); filterTask?.cancel(); filterWork?.cancel(); generation = UUID(); readGeneration = UUID(); loading = false
        criteria = value; error = nil; posts = []; revision &+= 1; queryRevision &+= 1; filtering = true; notify()
        let snapshot = pages.posts, owner = generation, profile = userID
        let work = Task.detached(priority: .userInitiated) { () throws -> [Post] in
            var result = [Post]()
            for (index, post) in snapshot.enumerated() {
                if index % 128 == 0 { try Task.checkCancellation() }
                if value.matches(post, profileID: profile) { result.append(post) }
            }
            return result
        }
        filterWork = work
        filterTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await work.value
                guard owner == generation else { return }
                posts = result; revision &+= 1; filtering = false; filterWork = nil; filterTask = nil; notify(); continueIfSparse()
            } catch { if owner == generation { filtering = false; filterWork = nil; filterTask = nil; notify() } }
        }
    }
    private func notify() { onGridUpdate?(); onViewerUpdate?() }
    private func continueIfSparse() {
        if active && criteria != nil && posts.count < 18 && pages.next != nil && error == nil && !filtering {
            Task { @MainActor [weak self] in await Task.yield(); self?.loadNext() }
        }
    }
    private func load(replacing: Bool, explicit: Bool = false) {
        guard active, !loading, !filtering, explicit || error == nil, replacing || pages.next != nil else { return }
        error = nil; loading = true; notify()
        readGeneration = UUID()
        let owner = generation, readOwner = readGeneration, cursor = replacing ? nil : pages.next
        task = Task { [weak self] in
            guard let self else { return }
            defer { if owner == generation && readOwner == readGeneration { loading = false; task = nil; notify(); continueIfSparse() } }
            do {
                let epoch = await app.api.sessionEpoch()
                let result = try await app.api.profileTimeline(userID: userID, featured: featured, next: cursor)
                try Task.checkCancellation(); guard owner == generation, readOwner == readGeneration, epoch == (await app.api.sessionEpoch()) else { return }
                let oldIDs = replacing ? Set<String>() : Set(pages.posts.map(\.id))
                try pages.apply(result, replacing: replacing, featuredOwner: featured ? userID : nil)
                if replacing { posts = [] }
                let new = pages.posts.filter { !oldIDs.contains($0.id) }
                posts += criteria.map { query in new.filter { query.matches($0, profileID: self.userID) } } ?? new
                revision &+= 1
                // Entirely filtered/empty intermediate pages are not a clean end.
                if posts.isEmpty && pages.next != nil && criteria == nil {
                    Task { @MainActor [weak self] in await Task.yield(); self?.loadNext() }
                }
            } catch is CancellationError {} catch { if owner == generation && readOwner == readGeneration { self.error = error } }
        }
    }
}

final class PostGridCell: UICollectionViewCell {
    private let picture = UIImageView(), badge = UILabel(), pin = UIImageView()
    private var task: Task<Void, Never>?, id: String?
    override init(frame: CGRect) {
        super.init(frame: frame); contentView.backgroundColor = ClassicTheme.drawer
        picture.contentMode = .scaleAspectFill; picture.clipsToBounds = true
        badge.textColor = .white; badge.font = ClassicTheme.font(11, bold: true); badge.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        pin.image = UIImage(systemName: "pin.fill"); pin.tintColor = .white; pin.layer.shadowOpacity = 0.6; pin.layer.shadowRadius = 2
        for item in [picture, badge, pin] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([
            picture.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), picture.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), picture.topAnchor.constraint(equalTo: contentView.topAnchor), picture.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3), badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            pin.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5), pin.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5), pin.widthAnchor.constraint(equalToConstant: 14), pin.heightAnchor.constraint(equalToConstant: 16)
        ])
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    override func prepareForReuse() { super.prepareForReuse(); task?.cancel(); id = nil; picture.image = nil }
    func bind(_ post: Post, loader: MediaLoader, action: String = "Open post") {
        task?.cancel(); id = post.id; picture.image = nil; pin.isHidden = !post.isPinned
        let kind = ProfileMediaKind.category(post.type)
        badge.text = kind == .gifs ? " GIF " : post.isVideo ? " ▶ " : post.hasSource ? " ↻ " : nil
        accessibilityIdentifier = "grid-post-" + post.id
        accessibilityLabel = "\(post.author), \(post.type), \(action)"
        accessibilityValue = post.isPinned ? "Pinned" : nil
        guard let url = post.gridThumbnailURL ?? post.mediaURL else { return }
        task = Task { [weak self] in
            guard let image = try? await loader.image(url), !Task.isCancelled, self?.id == post.id else { return }; self?.picture.image = image
        }
    }
}
