import UIKit

final class ProfileController: ClassicScreenController {
    private let app: AppContext, userID: String, initialNickname: String
    private let header = ProfileHeaderView(), tabs = UIStackView(), body = UIView(), information = UIScrollView(), infoRows = UIStackView()
    private let gridTab = UIButton(type: .custom), infoTab = UIButton(type: .custom), search = UIButton(type: .custom), status = StatusView()
    private let subscribe = UIButton(type: .custom)
    private var browser: ProfileBrowser!, grid: ProfilePostsController!
    private var profile: UserProfile?, showingInfo = false, busy = false, reconcile = false
    private var generation = UUID(), loadTask: Task<Void, Never>?, observer: NSObjectProtocol?
    init(app: AppContext, userID: String, nickname: String) {
        self.app = app; self.userID = userID; initialNickname = nickname; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { loadTask?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func viewDidLoad() {
        super.viewDidLoad(); view.accessibilityIdentifier = "user-profile"
        browser = ProfileBrowser(app: app, userID: userID, nickname: initialNickname)
        grid = ProfilePostsController(browser: browser, embedded: true)
        let title = UILabel(); title.text = "Profile"; title.textColor = .white; title.font = ClassicTheme.font(20, bold: true)
        search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal); search.tintColor = .white; search.accessibilityLabel = "Advanced Search"
        search.widthAnchor.constraint(equalToConstant: 44).isActive = true; search.addTarget(self, action: #selector(openSearch), for: .touchUpInside)
        let titleRow = UIStackView(arrangedSubviews: [title, search]); titleRow.spacing = 8; classicBar.setCenter(titleRow)
        classicBar.onTrailing = { [weak self] in self?.refreshProfile() }
        gridTab.setImage(UIImage(systemName: "square.grid.3x3.fill"), for: .normal); gridTab.accessibilityLabel = "Profile posts"
        infoTab.setImage(UIImage(systemName: "info"), for: .normal); infoTab.accessibilityLabel = "Profile information"
        for button in [gridTab, infoTab] { button.tintColor = ClassicTheme.muted; button.addTarget(self, action: #selector(tabPressed(_:)), for: .touchUpInside); tabs.addArrangedSubview(button) }
        tabs.distribution = .fillEqually; tabs.backgroundColor = ClassicTheme.bar
        subscribe.titleLabel?.font = ClassicTheme.font(14, bold: true); subscribe.setTitleColor(.black, for: .normal); subscribe.backgroundColor = ClassicTheme.yellow
        subscribe.layer.cornerRadius = 4; subscribe.addTarget(self, action: #selector(changeSubscription), for: .touchUpInside); subscribe.isHidden = true
        header.addSubview(subscribe); subscribe.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([subscribe.centerXAnchor.constraint(equalTo: header.centerXAnchor), subscribe.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8), subscribe.heightAnchor.constraint(equalToConstant: 32), subscribe.widthAnchor.constraint(greaterThanOrEqualToConstant: 130)])
        for item in [header, tabs, body, status] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: contentView.topAnchor), header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), header.heightAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.60),
            tabs.topAnchor.constraint(equalTo: header.bottomAnchor), tabs.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), tabs.heightAnchor.constraint(equalToConstant: 44),
            body.topAnchor.constraint(equalTo: tabs.bottomAnchor), body.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), body.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), body.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), status.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), status.topAnchor.constraint(equalTo: contentView.topAnchor), status.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        addChild(grid); body.addSubview(grid.view); grid.didMove(toParent: self)
        infoRows.axis = .vertical; infoRows.spacing = 20
        for item in [grid.view!, information] { item.translatesAutoresizingMaskIntoConstraints = false
            if item === information { body.addSubview(item) }
            NSLayoutConstraint.activate([item.leadingAnchor.constraint(equalTo: body.leadingAnchor), item.trailingAnchor.constraint(equalTo: body.trailingAnchor), item.topAnchor.constraint(equalTo: body.topAnchor), item.bottomAnchor.constraint(equalTo: body.bottomAnchor)])
        }
        information.addSubview(infoRows); infoRows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([infoRows.leadingAnchor.constraint(equalTo: information.contentLayoutGuide.leadingAnchor, constant: 16), infoRows.trailingAnchor.constraint(equalTo: information.contentLayoutGuide.trailingAnchor, constant: -16), infoRows.topAnchor.constraint(equalTo: information.contentLayoutGuide.topAnchor, constant: 18), infoRows.bottomAnchor.constraint(equalTo: information.contentLayoutGuide.bottomAnchor, constant: -18), infoRows.widthAnchor.constraint(equalTo: information.frameLayoutGuide.widthAnchor, constant: -32)])
        status.retry.addTarget(self, action: #selector(retryProfile), for: .touchUpInside)
        observer = NotificationCenter.default.addObserver(forName: .oldFunnyAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self else { return }; self.profile = nil; self.busy = false; self.classicBar.trailing.isEnabled = true; self.loadProfile() }
        }
        updateTab(); loadProfile()
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); browser.setActive(!showingInfo) }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); browser.setActive(false) }
    @objc private func retryProfile() { loadProfile() }
    private func refreshProfile() {
        guard !busy else { return }
        browser.needsRefresh = true
        if !showingInfo && view.window != nil { browser.setActive(true) }
        loadProfile()
    }
    private func loadProfile() {
        guard !busy else { return }
        loadTask?.cancel(); generation = UUID(); let owner = generation
        if profile == nil { status.loading() }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let user = try await app.api.profile(userID: userID), account = await app.api.account()
                try Task.checkCancellation(); guard owner == generation else { return }
                profile = user; reconcile = false; status.isHidden = true
                if user.isDeleted { status.message("This profile is unavailable.", canRetry: false); return }
                header.bind(user, loader: app.media); subscribe.isHidden = account?.accountID == userID
                subscribe.isEnabled = !busy && !user.isBlocked && !user.areYouBlocked
                subscribe.setTitle(user.isSubscribed ? "Subscribed" : "Subscribe", for: .normal)
                updateInformation(user)
            } catch {
                if owner == generation {
                    if profile == nil { status.message((error as? ClientError)?.errorDescription ?? "Could not load this profile.") }
                    else { showError(error) }
                }
            }
        }
    }
    @objc private func tabPressed(_ button: UIButton) { showingInfo = button === infoTab; updateTab() }
    private func updateTab() {
        grid.view.isHidden = showingInfo; information.isHidden = !showingInfo
        gridTab.tintColor = showingInfo ? ClassicTheme.muted : ClassicTheme.yellow; infoTab.tintColor = showingInfo ? ClassicTheme.yellow : ClassicTheme.muted
        gridTab.accessibilityTraits = showingInfo ? .button : [.button, .selected]; infoTab.accessibilityTraits = showingInfo ? [.button, .selected] : .button
        browser.setActive(!showingInfo && view.window != nil)
    }
    @objc private func openSearch() {
        let search = ProfileBrowser(app: app, userID: userID, nickname: profile?.nickname ?? initialNickname, search: true)
        navigationController?.pushViewController(ProfilePostsController(browser: search), animated: true)
    }
    private func updateInformation(_ user: UserProfile) {
        infoRows.arrangedSubviews.forEach { infoRows.removeArrangedSubview($0); $0.removeFromSuperview() }
        func counter(_ number: Int, _ title: String, action: @escaping () -> Void) -> UIButton {
            let button = UIButton(type: .custom); button.setTitle("\(number)\n\(title)", for: .normal); button.titleLabel?.numberOfLines = 2; button.titleLabel?.textAlignment = .center
            button.titleLabel?.font = ClassicTheme.font(17, bold: true); button.setTitleColor(ClassicTheme.text, for: .normal)
            button.accessibilityLabel = "\(number) \(title.lowercased())"; button.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
            button.addAction(UIAction { _ in action() }, for: .touchUpInside); return button
        }
        let posts = counter(user.created, "Posts") { [weak self] in self?.showingInfo = false; self?.updateTab() }
        let featured = counter(user.featured, "Featured") { [weak self] in
            guard let self else { return }; let source = ProfileBrowser(app: app, userID: userID, nickname: user.nickname, featured: true)
            navigationController?.pushViewController(ProfilePostsController(browser: source), animated: true)
        }
        let subscribers = counter(user.subscribers, "Subscribers") { [weak self] in self?.openUsers(.subscribers) }
        let subscriptions = counter(user.subscriptions, "Subscriptions") { [weak self] in self?.openUsers(.subscriptions) }
        for pair in [[posts, featured], [subscribers, subscriptions]] { let row = UIStackView(arrangedSubviews: pair); row.distribution = .fillEqually; infoRows.addArrangedSubview(row) }
        let about = UILabel(); about.text = user.about; about.numberOfLines = 0; about.font = ClassicTheme.font(16); about.textColor = ClassicTheme.text; infoRows.addArrangedSubview(about)
    }
    private func openUsers(_ kind: UserListKind) {
        navigationController?.pushViewController(UserListController(app: app, title: kind == .subscribers ? "Subscribers" : "Subscriptions", userID: userID, kind: kind), animated: true)
    }
    @objc private func changeSubscription() {
        guard !busy, let profile else { return }
        if reconcile { loadProfile(); return }
        busy = true; subscribe.isEnabled = false; classicBar.trailing.isEnabled = false; let owner = generation
        Task { [weak self] in
            guard let self else { return }; defer { if owner == generation { busy = false; subscribe.isEnabled = true; classicBar.trailing.isEnabled = true } }
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            let session = await app.api.sessionEpoch()
            do {
                let confirmed = try await app.api.setSubscribed(userID: userID, enabled: !profile.isSubscribed, session: session)
                guard owner == generation else { return }; self.profile = confirmed; subscribe.setTitle(confirmed.isSubscribed ? "Subscribed" : "Subscribe", for: .normal); updateInformation(confirmed)
            } catch {
                guard owner == generation else { return }; reconcile = true; subscribe.setTitle("Refresh to verify", for: .normal); showError(ProfileActionError.unconfirmed)
            }
        }
    }
}
private final class ProfileHeaderView: UIView {
    private let cover = UIImageView(), avatar = RemoteAvatarView(), nickname = UILabel()
    private var task: Task<Void, Never>?
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .black; clipsToBounds = true
        cover.contentMode = .scaleAspectFill; cover.clipsToBounds = true
        nickname.textColor = .white; nickname.font = ClassicTheme.font(22, bold: true); nickname.textAlignment = .center
        nickname.layer.shadowColor = UIColor.black.cgColor; nickname.layer.shadowOpacity = 0.9; nickname.layer.shadowRadius = 3
        avatar.layer.borderColor = UIColor.white.cgColor; avatar.layer.borderWidth = 2
        for item in [cover, avatar, nickname] { item.translatesAutoresizingMaskIntoConstraints = false; addSubview(item) }
        NSLayoutConstraint.activate([cover.leadingAnchor.constraint(equalTo: leadingAnchor), cover.trailingAnchor.constraint(equalTo: trailingAnchor), cover.topAnchor.constraint(equalTo: topAnchor), cover.bottomAnchor.constraint(equalTo: bottomAnchor), avatar.centerXAnchor.constraint(equalTo: centerXAnchor), avatar.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -23), avatar.widthAnchor.constraint(equalToConstant: 74), avatar.heightAnchor.constraint(equalToConstant: 74), nickname.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 9), nickname.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), nickname.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    func bind(_ user: UserProfile, loader: MediaLoader) {
        task?.cancel(); nickname.text = user.nickname; avatar.set(user.avatarURL, loader: loader); cover.image = nil
        guard let url = user.coverURL else { return }
        task = Task { [weak self] in guard let image = try? await loader.image(url), !Task.isCancelled else { return }; self?.cover.image = image }
    }
}
