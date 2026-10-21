import UIKit

/// The same public user rows serve subscribers/subscriptions and the author
/// picker. Search has one user page, never an unrelated Tags tab.
final class UserListController: ClassicScreenController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let app: AppContext, heading: String
    private let userID: String?, kind: UserListKind?
    private let choose: ((UserProfile) -> Void)?
    private let table = UITableView(frame: .zero, style: .plain), query = ClassicTextField(), status = StatusView()
    private var users = [UserProfile](), nextCursor: String?, cursors = Set<String>()
    private var generation = UUID(), loading = false, failed = false
    private var task: Task<Void, Never>?, debounce: Task<Void, Never>?
    private var observer: NSObjectProtocol?, needsReload = false
    private let recentKey = "oldFunny.profileAuthorRecents.v1"
    init(app: AppContext, title: String, userID: String? = nil, kind: UserListKind? = nil, choose: ((UserProfile) -> Void)? = nil) {
        self.app = app; heading = title; self.userID = userID; self.kind = kind; self.choose = choose
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel(); debounce?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func viewDidLoad() {
        super.viewDidLoad(); classicBar.setTitle(heading)
        classicBar.onTrailing = { [weak self] in
            guard let self else { return }
            if kind == nil && (query.text ?? "").isEmpty { UserDefaults.standard.removeObject(forKey: recentKey); showRecent() }
            else { load(replacing: true, explicit: true) }
        }
        table.dataSource = self; table.delegate = self; table.backgroundColor = ClassicTheme.background
        table.register(ProfileUserCell.self, forCellReuseIdentifier: "user"); table.rowHeight = 64; table.separatorColor = ClassicTheme.drawer
        table.keyboardDismissMode = .onDrag
        var top = contentView.topAnchor
        if kind == nil {
            query.backgroundColor = ClassicTheme.drawer; query.textColor = ClassicTheme.text; query.font = ClassicTheme.font(16)
            query.attributedPlaceholder = NSAttributedString(string: "Search iFunnyers", attributes: [.foregroundColor: ClassicTheme.muted])
            query.autocapitalizationType = .none; query.autocorrectionType = .no; query.returnKeyType = .search; query.delegate = self
            query.accessibilityIdentifier = "user-search"; query.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
            query.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(query)
            NSLayoutConstraint.activate([query.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8), query.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8), query.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8), query.heightAnchor.constraint(equalToConstant: 42)])
            top = query.bottomAnchor
        }
        for item in [table, status] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item)
            NSLayoutConstraint.activate([item.topAnchor.constraint(equalTo: top, constant: kind == nil ? 8 : 0), item.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), item.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), item.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
        }
        status.retry.addTarget(self, action: #selector(retry), for: .touchUpInside)
        observer = NotificationCenter.default.addObserver(forName: .oldFunnyAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }; self.task?.cancel(); self.debounce?.cancel(); self.generation = UUID()
                self.users = []; self.nextCursor = nil; self.cursors = []; self.loading = false; self.failed = false
                self.table.reloadData(); self.needsReload = true
                if self.navigationController?.topViewController === self { self.reloadAfterAccountChange() }
            }
        }
        if kind == nil { showRecent() } else { load(replacing: true) }
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if needsReload { reloadAfterAccountChange() } }
    private func reloadAfterAccountChange() { needsReload = false; if kind == nil { queryChanged() } else { load(replacing: true, explicit: true) } }
    private func showRecent() {
        let saved = UserDefaults.standard.array(forKey: recentKey) as? [[String: String]] ?? []
        users = saved.compactMap { value in
            let raw = JSON.object(["id": .string(value["id"] ?? ""), "nick": .string(value["nick"] ?? ""), "avatar": .object(["s": .string(value["avatar"] ?? "")])])
            return try? UserProfile(raw)
        }
        nextCursor = nil; table.reloadData()
        if users.isEmpty { status.message("Search for a user.", canRetry: false) } else { status.isHidden = true }
        classicBar.trailing.setImage(UIImage(systemName: "trash"), for: .normal); classicBar.trailing.accessibilityLabel = "Clear recent users"
    }
    @objc private func queryChanged() {
        debounce?.cancel(); task?.cancel(); generation = UUID(); loading = false; failed = false; users = []; nextCursor = nil; cursors = []
        table.reloadData()
        if (query.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { showRecent(); return }
        status.loading()
        debounce = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000); try Task.checkCancellation(); self?.load(replacing: true) } catch {}
        }
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { debounce?.cancel(); query.resignFirstResponder(); load(replacing: true, explicit: true); return true }
    @objc private func retry() { load(replacing: users.isEmpty, explicit: true) }
    private func load(replacing: Bool, explicit: Bool = false) {
        guard !loading, explicit || !failed, replacing || nextCursor != nil else { return }
        let text = (query.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == nil && text.isEmpty { showRecent(); return }
        loading = true; failed = false; if users.isEmpty { status.loading() }
        classicBar.trailing.setImage(ClassicGlyph.refresh.image, for: .normal); classicBar.trailing.accessibilityLabel = "Refresh"
        let owner = generation, cursor = replacing ? nil : nextCursor
        task = Task { [weak self] in
            guard let self else { return }; defer { if owner == generation { loading = false; task = nil } }
            do {
                let result: UserPage
                if let kind, let userID { result = try await app.api.users(userID: userID, kind: kind, next: cursor) }
                else { result = try await app.api.searchUsers(text, next: cursor) }
                try Task.checkCancellation(); guard owner == generation else { return }
                if let candidate = result.paging.next, !replacing && (candidate == nextCursor || cursors.contains(candidate)) { throw ProfileActionError.cursorLoop }
                if replacing { users = []; cursors = [] }
                var seen = Set(users.map(\.id)); users += result.users.filter { seen.insert($0.id).inserted }
                nextCursor = result.paging.next; if let nextCursor { cursors.insert(nextCursor) }
                table.reloadData()
                if users.isEmpty { status.message("No users found.", canRetry: nextCursor != nil) } else { status.isHidden = true }
            } catch {
                if owner == generation {
                    failed = true
                    if users.isEmpty { status.message((error as? ClientError)?.errorDescription ?? "Could not load users.") }
                    else { showError(error) }
                }
            }
        }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { users.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = table.dequeueReusableCell(withIdentifier: "user", for: indexPath) as! ProfileUserCell
        cell.bind(users[indexPath.row], loader: app.media); return cell
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) { if indexPath.row >= users.count - 5 { load(replacing: false) } }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        table.deselectRow(at: indexPath, animated: true); let user = users[indexPath.row]
        if let choose {
            var recent = UserDefaults.standard.array(forKey: recentKey) as? [[String: String]] ?? []
            recent.removeAll { $0["id"] == user.id }; recent.insert(["id": user.id, "nick": user.nickname, "avatar": user.avatarURL?.absoluteString ?? ""], at: 0)
            UserDefaults.standard.set(Array(recent.prefix(20)), forKey: recentKey)
            choose(user); navigationController?.popViewController(animated: true)
        } else { navigationController?.pushViewController(ProfileController(app: app, userID: user.id, nickname: user.nickname), animated: true) }
    }
}
private final class ProfileUserCell: UITableViewCell {
    private let avatar = RemoteAvatarView(), name = UILabel(), detail = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier); backgroundColor = ClassicTheme.background
        name.font = ClassicTheme.font(17, bold: true); name.textColor = ClassicTheme.blue
        detail.font = ClassicTheme.font(12); detail.textColor = ClassicTheme.muted
        let names = UIStackView(arrangedSubviews: [name, detail]); names.axis = .vertical; names.spacing = 3
        for item in [avatar, names] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12), avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), avatar.widthAnchor.constraint(equalToConstant: 42), avatar.heightAnchor.constraint(equalToConstant: 42), names.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12), names.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12), names.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func bind(_ user: UserProfile, loader: MediaLoader) { name.text = user.nickname; detail.text = "\(user.subscribers) subscribers"; avatar.set(user.avatarURL, loader: loader); accessibilityIdentifier = "user-row-" + user.id }
}
