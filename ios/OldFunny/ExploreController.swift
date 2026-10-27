import UIKit

final class ExploreController: ClassicScreenController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private enum Mode { case explore, recent, tags, users }
    private enum Row { case tag(ExploreTile, trending: Bool), user(UserProfile), recent(RecentSearchEntry) }
    private let app: AppContext
    private let query = ClassicTextField(), tabs = UISegmentedControl(items: ["Tags", "iFunnyers"])
    private let table = UITableView(frame: .zero, style: .plain), status = StatusView(), footer = UIButton(type: .system)
    private var tabHeight: NSLayoutConstraint!
    private var mode: Mode = .explore, rows = [Row](), tiles = [ExploreTile]()
    private var users = [UserProfile](), nextCursor: String?, cursors = Set<String>()
    private var generation = UUID(), task: Task<Void, Never>?, loading = false, failed = false
    private var observer: NSObjectProtocol?, active = false
    init(app: AppContext) { self.app = app; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func viewDidLoad() {
        super.viewDidLoad(); view.accessibilityIdentifier = "explore-screen"; classicBar.setTitle("Explore")
        classicBar.onTrailing = { [weak self] in self?.trailing() }
        query.backgroundColor = ClassicTheme.drawer; query.textColor = ClassicTheme.text; query.font = ClassicTheme.font(16)
        query.attributedPlaceholder = NSAttributedString(string: "Search tags and iFunnyers", attributes: [.foregroundColor: ClassicTheme.muted])
        query.autocapitalizationType = .none; query.autocorrectionType = .no; query.clearButtonMode = .whileEditing
        query.returnKeyType = .search; query.delegate = self; query.accessibilityIdentifier = "explore-query"
        query.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        tabs.selectedSegmentIndex = 0; tabs.selectedSegmentTintColor = ClassicTheme.yellow
        tabs.setTitleTextAttributes([.foregroundColor: ClassicTheme.text], for: .normal)
        tabs.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        tabs.addTarget(self, action: #selector(queryChanged), for: .valueChanged); tabs.accessibilityIdentifier = "explore-tabs"
        table.backgroundColor = ClassicTheme.background; table.separatorColor = ClassicTheme.drawer
        table.rowHeight = 72; table.keyboardDismissMode = .onDrag; table.dataSource = self; table.delegate = self
        table.accessibilityIdentifier = "explore-results"
        table.register(ExploreTagCell.self, forCellReuseIdentifier: "tag"); table.register(ProfileUserCell.self, forCellReuseIdentifier: "user")
        footer.setTitle("Could not load more. Tap to retry.", for: .normal); footer.tintColor = ClassicTheme.yellow
        footer.addTarget(self, action: #selector(retry), for: .touchUpInside)
        for item in [query, tabs, table, status] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        tabHeight = tabs.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            query.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8), query.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8), query.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8), query.heightAnchor.constraint(equalToConstant: 42),
            tabs.topAnchor.constraint(equalTo: query.bottomAnchor, constant: 8), tabs.leadingAnchor.constraint(equalTo: query.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: query.trailingAnchor), tabHeight,
            table.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8), table.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), table.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), table.bottomAnchor.constraint(equalTo: contentView.keyboardLayoutGuide.topAnchor),
            status.topAnchor.constraint(equalTo: table.topAnchor), status.leadingAnchor.constraint(equalTo: table.leadingAnchor), status.trailingAnchor.constraint(equalTo: table.trailingAnchor), status.bottomAnchor.constraint(equalTo: table.bottomAnchor)
        ])
        status.retry.addTarget(self, action: #selector(retry), for: .touchUpInside)
        observer = NotificationCenter.default.addObserver(forName: .oldFunnyAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self else { return }; invalidate(resetPages: true); rows = []; tiles = []; users = []; render(); if active { queryChanged() } }
        }
        render()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); active = true
        if mode == .recent { showRecent() }
        else if rows.isEmpty && !failed { load(replacing: true) }
        else if mode == .users && nextCursor != nil && (table.indexPathsForVisibleRows ?? []).contains(where: { $0.row >= rows.count - 5 }) { load(replacing: false) }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); active = false; invalidate() }
    private func invalidate(resetPages: Bool = false) {
        task?.cancel(); task = nil; generation = UUID(); loading = false; failed = false
        if resetPages { nextCursor = nil; cursors = [] }
    }
    func textFieldDidBeginEditing(_ textField: UITextField) { if (query.text ?? "").isEmpty { invalidate(resetPages: true); showRecent() } }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { query.resignFirstResponder(); return true }
    @objc private func queryChanged() {
        invalidate(resetPages: true); rows = []; users = []; table.setContentOffset(.zero, animated: false)
        let text = query.text ?? ""
        if text.isEmpty {
            if query.isFirstResponder { showRecent() }
            else { mode = .explore; rows = tiles.map { .tag($0, trending: true) }; render(); if tiles.isEmpty { load(replacing: true) } }
            return
        }
        mode = tabs.selectedSegmentIndex == 0 ? .tags : .users
        render()
        guard text.utf16.count >= 2 else { status.message("Type one more character to search.", canRetry: false); return }
        loading = true; status.loading(); let owner = generation
        task = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000); try Task.checkCancellation() } catch { return }
            guard let self, owner == generation else { return }; loading = false; task = nil; load(replacing: true)
        }
    }
    private func showRecent() { mode = .recent; rows = app.searchHistory.history.entries.map(Row.recent); render() }
    private func trailing() { if mode == .recent { app.searchHistory.clear(); showRecent() } else { load(replacing: true, explicit: true) } }
    @objc private func retry() { load(replacing: rows.isEmpty, explicit: true) }
    private func render() {
        tabs.isHidden = mode == .explore || mode == .recent; tabHeight.constant = tabs.isHidden ? 0 : 32
        classicBar.trailing.setImage(mode == .recent ? UIImage(systemName: "trash") : ClassicGlyph.refresh.image, for: .normal)
        classicBar.trailing.accessibilityLabel = mode == .recent ? "Clear recent searches" : "Refresh"
        table.reloadData(); table.accessibilityValue = "\(rows.count) results"
        #if CLASSIC_UI_PREVIEW
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-explore") { view.accessibilityValue = PreviewFixtures.exploreRequests.joined(separator: "|") + "|" }
        #endif
        if !rows.isEmpty { status.isHidden = true }
        else if loading { status.loading() }
        else { status.message(mode == .recent ? "No recent searches." : "No results.", canRetry: false) }
    }
    private func load(replacing: Bool, explicit: Bool = false) {
        guard active, !loading, explicit || !failed, mode != .recent, replacing || nextCursor != nil else { return }
        let text = query.text ?? ""
        if mode != .explore && text.utf16.count < 2 { return }
        loading = true; failed = false; if rows.isEmpty { status.loading() }; table.tableFooterView = nil
        let owner = generation, requestMode = mode, cursor = replacing ? nil : nextCursor
        task = Task { [weak self] in
            guard let self else { return }; defer { if owner == generation { loading = false; task = nil } }
            do {
                let epoch = await app.api.sessionEpoch()
                switch requestMode {
                case .explore:
                    let page = try await app.api.explore()
                    try Task.checkCancellation(); guard owner == generation, epoch == (await app.api.sessionEpoch()) else { return }
                    tiles = page.tiles; rows = tiles.map { .tag($0, trending: true) }
                case .tags:
                    let page = try await app.api.exploreTags(text)
                    try Task.checkCancellation(); guard owner == generation, epoch == (await app.api.sessionEpoch()) else { return }
                    rows = page.tiles.map { .tag($0, trending: false) }
                case .users:
                    let page = try await app.api.searchUsers(text, next: cursor)
                    try Task.checkCancellation(); guard owner == generation, epoch == (await app.api.sessionEpoch()) else { return }
                    if let value = page.paging.next, !replacing && cursors.contains(value) { throw ProfileActionError.cursorLoop }
                    if replacing { users = []; cursors = [] }
                    var ids = Set(users.map(\.id)); users += page.users.filter { ids.insert($0.id).inserted }
                    nextCursor = page.paging.next; if let nextCursor { cursors.insert(nextCursor) }; rows = users.map(Row.user)
                case .recent: return
                }
                loading = false; render()
            } catch is CancellationError {} catch {
                guard owner == generation else { return }; failed = true
                if rows.isEmpty { status.message((error as? ClientError)?.errorDescription ?? "Could not load Explore.") }
                else { footer.frame = CGRect(x: 0, y: 0, width: table.bounds.width, height: 52); table.tableFooterView = footer }
            }
        }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        switch row {
        case .user(let user):
            let cell = table.dequeueReusableCell(withIdentifier: "user", for: indexPath) as! ProfileUserCell; cell.bind(user, loader: app.media); return cell
        case .recent(let entry) where entry.kind == .user:
            let cell = table.dequeueReusableCell(withIdentifier: "user", for: indexPath) as! ProfileUserCell
            if let user = entry.user { cell.bind(user, loader: app.media) }; return cell
        default:
            let cell = table.dequeueReusableCell(withIdentifier: "tag", for: indexPath) as! ExploreTagCell
            if case .tag(let tile, _) = row { cell.bind(tag: tile.tag, uses: tile.uses, url: tile.previewURL, loader: app.media) }
            else if case .recent(let entry) = row { cell.bind(tag: entry.query, uses: 0, url: nil, loader: app.media) }
            return cell
        }
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if mode == .users && indexPath.row >= rows.count - 5 { load(replacing: false) }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard rows.indices.contains(indexPath.row) else { return }; let row = rows[indexPath.row]
        table.deselectRow(at: indexPath, animated: true); view.endEditing(true)
        switch row {
        case .user(let user): openUser(user)
        case .tag(let tile, let trending): openTag(tile.tag, trending: trending)
        case .recent(let entry): if let user = entry.user { openUser(user) } else { openTag(entry.query, trending: false) }
        }
    }
    private func openUser(_ user: UserProfile) {
        app.searchHistory.record(RecentSearchEntry(user: user)); navigationController?.pushViewController(ProfileController(app: app, userID: user.id, nickname: user.nickname), animated: true)
    }
    private func openTag(_ tag: String, trending: Bool) {
        guard let feed = try? TagFeed(tag: tag, kind: trending ? .trending : .tag), let recent = try? RecentSearchEntry(tag: tag) else { return }
        app.searchHistory.record(recent); navigationController?.pushViewController(TagPostsController(app: app, feed: feed), animated: true)
    }
}

