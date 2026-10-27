import UIKit

final class TagPostsController: ClassicScreenController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let browser: TagBrowser
    private let grid = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let status = StatusView(), more = UIButton(type: .system)
    private var revision: UInt64?
    init(app: AppContext, feed: TagFeed) { browser = TagBrowser(app: app, feed: feed); super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.accessibilityIdentifier = "tag-grid-screen"; classicBar.setTitle(browser.nickname)
        classicBar.onTrailing = { [weak self] in self?.browser.refresh() }
        grid.backgroundColor = ClassicTheme.background; grid.alwaysBounceVertical = true; grid.accessibilityIdentifier = "tag-grid"
        grid.dataSource = self; grid.delegate = self; grid.register(PostGridCell.self, forCellWithReuseIdentifier: "post")
        more.setTitle("Could not load more. Tap to retry.", for: .normal); more.backgroundColor = ClassicTheme.bar; more.tintColor = ClassicTheme.yellow
        more.addTarget(self, action: #selector(retry), for: .touchUpInside)
        for item in [grid, status, more] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), grid.topAnchor.constraint(equalTo: contentView.topAnchor), grid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: grid.leadingAnchor), status.trailingAnchor.constraint(equalTo: grid.trailingAnchor), status.topAnchor.constraint(equalTo: grid.topAnchor), status.bottomAnchor.constraint(equalTo: grid.bottomAnchor),
            more.leadingAnchor.constraint(equalTo: grid.leadingAnchor), more.trailingAnchor.constraint(equalTo: grid.trailingAnchor), more.topAnchor.constraint(equalTo: grid.topAnchor), more.heightAnchor.constraint(equalToConstant: 44)
        ])
        status.retry.addTarget(self, action: #selector(retry), for: .touchUpInside)
        browser.onGridUpdate = { [weak self] in self?.render() }; render()
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); browser.setActive(true) }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); browser.setActive(false) }
    @objc private func retry() { browser.retry() }
    private func render() {
        guard isViewLoaded else { return }
        if revision != browser.revision { revision = browser.revision; grid.reloadData() }
        grid.accessibilityValue = "\(browser.posts.count) posts"
        more.isHidden = browser.error == nil || browser.posts.isEmpty
        classicBar.trailing.isEnabled = !browser.loading
        if !browser.posts.isEmpty { status.isHidden = true }
        else if let error = browser.error { status.message((error as? ClientError)?.errorDescription ?? (error as? ProfileActionError)?.errorDescription ?? "Could not load this tag.") }
        else if browser.loading || !browser.loaded { status.loading() }
        else { status.message("No posts to display.", canRetry: browser.hasNext) }
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { browser.posts.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = grid.dequeueReusableCell(withReuseIdentifier: "post", for: indexPath) as! PostGridCell
        cell.bind(browser.posts[indexPath.item], loader: browser.app.media); return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let side = max(1, (collectionView.bounds.width - 4) / 3); return CGSize(width: side, height: side)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat { 2 }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat { 2 }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) { if indexPath.item >= browser.posts.count - 12 { browser.loadNext() } }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        navigationController?.pushViewController(ProfileGalleryController(browser: browser, selected: indexPath.item), animated: true)
    }
}
