import UIKit

final class ProfileGalleryController: ClassicScreenController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let browser: ProfileBrowser
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private let status = StatusView()
    private var selected: Int, retained = [String: PostController]()
    init(browser: ProfileBrowser, selected: Int) { self.browser = browser; self.selected = selected; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); setClassicBarHidden(true); view.accessibilityIdentifier = "profile-gallery"
        addChild(pager); contentView.addSubview(pager.view); pager.didMove(toParent: self)
        for item in [pager.view!, status] { item.translatesAutoresizingMaskIntoConstraints = false
            if item === status { contentView.addSubview(item) }
            NSLayoutConstraint.activate([item.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), item.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), item.topAnchor.constraint(equalTo: contentView.topAnchor), item.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
        }
        pager.dataSource = self; pager.delegate = self
        if browser.posts.indices.contains(selected) { pager.setViewControllers([controller(at: selected)], direction: .forward, animated: false) }
        status.retry.addTarget(self, action: #selector(retry), for: .touchUpInside)
        browser.onViewerUpdate = { [weak self] in self?.update() }; update()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); browser.setActive(true, consumeRefresh: false)
        retained.values.forEach { $0.setObscured(false); $0.setSelected($0.index == selected) }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); browser.setActive(false)
        retained.values.forEach { $0.setObscured(true) }
    }
    @objc private func retry() { browser.retry() }
    private func update() {
        guard isViewLoaded else { return }
        if browser.posts.isEmpty {
            retained.values.forEach { $0.setObscured(true) }; retained = [:]; pager.dataSource = nil
            pager.setViewControllers([UIViewController()], direction: .forward, animated: false)
            setClassicBarHidden(false); classicBar.setTitle(browser.nickname)
            if let error = browser.error { status.message((error as? ClientError)?.errorDescription ?? (error as? ProfileActionError)?.errorDescription ?? "Could not load posts.") }
            else if browser.loading || !browser.loaded { status.loading() }
            else { status.message("No posts to display.", canRetry: false) }
        } else {
            status.isHidden = true; setClassicBarHidden(true)
            if !(pager.viewControllers?.first is PostController) { selected = min(selected, browser.posts.count - 1); pager.setViewControllers([controller(at: selected)], direction: .forward, animated: false) }
            pager.dataSource = nil; pager.dataSource = self
        }
    }
    private func controller(at index: Int) -> PostController {
        let post = browser.posts[index]
        if let cached = retained[post.id] { return cached }
        let controller = PostController(app: browser.app, post: post, index: index, source: "prof", section: browser.nickname, selected: index == selected, profileOwnerID: browser.userID)
        controller.onProfilePinsChanged = { [weak browser] in browser?.needsRefresh = true }
        retained[post.id] = controller; return controller
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let post = viewController as? PostController, post.index > 0, post.index <= browser.posts.count else { return nil }
        return controller(at: post.index - 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let post = viewController as? PostController else { return nil }
        guard post.index + 1 < browser.posts.count else { browser.loadNext(); return nil }
        return controller(at: post.index + 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let post = pager.viewControllers?.first as? PostController else { return }
        selected = post.index; retained.values.forEach { $0.setSelected($0 === post) }
        retained = retained.filter { abs($0.value.index - selected) <= 3 }
        if selected >= browser.posts.count - 5 { browser.loadNext() }
    }
}
