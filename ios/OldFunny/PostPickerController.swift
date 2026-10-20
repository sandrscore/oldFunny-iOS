import UIKit

/// Existing posts/reposts only: choosing never uploads or publishes anything.
final class PostPickerController: ClassicScreenController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let app: AppContext
    private let userID: String
    private let choose: (Post) -> Void
    private let grid = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let status = StatusView()
    private var pages = FeedPages(), loading = false
    private var task: Task<Void, Never>?
    init(app: AppContext, userID: String, choose: @escaping (Post) -> Void) {
        self.app = app; self.userID = userID; self.choose = choose; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); classicBar.setTitle("Attach a post")
        classicBar.onTrailing = { [weak self] in self?.load(replacing: true) }
        grid.backgroundColor = ClassicTheme.background; grid.dataSource = self; grid.delegate = self
        grid.register(PostPickerCell.self, forCellWithReuseIdentifier: "post"); grid.alwaysBounceVertical = true
        for item in [grid, status] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item)
            NSLayoutConstraint.activate([item.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), item.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), item.topAnchor.constraint(equalTo: contentView.topAnchor), item.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
        }
        status.retry.addTarget(self, action: #selector(retry), for: .touchUpInside); load(replacing: true)
    }
    @objc private func retry() { load(replacing: pages.next == nil) }
    private func load(replacing: Bool) {
        guard !loading, replacing || pages.next != nil else { return }
        loading = true; if pages.posts.isEmpty { status.loading() }
        task = Task { [weak self] in
            guard let self else { return }; defer { loading = false; task = nil }
            do {
                guard await app.api.account()?.accountID == userID else { throw ClientError.sessionChanged }
                var replace = replacing, batch = 0
                repeat {
                    let result = try await app.api.timeline(userID: userID, next: replace ? nil : pages.next)
                    try Task.checkCancellation(); pages.apply(result, replacing: replace); replace = false; batch += 1
                } while pages.posts.isEmpty && pages.next != nil && batch < 3
                grid.reloadData(); status.isHidden = !pages.posts.isEmpty
                if pages.posts.isEmpty { status.message(pages.next == nil ? "No posts to attach." : "No available posts in this page. Try again to continue.", canRetry: pages.next != nil) }
            } catch {
                if pages.posts.isEmpty { status.message((error as? ClientError)?.errorDescription ?? "Could not load your posts.") }
                else { showError(error) }
            }
        }
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { pages.posts.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = grid.dequeueReusableCell(withReuseIdentifier: "post", for: indexPath) as! PostPickerCell
        cell.bind(pages.posts[indexPath.item], loader: app.media); return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let side = max(1, (collectionView.bounds.width - 4) / 3); return CGSize(width: side, height: side)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat { 2 }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat { 2 }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= pages.posts.count - 18 { load(replacing: false) }
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let post = pages.posts[indexPath.item]
        Task { [weak self] in
            guard let self else { return }
            guard await app.api.account()?.accountID == userID else { showError(ClientError.sessionChanged); return }
            choose(post); navigationController?.popViewController(animated: true)
        }
    }
}

private final class PostPickerCell: UICollectionViewCell {
    private let picture = UIImageView(), badge = UILabel()
    private var task: Task<Void, Never>?, id: String?
    override init(frame: CGRect) {
        super.init(frame: frame); contentView.backgroundColor = ClassicTheme.drawer
        picture.contentMode = .scaleAspectFill; picture.clipsToBounds = true
        badge.textColor = .white; badge.font = ClassicTheme.font(11, bold: true); badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        for item in [picture, badge] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([picture.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), picture.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), picture.topAnchor.constraint(equalTo: contentView.topAnchor), picture.bottomAnchor.constraint(equalTo: contentView.bottomAnchor), badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3), badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3)])
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    override func prepareForReuse() { super.prepareForReuse(); task?.cancel(); id = nil; picture.image = nil }
    func bind(_ post: Post, loader: MediaLoader) {
        task?.cancel(); id = post.id; picture.image = nil
        badge.text = post.isVideo ? " ▶ " : (post.isGIF ? " GIF " : nil)
        accessibilityLabel = "\(post.author), \(post.type), attach post"
        guard let url = post.posterURL ?? post.mediaURL else { return }
        task = Task { [weak self] in
            guard let image = try? await loader.image(url), !Task.isCancelled, self?.id == post.id else { return }; self?.picture.image = image
        }
    }
}