private final class ExploreTagCell: UITableViewCell {
    private let tagName = UILabel(), count = UILabel(), thumbnail = UIImageView(), hashLabel = UILabel()
    private var task: Task<Void, Never>?, boundTag: String?
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier); backgroundColor = ClassicTheme.background
        hashLabel.text = "#"; hashLabel.font = ClassicTheme.font(36, bold: true); hashLabel.textColor = ClassicTheme.yellow
        tagName.font = ClassicTheme.font(18, bold: true); tagName.textColor = ClassicTheme.yellow
        count.font = ClassicTheme.font(12); count.textColor = ClassicTheme.muted
        thumbnail.contentMode = .scaleAspectFill; thumbnail.clipsToBounds = true; thumbnail.layer.cornerRadius = 3
        let text = UIStackView(arrangedSubviews: [tagName, count]); text.axis = .vertical; text.spacing = 3
        for item in [hashLabel, text, thumbnail] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([
            hashLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16), hashLabel.widthAnchor.constraint(equalToConstant: 36), hashLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: hashLabel.trailingAnchor, constant: 12), text.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), text.trailingAnchor.constraint(lessThanOrEqualTo: thumbnail.leadingAnchor, constant: -8),
            thumbnail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12), thumbnail.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), thumbnail.heightAnchor.constraint(equalToConstant: 54), thumbnail.widthAnchor.constraint(equalToConstant: 54)
        ])
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    override func prepareForReuse() { super.prepareForReuse(); task?.cancel(); boundTag = nil; thumbnail.image = nil }
    func bind(tag: String, uses: Int, url: URL?, loader: MediaLoader) {
        task?.cancel(); boundTag = tag; thumbnail.image = nil; tagName.text = tag; count.text = uses > 0 ? "\(uses) posts" : nil
        accessibilityLabel = "#" + tag; accessibilityIdentifier = "explore-tag-" + tag
        guard let url else { return }
        task = Task { [weak self] in guard let bitmap = try? await loader.image(url), !Task.isCancelled, self?.boundTag == tag else { return }; self?.thumbnail.image = bitmap }
    }
}
