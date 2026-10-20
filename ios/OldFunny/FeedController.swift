import UIKit

final class FeedController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let app: AppContext
    private var feed: Feed
    private let timelineID: String?
    private let profileName: String?
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private let status = StatusView()
    private var pages = FeedPages()
    private var selected = 0
    private var loading = false
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(app: AppContext, feed: Feed, timelineID: String? = nil, profileName: String? = nil) {
        self.app = app; self.feed = feed; self.timelineID = timelineID; self.profileName = profileName
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = ClassicTheme.background
        title = profileName ?? feed.title
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refresh))
        if timelineID == nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"), style: .plain, target: self, action: #selector(menu))
            app.onAccountChange = { [weak self] in self?.resetAndLoad() }
        }
        addChild(pager); view.addSubview(pager.view); pager.didMove(toParent: self)
        pager.view.translatesAutoresizingMaskIntoConstraints = false
        pager.dataSource = self; pager.delegate = self
        view.addSubview(status); status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pager.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), pager.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pager.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), pager.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: pager.view.leadingAnchor), status.trailingAnchor.constraint(equalTo: pager.view.trailingAnchor),
            status.topAnchor.constraint(equalTo: pager.view.topAnchor), status.bottomAnchor.constraint(equalTo: pager.view.bottomAnchor)
        ])
        status.retry.addTarget(self, action: #selector(refresh), for: .touchUpInside)
        load(replacing: true)
    }
    @objc private func refresh() { load(replacing: true) }
    private func resetAndLoad() {
        task?.cancel(); generation = UUID(); loading = false; pages = FeedPages(); selected = 0
        pager.setViewControllers(nil, direction: .forward, animated: false)
        load(replacing: true)
    }
    @objc private func menu() {
        let menu = UIAlertController(title: "oldFunny", message: nil, preferredStyle: .actionSheet)
        for item in Feed.allCases {
            menu.addAction(UIAlertAction(title: item.title, style: .default) { [weak self] _ in
                guard let self else { return }; feed = item; title = item.title; resetAndLoad()
            })
        }
        menu.addAction(UIAlertAction(title: "Profile", style: .default) { [weak self] _ in self?.openProfile() })
        menu.addAction(UIAlertAction(title: "Account", style: .default) { [weak self] _ in self?.accountMenu() })
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        menu.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(menu, animated: true)
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
            guard let account = await app.api.account() else { app.signIn(from: self); return }
            let menu = UIAlertController(title: account.nickname, message: nil, preferredStyle: .actionSheet)
            menu.addAction(UIAlertAction(title: "Remove account from oldFunny", style: .destructive) { [weak self] _ in
                guard let self else { return }
                Task {
                    do { try await app.api.forgetSession(); resetAndLoad() }
                    catch { showError(error) }
                }
            })
            menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            menu.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
            present(menu, animated: true)
        }
    }
    private func load(replacing: Bool) {
        guard !loading else { return }
        if !replacing && pages.next == nil { return }
        loading = true; navigationItem.rightBarButtonItem?.isEnabled = false
        if pages.posts.isEmpty { status.loading() }
        let owner = generation, cursor = replacing ? nil : pages.next, selectedFeed = feed
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if owner == generation { loading = false; task = nil; navigationItem.rightBarButtonItem?.isEnabled = true }
            }
            do {
                let page: PostPage
                if let timelineID { page = try await app.api.timeline(userID: timelineID, next: cursor) }
                else { page = try await app.api.feed(selectedFeed, next: cursor) }
                try Task.checkCancellation()
                guard owner == generation else { return }
                pages.apply(page, replacing: replacing)
                if replacing { selected = 0 }
                if pages.posts.isEmpty {
                    status.message("No posts to display.")
                } else {
                    status.isHidden = true
                    if replacing || pager.viewControllers?.isEmpty != false {
                        pager.setViewControllers([controller(at: selected)], direction: .forward, animated: false)
                    }
                    // Empty server pages may still carry a continuation. Keep
                    // traversing on explicit refresh rather than silently loop.
                    pager.dataSource = nil; pager.dataSource = self
                }
            } catch {
                guard owner == generation else { return }
                if pages.posts.isEmpty {
                    if case ClientError.signInRequired = error {
                        status.message("Sign in to view your subscriptions.", canRetry: false)
                        app.signIn(from: self)
                    } else { status.message((error as? ClientError)?.errorDescription ?? "Could not load posts.") }
                } else { showError(error) }
            }
        }
    }
    private func controller(at index: Int) -> PostController {
        PostController(app: app, post: pages.posts[index], index: index, source: timelineID == nil ? feed.source : "prof")
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let post = viewController as? PostController, post.index > 0 else { return nil }
        return controller(at: post.index - 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let post = viewController as? PostController, post.index + 1 < pages.posts.count else { return nil }
        return controller(at: post.index + 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let post = pageViewController.viewControllers?.first as? PostController else { return }
        selected = post.index
        if selected >= pages.posts.count - 5 { load(replacing: false) }
    }
}
