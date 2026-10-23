import UIKit

/// Account/query-fenced user suggestions above the existing comment footer.
/// The panel can be resized independently of the retained comments list.
final class MentionSuggestionsView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onChoose: ((MentionUser) -> Void)?, onHeight: ((CGFloat) -> Void)?
    var availableHeight: (() -> CGFloat)?
    private let app: AppContext
    private weak var host: UIViewController?
    private let list = UITableView(frame: .zero, style: .plain), status = UIButton(type: .custom), grip = UIView()
    private var users = [MentionUser](), ids = Set<String>(), cursors = Set<String>()
    private var defaults: [MentionUser]?, nextCursor: String?, generation = UUID()
    private(set) var query: String?
    private var loading = false, failed = false, needsSignIn = false, loaded = false
    private var task: Task<Void, Never>?, debounce: Task<Void, Never>?
    private var preferredHeight: CGFloat?, dragHeight: CGFloat = 0
    init(app: AppContext, host: UIViewController) {
        self.app = app; self.host = host; super.init(frame: .zero)
        backgroundColor = ClassicTheme.bar; isHidden = true; accessibilityIdentifier = "mention-panel"
        let mark = UIView(); mark.backgroundColor = ClassicTheme.muted; mark.layer.cornerRadius = 2
        mark.translatesAutoresizingMaskIntoConstraints = false; grip.addSubview(mark)
        NSLayoutConstraint.activate([grip.heightAnchor.constraint(equalToConstant: 18), mark.centerXAnchor.constraint(equalTo: grip.centerXAnchor), mark.centerYAnchor.constraint(equalTo: grip.centerYAnchor), mark.widthAnchor.constraint(equalToConstant: 44), mark.heightAnchor.constraint(equalToConstant: 4)])
        grip.accessibilityLabel = "Resize mention suggestions"; grip.isAccessibilityElement = true
        grip.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resize(_:))))
        status.titleLabel?.font = ClassicTheme.font(13); status.setTitleColor(ClassicTheme.text, for: .normal)
        status.accessibilityIdentifier = "mention-status"; status.addTarget(self, action: #selector(retry), for: .touchUpInside)
        let statusHeight = status.heightAnchor.constraint(equalToConstant: 36); statusHeight.priority = .init(999); statusHeight.isActive = true
        list.dataSource = self; list.delegate = self; list.rowHeight = 56; list.separatorStyle = .none
        list.backgroundColor = ClassicTheme.bar; list.contentInsetAdjustmentBehavior = .never
        list.register(MentionSuggestionCell.self, forCellReuseIdentifier: "mention"); list.accessibilityIdentifier = "mention-suggestions"
        let stack = UIStackView(arrangedSubviews: [grip, status, list]); stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel(); debounce?.cancel() }
    func resetAccount() { defaults = nil; hide() }
    func hide() {
        task?.cancel(); debounce?.cancel(); task = nil; debounce = nil; generation = UUID()
        query = nil; loading = false; isHidden = true; preferredHeight = nil; onHeight?(0)
    }
    func show(_ value: String) {
        if !isHidden && query == value { return }
        task?.cancel(); debounce?.cancel(); generation = UUID(); query = value
        users = []; ids = []; cursors = []; nextCursor = nil; loading = false; failed = false; needsSignIn = false; loaded = false
        isHidden = false; preferredHeight = nil; list.setContentOffset(.zero, animated: false); list.reloadData()
        if value.isEmpty, let defaults { users = defaults; ids = Set(users.map(\.id)); loaded = true; render(); return }
        if !value.isEmpty && value.unicodeScalars.count < 2 { notice("Type one more character to search"); return }
        notice("Loading profiles…")
        debounce = Task { [weak self] in
            do {
                if !value.isEmpty { try await Task.sleep(nanoseconds: 250_000_000) }
                try Task.checkCancellation(); self?.load()
            } catch {}
        }
    }
    func notice(_ message: String) { status.setTitle(message, for: .normal); status.isHidden = false; resolveHeight() }
    private func render() {
        list.reloadData()
        if failed { notice(needsSignIn ? "Sign in to load profiles" : "Couldn't load profiles. Tap to retry.") }
        else if users.isEmpty { notice(loading ? "Loading profiles…" : "No matching profiles") }
        else { status.isHidden = true; resolveHeight() }
    }
    private func limits() -> (CGFloat, CGFloat) {
        let available = max(56, availableHeight?() ?? 360), extra: CGFloat = 18 + (status.isHidden ? 0 : 36)
        return (min(available, CGFloat(max(1, min(users.count, 3))) * 56 + extra), min(available, CGFloat(max(1, min(users.count, 9))) * 56 + extra))
    }
    private func resolveHeight() {
        guard !isHidden else { return }; let (minimum, maximum) = limits()
        onHeight?(min(maximum, max(minimum, preferredHeight ?? minimum)))
    }
    override func layoutSubviews() { super.layoutSubviews(); resolveHeight() }
    @objc private func resize(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began { dragHeight = bounds.height }
        let (minimum, maximum) = limits()
        preferredHeight = min(maximum, max(minimum, dragHeight - pan.translation(in: self).y)); resolveHeight()
    }
    @objc private func retry() {
        if needsSignIn, let host { app.signIn(from: host); return }
        guard failed else { return }; failed = false; load()
    }
    private func load() {
        guard let query, !isHidden, !loading, !failed, query.isEmpty || query.unicodeScalars.count >= 2,
              !loaded || nextCursor != nil else { return }
        loading = true; needsSignIn = false; let owner = generation, cursor = nextCursor
        if users.isEmpty { notice("Loading profiles…") }
        task = Task { [weak self] in
            guard let self else { return }
            defer { if owner == generation { loading = false; task = nil; render() } }
            do {
                let page = try await app.api.mentionUsers(query: query, next: cursor)
                try Task.checkCancellation(); guard owner == generation, !isHidden else { return }
                for user in page.users where !ids.contains(user.id) {
                    if query.isEmpty && users.count >= 9 { break }
                    ids.insert(user.id); users.append(user)
                }
                loaded = true; nextCursor = query.isEmpty ? nil : page.paging.next
                if let nextCursor, !cursors.insert(nextCursor).inserted { self.nextCursor = nil }
                if query.isEmpty { defaults = users }
                // Invalid/filtered users do not make an intermediate page final.
                if users.count < 9 && nextCursor != nil { Task { @MainActor [weak self] in await Task.yield(); self?.load() } }
            } catch is CancellationError {} catch {
                guard owner == generation else { return }; failed = true
                if case ClientError.signInRequired = error { needsSignIn = true }
            }
        }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { users.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = list.dequeueReusableCell(withIdentifier: "mention", for: indexPath) as! MentionSuggestionCell
        cell.bind(users[indexPath.row], loader: app.media); return cell
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) { if indexPath.row >= users.count - 4 { load() } }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.deselectRow(at: indexPath, animated: true); onChoose?(users[indexPath.row]) }
}

