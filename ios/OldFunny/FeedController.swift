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
    private var readContext: ReadContext?
    private var exposure = FeaturedReadExposure()
    private var settled = true, onScreen = false
    private var readWatch: Task<Void, Never>?
    private var readObservers = [NSObjectProtocol]()
    private var lastReadSample: TimeInterval?
    #if CLASSIC_UI_PREVIEW
    private let readTrace = UILabel()
    #endif
    #if CLASSIC_UI_PREVIEW
    private var previewOpened = false
    #endif

    init(app: AppContext, feed: Feed, timelineID: String? = nil, profileName: String? = nil) {
        self.app = app; self.feed = feed; self.timelineID = timelineID; self.profileName = profileName
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel(); readWatch?.cancel(); readObservers.forEach { NotificationCenter.default.removeObserver($0) } }
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
        #if CLASSIC_UI_PREVIEW
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-reads") {
            readTrace.accessibilityIdentifier = "offline-read-trace"
            readTrace.font = UIFont.systemFont(ofSize: 8); readTrace.textColor = .white
            readTrace.backgroundColor = .black; readTrace.numberOfLines = 2
            readTrace.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(readTrace)
            NSLayoutConstraint.activate([readTrace.leadingAnchor.constraint(equalTo: view.leadingAnchor), readTrace.trailingAnchor.constraint(equalTo: view.trailingAnchor), readTrace.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), readTrace.heightAnchor.constraint(equalToConstant: 24)])
        }
        #endif
        readObservers.append(NotificationCenter.default.addObserver(forName: .oldFunnyReadsChanged, object: app.reads, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateReadBadge() }
        })
        readObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.exposure.reset(); self?.lastReadSample = nil }
        })
        load(replacing: true)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onScreen = true; app.reads.activate(); startReadWatch()
        #if CLASSIC_UI_PREVIEW
        if !previewOpened && ProcessInfo.processInfo.arguments.contains("--preview-sidebar") {
            previewOpened = true; toggleMenu()
        }
        #endif
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); onScreen = false
        readWatch?.cancel(); readWatch = nil; exposure.reset(); lastReadSample = nil
    }
    private func startReadWatch() {
        guard timelineID == nil, readWatch == nil else { return }
        readWatch = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { break }
                guard let self, onScreen else { break }
                await sampleRead()
            }
        }
    }
    private func sampleRead() async {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastReadSample, now - lastReadSample > 0.5 { exposure.reset() }
        lastReadSample = now
        #if CLASSIC_UI_PREVIEW
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-reads") { updateReadTrace() }
        #endif
        guard onScreen, timelineID == nil, let context = readContext,
              let post = pager.viewControllers?.first as? PostController else { exposure.reset(); return }
        let live = await app.api.readContext()
        // Token rotation may retain the same account/epoch; an account switch
        // must never credit the newly selected account for an old viewer.
        guard live.key == context.key, live.epoch == context.epoch else { exposure.reset(); return }
        readContext = live
        let visibility = post.readVisibility(settled: settled, drawerOpen: sidebar != nil)
        let visible = visibility.qualifies(for: feed)
        let report: Bool
        if feed == .featured { report = exposure.sample(postID: post.post.id, scope: live.key + live.epoch.uuidString + live.authorizationMarker, now: Int64(now * 1000), visible: visible) }
        else { exposure.reset(); report = feed == .subscriptions && live.signedIn && visible }
        guard report else { return }
        do { try await app.reads.viewed(post.post.id, feed: feed, context: live) }
        catch { exposure.reset() } // A failed durable save can be retried after a fresh interval.
    }
    private func updateReadBadge() {
        sidebar?.setSubscriptionsUnread(app.reads.unreadSubscriptions, clearing: app.reads.clearing)
    }
    #if CLASSIC_UI_PREVIEW
    private func updateReadTrace() {
        let current = pager.viewControllers?.first as? PostController
        let rendered = current?.readVisibility(settled: settled, drawerOpen: sidebar != nil).rendered == true
        let value = "\(PreviewFixtures.readEvents.joined(separator: "|")); unread=\(app.reads.unreadSubscriptions.map(String.init) ?? "unknown"); rendered=\(rendered); post=\(current?.post.id ?? "none")"
        if readTrace.text != value { readTrace.text = value }
        if view.subviews.last !== readTrace { view.bringSubviewToFront(readTrace) }
    }
    #endif
    private var currentPost: Post? { pages.posts.indices.contains(selected) ? pages.posts[selected] : nil }
    private func updateHeader() { authorHeader.update(post: currentPost, section: profileName ?? feed.title, loader: app.media) }
    @objc private func retryLoad() { load(replacing: pages.next == nil || !pages.posts.isEmpty) }
    private func refresh() { closeSidebar(); load(replacing: true) }
    private func resetAndLoad() {
        exposure.reset(); readContext = nil; settled = true
        closeSidebar(); task?.cancel(); generation = UUID(); loading = false
        // A scroll-style page controller requires one displayed controller.
        // Detach its data source before invalidating the old index snapshot.
        pager.dataSource = nil
        retained.values.forEach { $0.setObscured(true) }
        pager.setViewControllers([UIViewController()], direction: .forward, animated: false)
        pages = FeedPages(); selected = 0; retained = [:]; updateHeader()
        load(replacing: true)
    }
    private func toggleMenu() {
        if sidebar != nil { closeSidebar(); return }
        let menu = SidebarView(selected: feed); menu.translatesAutoresizingMaskIntoConstraints = false
        menu.onSubscriptionsHold = { [weak self] in self?.subscriptionsOptions() }
        menu.onClose = { [weak self] in self?.closeSidebar() }
        menu.onSelect = { [weak self] destination in
            self?.closeSidebar { [weak self] in
                guard let self else { return }
                switch destination {
                case .feed(let item): if feed != item { feed = item; resetAndLoad() }
                case .explore: navigationController?.pushViewController(ExploreController(app: app), animated: true)
                case .profile: openProfile()
                case .account: accountMenu()
                }
            }
        }
        contentView.addSubview(menu)
        NSLayoutConstraint.activate([menu.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), menu.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), menu.topAnchor.constraint(equalTo: contentView.topAnchor), menu.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
        sidebar = menu; menu.alpha = 0
        exposure.reset(); updateReadBadge(); app.reads.requestSync(refreshCounter: true)
        (pager.viewControllers?.first as? PostController)?.setObscured(true)
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18) { menu.alpha = 1 }
        classicBar.leading.accessibilityLabel = "Close menu"
        UIAccessibility.post(notification: .screenChanged, argument: menu)
    }
    private func subscriptionsOptions() {
        guard let context = app.reads.currentContext, context.signedIn else { return }
        let options = UIAlertController(title: "Subscriptions", message: nil, preferredStyle: .alert)
        let mark = UIAlertAction(title: "Mark as viewed", style: .default) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do { try await app.reads.clearSubscriptions(expected: context) }
                catch {
                    // A local/fake failure can arrive before the choice alert
                    // finishes dismissing. Keep the failure visible for retry.
                    while presentedViewController?.isBeingDismissed == true {
                        do { try await Task.sleep(nanoseconds: 25_000_000) } catch { return }
                    }
                    showError(error)
                }
            }
        }
        mark.isEnabled = !app.reads.clearing; options.addAction(mark)
        options.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(options, animated: true)
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
        navigationController?.pushViewController(ProfileController(app: app, userID: id, nickname: post.author), animated: true)
    }
    private func openProfile() {
        Task { [weak self] in
            guard let self else { return }
            guard let account = await app.api.account() else { app.signIn(from: self); return }
            navigationController?.pushViewController(ProfileController(app: app, userID: account.accountID, nickname: account.nickname), animated: true)
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
        if replacing { exposure.reset() }
        loading = true; classicBar.trailing.isEnabled = false
        if pages.posts.isEmpty { status.loading() }
        let owner = generation, selectedFeed = feed
        task = Task { [weak self] in
            guard let self else { return }
            defer { if owner == generation { loading = false; task = nil; classicBar.trailing.isEnabled = true } }
            do {
                var replace = replacing, fetched = 0, cursors = Set<String>()
                repeat {
                    let cursor = replace ? nil : pages.next
                    let page: PostPage
                    if let timelineID { page = try await app.api.timeline(userID: timelineID, next: cursor) }
                    else {
                        let result = try await app.reads.page(selectedFeed, next: cursor)
                        page = result.0; readContext = result.1
                    }
                    try Task.checkCancellation(); guard owner == generation else { return }
                    pages.apply(page, replacing: replace)
                    if replace { selected = 0 }; replace = false; fetched += 1
                    if let next = pages.next, !cursors.insert(next).inserted { break }
                    await Task.yield()
                } while pages.posts.count - selected < 2 && pages.next != nil && fetched < (selectedFeed == .featured && timelineID == nil ? 12 : 3)
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
        let controller = PostController(app: app, post: post, index: index, source: timelineID == nil ? feed.source : "prof", section: profileName ?? feed.title, selected: index == selected)
        if timelineID == nil { controller.onMenu = { [weak self] in self?.toggleMenu() } }
        controller.onRefresh = { [weak self] in self?.refresh() }
        controller.onPanelChange = { [weak self] _ in self?.exposure.reset() }
        retained[post.id] = controller
        return controller
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let post = viewController as? PostController, post.index > 0, post.index <= pages.posts.count else { return nil }; return controller(at: post.index - 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let post = viewController as? PostController else { return nil }
        guard post.index + 1 < pages.posts.count else { load(replacing: false); return nil }
        return controller(at: post.index + 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        settled = true; exposure.reset()
        guard completed, let post = pageViewController.viewControllers?.first as? PostController else { return }
        selected = post.index; updateHeader()
        retained.values.forEach { $0.setSelected($0 === post) }
        retained = retained.filter { abs($0.value.index - selected) <= 3 }
        if selected >= pages.posts.count - 5 { load(replacing: false) }
    }
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        settled = false; exposure.reset()
    }
}
