import UIKit

final class ProfilePostsController: ClassicScreenController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    let browser: ProfileBrowser
    private let embedded: Bool
    private let grid = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let status = StatusView(), retryBanner = UIButton(type: .custom)
    private let tags = ProfileTagChips(), mediaChoice = UIButton(type: .custom), authorChoice = UIButton(type: .custom)
    private let repubs = UIButton(type: .custom), clearAuthor = UIButton(type: .custom)
    private let authorAvatar = RemoteAvatarView()
    private var selectedAuthorAvatar: URL?
    private var gridTop: NSLayoutYAxisAnchor!
    private var renderedRevision: UInt64?
    private var renderedQueryRevision: UInt64?
    private var tagOrder = [String]()
    init(browser: ProfileBrowser, embedded: Bool = false) { self.browser = browser; self.embedded = embedded; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.accessibilityIdentifier = browser.featured ? "profile-featured-grid" : "profile-posts-grid"
        if embedded { setClassicBarHidden(true) }
        else { classicBar.setTitle(browser.criteria != nil ? "Advanced Search" : "\(browser.nickname) · Featured") }
        classicBar.onTrailing = { [weak self] in self?.browser.refresh() }
        if browser.criteria != nil {
            let title = UILabel(), subtitle = UILabel()
            title.text = "Advanced Search"; title.textColor = .white; title.font = ClassicTheme.font(18, bold: true)
            subtitle.text = browser.nickname; subtitle.textColor = ClassicTheme.muted; subtitle.font = ClassicTheme.font(12)
            let heading = UIStackView(arrangedSubviews: [title, subtitle]); heading.axis = .vertical; heading.spacing = 1; classicBar.setCenter(heading)
            classicBar.trailing.setImage(ClassicGlyph.account.image, for: .normal); classicBar.trailing.accessibilityLabel = "Search options"
            classicBar.onTrailing = { [weak self] in self?.searchOptions() }
        }
        gridTop = contentView.topAnchor
        if browser.criteria != nil { addFilters() }
        grid.dataSource = self; grid.delegate = self; grid.backgroundColor = ClassicTheme.background; grid.alwaysBounceVertical = true
        grid.accessibilityIdentifier = "profile-grid"
        grid.register(PostGridCell.self, forCellWithReuseIdentifier: "post")
        retryBanner.setTitle("Could not load more. Tap to retry.", for: .normal); retryBanner.setTitleColor(ClassicTheme.yellow, for: .normal)
        retryBanner.titleLabel?.font = ClassicTheme.font(14); retryBanner.backgroundColor = ClassicTheme.bar
        retryBanner.addTarget(self, action: #selector(retry), for: .touchUpInside)
        for item in [grid, status, retryBanner] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: gridTop), grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), grid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            status.topAnchor.constraint(equalTo: grid.topAnchor), status.leadingAnchor.constraint(equalTo: grid.leadingAnchor), status.trailingAnchor.constraint(equalTo: grid.trailingAnchor), status.bottomAnchor.constraint(equalTo: grid.bottomAnchor),
            retryBanner.topAnchor.constraint(equalTo: grid.topAnchor), retryBanner.leadingAnchor.constraint(equalTo: grid.leadingAnchor), retryBanner.trailingAnchor.constraint(equalTo: grid.trailingAnchor), retryBanner.heightAnchor.constraint(equalToConstant: 44)
        ])
        status.retry.addTarget(self, action: #selector(retry), for: .touchUpInside)
        browser.onGridUpdate = { [weak self] in self?.render() }; render()
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if !embedded { browser.setActive(true) } }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if !embedded { browser.setActive(false) } }
    @objc private func retry() { browser.retry() }
    private func render() {
        guard isViewLoaded else { return }
        if renderedRevision != browser.revision { renderedRevision = browser.revision; grid.reloadData() }
        if renderedQueryRevision != browser.queryRevision {
            renderedQueryRevision = browser.queryRevision
            grid.setContentOffset(CGPoint(x: 0, y: -grid.adjustedContentInset.top), animated: false)
        }
        grid.accessibilityValue = "\(grid.numberOfItems(inSection: 0)) posts"
        classicBar.trailing.isEnabled = browser.criteria != nil || !browser.loading
        retryBanner.isHidden = browser.error == nil || browser.posts.isEmpty
        if browser.posts.isEmpty {
            if let error = browser.error { status.message((error as? ClientError)?.errorDescription ?? (error as? ProfileActionError)?.errorDescription ?? "Could not load posts.") }
            else if browser.loading || browser.filtering || !browser.loaded { status.loading() }
            else { status.message(browser.hasNext ? "Searching older posts…" : "No matching posts.", canRetry: browser.hasNext) }
        } else { status.isHidden = true }
        if let criteria = browser.criteria {
            tagOrder = tagOrder.filter { criteria.tags.contains($0) }
            tagOrder += criteria.tags.subtracting(Set(tagOrder)).sorted()
            tags.show(tagOrder)
            mediaChoice.setTitle(criteria.media.title + " ▾", for: .normal)
            authorChoice.setTitle(criteria.authorID == nil ? "Any author ▾" : criteria.authorNickname, for: .normal)
            authorChoice.isEnabled = criteria.includeRepubs; clearAuthor.isEnabled = criteria.includeRepubs
            clearAuthor.isHidden = criteria.authorID == nil; authorChoice.alpha = criteria.includeRepubs ? 1 : 0.4
            authorAvatar.isHidden = criteria.authorID == nil; authorAvatar.alpha = criteria.includeRepubs ? 1 : 0.4
            repubs.setTitleColor(criteria.includeRepubs ? .systemRed : ClassicTheme.muted, for: .normal)
            repubs.accessibilityValue = criteria.includeRepubs ? "Included" : "Excluded"
        }
    }
    private func addFilters() {
        tags.accessibilityIdentifier = "profile-tags"
        tags.onAdd = { [weak self] in self?.chooseTags() }
        tags.onRemove = { [weak self] tag in
            guard let self, var query = browser.criteria else { return }
            query.setTags(query.tags.filter { $0 != tag }); browser.setCriteria(query)
        }
        for button in [mediaChoice, authorChoice, clearAuthor, repubs] { button.titleLabel?.font = ClassicTheme.font(14); button.setTitleColor(ClassicTheme.text, for: .normal); button.heightAnchor.constraint(equalToConstant: 40).isActive = true }
        repubs.setTitle("↻", for: .normal); repubs.titleLabel?.font = ClassicTheme.font(28); repubs.accessibilityLabel = "Include republished posts"
        repubs.widthAnchor.constraint(equalToConstant: 44).isActive = true; repubs.addTarget(self, action: #selector(toggleRepubs), for: .touchUpInside)
        mediaChoice.addTarget(self, action: #selector(selectMedia), for: .touchUpInside); mediaChoice.accessibilityIdentifier = "profile-media-filter"
        authorChoice.addTarget(self, action: #selector(selectAuthor), for: .touchUpInside); authorChoice.accessibilityIdentifier = "profile-author-filter"
        clearAuthor.setTitle("×", for: .normal); clearAuthor.accessibilityLabel = "Clear author filter"; let clearWidth = clearAuthor.widthAnchor.constraint(equalToConstant: 32); clearWidth.priority = .init(999); clearWidth.isActive = true
        clearAuthor.addTarget(self, action: #selector(removeAuthor), for: .touchUpInside)
        let top = UIStackView(arrangedSubviews: [tags, repubs]); top.spacing = 6; top.alignment = .top
        let avatarWidth = authorAvatar.widthAnchor.constraint(equalToConstant: 28); avatarWidth.priority = .init(999); avatarWidth.isActive = true; authorAvatar.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let lower = UIStackView(arrangedSubviews: [mediaChoice, authorAvatar, authorChoice, clearAuthor]); lower.spacing = 8; lower.alignment = .center
        mediaChoice.widthAnchor.constraint(equalToConstant: 145).isActive = true
        let rows = UIStackView(arrangedSubviews: [top, lower]); rows.axis = .vertical; rows.spacing = 2
        rows.backgroundColor = ClassicTheme.bar; rows.isLayoutMarginsRelativeArrangement = true; rows.layoutMargins = UIEdgeInsets(top: 6, left: 10, bottom: 5, right: 6)
        rows.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(rows)
        NSLayoutConstraint.activate([rows.topAnchor.constraint(equalTo: contentView.topAnchor), rows.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), rows.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)])
        gridTop = rows.bottomAnchor
    }
    private func chooseTags() {
        guard browser.criteria != nil else { return }
        let editor = ProfileTagEditor(app: browser.app, tags: tagOrder) { [weak self] values in
            guard let self, var query = browser.criteria else { return }
            tagOrder = values
            query.setTags(values); browser.setCriteria(query)
        }
        navigationController?.pushViewController(editor, animated: true)
    }
    @objc private func toggleRepubs() { guard var query = browser.criteria else { return }; query.includeRepubs.toggle(); browser.setCriteria(query) }
    @objc private func removeAuthor() { guard var query = browser.criteria else { return }; query.authorID = nil; query.authorNickname = ""; selectedAuthorAvatar = nil; browser.setCriteria(query) }
    @objc private func selectMedia() {
        let sheet = UIAlertController(title: "Media", message: nil, preferredStyle: .actionSheet)
        for media in ProfileMediaKind.allCases { sheet.addAction(UIAlertAction(title: media.title, style: .default) { [weak self] _ in
            guard let self, var query = browser.criteria else { return }; query.media = media; browser.setCriteria(query)
        }) }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel)); sheet.popoverPresentationController?.sourceView = mediaChoice; present(sheet, animated: true)
    }
    @objc private func selectAuthor() {
        view.endEditing(true)
        let picker = UserListController(app: browser.app, title: "Any author") { [weak self] user in
            guard let self, var query = browser.criteria else { return }; query.authorID = user.id; query.authorNickname = user.nickname
            selectedAuthorAvatar = user.avatarURL; authorAvatar.set(selectedAuthorAvatar, loader: browser.app.media); browser.setCriteria(query)
        }
        navigationController?.pushViewController(picker, animated: true)
    }
    private func searchOptions() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if browser.criteria != ProfileSearchCriteria() { sheet.addAction(UIAlertAction(title: "Clear filters", style: .default) { [weak self] _ in
            self?.selectedAuthorAvatar = nil; self?.browser.setCriteria(ProfileSearchCriteria())
        }) }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel)); sheet.popoverPresentationController?.sourceView = classicBar.trailing; present(sheet, animated: true)
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
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= browser.posts.count - 18 { browser.loadNext() }
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        navigationController?.pushViewController(ProfileGalleryController(browser: browser, selected: indexPath.item), animated: true)
    }
}