private final class MentionSuggestionCell: UITableViewCell {
    private let avatar = RemoteAvatarView(), nickname = UILabel(), mutual = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier); backgroundColor = ClassicTheme.bar
        nickname.font = ClassicTheme.font(15, bold: true); nickname.textColor = ClassicTheme.blue
        mutual.text = "✓"; mutual.font = ClassicTheme.font(18, bold: true); mutual.textColor = .systemGreen
        for item in [avatar, nickname, mutual] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12), avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), avatar.widthAnchor.constraint(equalToConstant: 36), avatar.heightAnchor.constraint(equalToConstant: 36), nickname.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10), nickname.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), nickname.trailingAnchor.constraint(lessThanOrEqualTo: mutual.leadingAnchor, constant: -8), mutual.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16), mutual.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func bind(_ user: MentionUser, loader: MediaLoader) {
        nickname.text = user.nickname; mutual.isHidden = !user.mutual; avatar.set(user.avatarURL, loader: loader)
        accessibilityIdentifier = "mention-user-" + user.id
        accessibilityLabel = "Mention " + user.nickname + (user.mutual ? ", following each other" : "")
    }
}

@MainActor
final class CommentMentionComposer {
    private(set) var document = MentionDocument()
    var onChange: ((MentionDocument) -> Void)?
    private weak var input: UITextField?
    private let suggestions: MentionSuggestionsView
    private var styling = false, active = false
    private var observers = [NSObjectProtocol]()
    init(input: UITextField, suggestions: MentionSuggestionsView) {
        self.input = input; self.suggestions = suggestions
        suggestions.onChoose = { [weak self] in self?.choose($0) }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.suggestions.hide() } })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.updateSelection() } })
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    func setActive(_ value: Bool) { active = value; if value { updateSelection() } else { suggestions.hide() } }
    func resetAccount() { document = MentionDocument(); suggestions.resetAccount(); restore(document) }
    func restore(_ value: MentionDocument) { document = value; input?.text = value.text; onChange?(document); style(); updateSelection() }
    func endEditing() { suggestions.hide() }
    func shouldEdit(_ range: NSRange, replacement: String) -> Bool {
        var updated = document
        guard updated.replace(range, with: replacement), updated.text.utf16.count <= 300 else { return false }
        document = updated; return true
    }
    func didEdit() {
        guard !styling, let input else { return }
        if !document.text.utf16.elementsEqual((input.text ?? "").utf16) { document = MentionDocument(text: input.text ?? "") }
        onChange?(document); if input.markedTextRange == nil { style() }; updateSelection()
    }
    private func selection() -> (Int, Int)? {
        guard let input, let selected = input.selectedTextRange else { return nil }
        return (input.offset(from: input.beginningOfDocument, to: selected.start), input.offset(from: input.beginningOfDocument, to: selected.end))
    }
    func updateSelection() {
        guard !styling else { return }
        guard active, UIApplication.shared.applicationState == .active, let input, input.window != nil, input.isFirstResponder, input.isEnabled, input.markedTextRange == nil,
              document.text.utf16.elementsEqual((input.text ?? "").utf16), let (start, end) = selection(),
              let token = document.token(cursor: start, selectionEnd: end) else { suggestions.hide(); return }
        suggestions.show(token.query)
    }
    private func choose(_ user: MentionUser) {
        guard let input, let (start, end) = selection(), let token = document.token(cursor: start, selectionEnd: end), token.query == suggestions.query else { return }
        do {
            let caret = try document.choose(token, userID: user.id, nickname: user.nickname, cursor: start)
            input.text = document.text
            if let position = input.position(from: input.beginningOfDocument, offset: caret) { input.selectedTextRange = input.textRange(from: position, to: position) }
            style(); onChange?(document); suggestions.hide()
        } catch { suggestions.notice("Not enough room for this mention") }
    }
    private func style() {
        guard let input, input.markedTextRange == nil else { return }
        let selected = selection(); styling = true; defer { styling = false }
        let font = input.font ?? ClassicTheme.font(15)
        let attributed = NSMutableAttributedString(string: document.text, attributes: [.font: font, .foregroundColor: UIColor(white: 0.25, alpha: 1)])
        for mention in document.mentions { attributed.addAttribute(.foregroundColor, value: UIColor(red: 41 / 255, green: 121 / 255, blue: 1, alpha: 1), range: mention.range) }
        // UIKit already preserves attributes for ordinary edits. Replacing an
        // identical value during editing needlessly resets its text-input state.
        guard input.attributedText?.isEqual(to: attributed) != true else { return }
        input.attributedText = attributed
        if let (start, end) = selected, let a = input.position(from: input.beginningOfDocument, offset: start), let b = input.position(from: input.beginningOfDocument, offset: end) { input.selectedTextRange = input.textRange(from: a, to: b) }
    }
}
