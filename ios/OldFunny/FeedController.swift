import UIKit

final class FeedController: ClassicScreenController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let app: AppContext
    private var feed: Feed
    private let timelineID: String?
    private let profileName: String?
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private let status = StatusView(), authorHeader = AuthorHeader()
    private var sidebar: SidebarView?
    private var pages = FeedPages()
    private var selected = 0
    private var loading = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var retained = [String: PostController]()
    #if CLASSIC_UI_PREVIEW
    private var previewOpened = false
    #endif

    init(app: AppContext, feed: Feed, timelineID: String? = nil, profileName: String? = nil) {
        self.app = app; self.feed = feed; self.timelineID = timelineID; self.profileName = profileName
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); contentView.backgroundColor = .black
        setClassicBarHidden(true) // Each retained post owns all three panel headers.
        classicBar.setCenter(authorHeader)
        authorHeader.action = { [weak self] in self?.openAuthor() }
        classicBar.onTrailing = { [weak self] in self?.refresh() }
        if timelineID == nil {
            classicBar.leading.setImage(ClassicGlyph.menu.image, for: .normal)
            classicBar.leading.accessibilityLabel = "Open menu"
            classicBar.onLeading = { [weak self] in self?.toggleMenu() }
            app.onAccountChange = { [weak self] in self?.resetAndLoad() }
        }
        updateHeader()
        addChild(pager); contentView.addSubview(pager.view); pager.didMove(toParent: self)
        pager.view.translatesAutoresizingMaskIntoConstraints = false
        pager.dataSource = self; pager.delegate = self
        contentView.addSubview(status); status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pager.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), pager.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pager.view.topAnchor.constraint(equalTo: contentView.topAnchor), pager.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), status.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            status.topAnchor.constraint(equalTo: contentView.topAnchor), status.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        status.retry.addTarget(self, action: #selector(retryLoad), for: .touchUpInside)
        load(replacing: true)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if CLASSIC_UI_PREVIEW
        if !previewOpened && ProcessInfo.processInfo.arguments.contains("--preview-sidebar") {
            previewOpened = true; toggleMenu()
        }
        #endif
    }
    private var currentPost: Post? { pages.posts.indices.contains(selected) ? pages.posts[selected] : nil }
    private func updateHeader() { authorHeader.update(post: currentPost, section: profileName ?? feed.title, loader: app.media) }
    @objc private func retryLoad() { load(replacing: pages.next == nil || !pages.posts.isEmpty) }
    private func refresh() { closeSidebar(); load(replacing: true) }
    private func resetAndLoad() {
        closeSidebar(); task?.cancel(); generation = UUID(); loading = false; pages = FeedPages(); selected = 0
        pager.setViewControllers(nil, direction: .forward, animated: false); retained = [:]; updateHeader()
        load(replacing: true)
    }
    private func toggleMenu() {
        if sidebar != nil { closeSidebar(); return }
        let menu = SidebarView(selected: feed); menu.translatesAutoresizingMaskIntoConstraints = false
        menu.onClose = { [weak self] in self?.closeSidebar() }
        menu.onSelect = { [weak self] destination in
            self?.closeSidebar { [weak self] in
                guard let self else { return }
                switch destination {
                case .feed(let item): if feed != item { feed = item; resetAndLoad() }
                case .profile: openProfile()
                case .account: accountMenu()
                }
            }
        }
        contentView.addSubview(menu)
        NSLayoutConstraint.activate([menu.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), menu.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), menu.topAnchor.constraint(equalTo: contentView.topAnchor), menu.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
        sidebar = menu; menu.alpha = 0
        (pager.viewControllers?.first as? PostController)?.setObscured(true)
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18) { menu.alpha = 1 }
        classicBar.leading.accessibilityLabel = "Close menu"
        UIAccessibility.post(notification: .screenChanged, argument: menu)
    }
    private func closeSidebar(then completion: (() -> Void)? = nil) {
        guard let menu = sidebar else { completion?(); return }; sidebar = nil
        classicBar.leading.accessibilityLabel = "Open menu"
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.15, animations: { menu.alpha = 0 }) { [weak self] _ in
            menu.removeFromSuperview(); (self?.pager.viewControllers?.first as? PostController)?.setObscured(false)
            completion?()
        }
    }
    private func openAuthor() {
        guard let post = currentPost, let id = post.authorID else { return }
        navigationController?.pushViewController(FeedController(app: app, feed: .featured, timelineID: id, profileName: post.author), animated: true)
    }
    private func openProfile() {
        Task { [weak self] in
            guard let self else { return }
            guard let account = await app.api.account() else { app.signIn(from: self); return }
            navigationController?.pushViewController(FeedController(app: app, feed: .featured, timelineID: account.accountID, profileName: account.nickname), animated: true)
        }
    }
    private func accountMenu() {
        Task { [weak self] in
            guard let self else { return }
            let account = await app.api.account()
            navigationController?.pushViewController(AccountController(app: app, account: account), animated: true)
        }
    }
    private func load(replacing: Bool) {
        guard !loading, replacing || pages.next != nil else { return }
        loading = true; classicBar.trailing.isEnabled = false
        if pages.posts.isEmpty { status.loading() }
        let owner = generation, selectedFeed = feed
        task = Task { [weak self] in
            guard let self else { return }
            defer { if owner == generation { loading = false; task = nil; classicBar.trailing.isEnabled = true } }
            do {
                var replace = replacing, fetched = 0
                repeat {
                    let cursor = replace ? nil : pages.next
                    let page: PostPage
                    if let timelineID { page = try await app.api.timeline(userID: timelineID, next: cursor) }
                    else { page = try await app.api.feed(selectedFeed, next: cursor) }
                    try Task.checkCancellation(); guard owner == generation else { return }
                    pages.apply(page, replacing: replace)
                    if replace { selected = 0 }; replace = false; fetched += 1
                } while pages.posts.count - selected < 2 && pages.next != nil && fetched < 3
                if pages.posts.isEmpty {
                    status.message(pages.next == nil ? "No posts to display." : "No posts in this page. Tap Try again to continue.")
                } else {
                    status.isHidden = true
                    if replacing { retained = [:] }
                    if replacing || pager.viewControllers?.isEmpty != false { pager.setViewControllers([controller(at: selected)], direction: .forward, animated: false) }
                    pager.dataSource = nil; pager.dataSource = self
                    #if CLASSIC_UI_PREVIEW
                    if let post = pager.viewControllers?.first as? PostController {
                        if ProcessInfo.processInfo.arguments.contains("--preview-comments") { post.showPanel(.comments, animated: false) }
                        if ProcessInfo.processInfo.arguments.contains("--preview-information") { post.showPanel(.information, animated: false) }
                    }
                    #endif
                }
                updateHeader()
            } catch {
                guard owner == generation else { return }
                if pages.posts.isEmpty {
                    if case ClientError.signInRequired = error {
                        status.message("Sign in to view your subscriptions.", canRetry: false); app.signIn(from: self)
                    } else { status.message((error as? ClientError)?.errorDescription ?? "Could not load posts.") }
                } else { showError(error) }
            }
        }
    }
    private func controller(at index: Int) -> PostController {
        let post = pages.posts[index]
        if let cached = retained[post.id] { return cached }
        let controller = PostController(app: app, post: post, index: index, source: timelineID == nil ? feed.source : "prof", embedded: true)
        if timelineID == nil { controller.onMenu = { [weak self] in self?.toggleMenu() } }
        controller.onRefresh = { [weak self] in self?.refresh() }
        retained[post.id] = controller
        return controller
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let post = viewController as? PostController, post.index > 0 else { return nil }; return controller(at: post.index - 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let post = viewController as? PostController else { return nil }
        guard post.index + 1 < pages.posts.count else { load(replacing: false); return nil }
        return controller(at: post.index + 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let post = pageViewController.viewControllers?.first as? PostController else { return }
        selected = post.index; updateHeader()
        retained = retained.filter { abs($0.value.index - selected) <= 3 }
        if selected >= pages.posts.count - 5 { load(replacing: false) }
    }
}
