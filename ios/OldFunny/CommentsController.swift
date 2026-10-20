import UIKit

final class CommentsController: ClassicScreenController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate {
    private let app: AppContext
    private let postID: String
    private let parentID: String?
    private let postAuthorID: String?
    var onClose: (() -> Void)?
    var onCountChange: ((Int) -> Void)?
    var isEmbeddedPanel = false
    private let table = UITableView(frame: .zero, style: .plain)
    private let text = ClassicTextField(), send = ClassicTheme.button(.send, label: "Send comment")
    private var count: Int?
    private var draft = CommentDraft(), accountID: String?
    private let attach = UIButton(type: .custom), attachment = UIButton(type: .custom)
    private var attachmentTask: Task<Void, Never>?
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var comments: [Comment] = [], nextCursor: String?, usedCursors = Set<String>()
    private var task: Task<Void, Never>?, loading = false
    private var generation = UUID()
    private var dismissingKeyboardTap = false
    init(app: AppContext, postID: String, parentID: String? = nil, count: Int? = nil, postAuthorID: String? = nil) {
        self.app = app; self.postID = postID; self.parentID = parentID; self.count = count; self.postAuthorID = postAuthorID
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel(); attachmentTask?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "comments-screen"; text.accessibilityIdentifier = "comment-draft"
        let kind = parentID == nil ? "comments" : "replies"
        classicBar.setTitle(count.map { "\($0) \(kind)" } ?? (parentID == nil ? "Comments" : "Replies"))
        classicBar.onTrailing = { [weak self] in self?.refresh() }
        if onClose != nil { classicBar.onLeading = { [weak self] in self?.onClose?() } }
        table.dataSource = self; table.delegate = self; table.backgroundColor = ClassicTheme.background
        table.register(ClassicCommentCell.self, forCellReuseIdentifier: "comment"); table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 90
        table.keyboardDismissMode = .interactive
        let finishEditing = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        finishEditing.delegate = self; finishEditing.cancelsTouchesInView = true
        finishEditing.delaysTouchesBegan = true; table.addGestureRecognizer(finishEditing)
        // In the post's comments panel a downward fling at the top returns to
        // media. Keep refresh on the header rather than competing for that swipe.
        if !isEmbeddedPanel {
            let refreshControl = UIRefreshControl(); refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged); table.refreshControl = refreshControl
        }
        spinner.hidesWhenStopped = true; table.tableFooterView = spinner
        text.attributedPlaceholder = NSAttributedString(string: "Say something funny…", attributes: [.foregroundColor: UIColor(white: 0.58, alpha: 1)])
        text.borderStyle = .none; text.textColor = UIColor(white: 0.25, alpha: 1)
        text.font = ClassicTheme.font(15); text.layer.cornerRadius = 5
        text.backgroundColor = UIColor(white: 0.90, alpha: 1); text.delegate = self; text.returnKeyType = .send
        text.addTarget(self, action: #selector(draftChanged), for: .editingChanged)
        send.tintColor = ClassicTheme.muted
        send.addTarget(self, action: #selector(postComment), for: .touchUpInside)
        attach.setTitle("+", for: .normal); attach.titleLabel?.font = ClassicTheme.font(30); attach.setTitleColor(.white, for: .normal)
        attach.accessibilityLabel = "Attach one of your posts"; attach.widthAnchor.constraint(equalToConstant: 38).isActive = true
        attach.heightAnchor.constraint(equalToConstant: 44).isActive = true
        attach.addTarget(self, action: #selector(chooseAttachment), for: .touchUpInside)
        attachment.widthAnchor.constraint(equalToConstant: 38).isActive = true; attachment.heightAnchor.constraint(equalToConstant: 38).isActive = true
        attachment.imageView?.contentMode = .scaleAspectFill; attachment.clipsToBounds = true; attachment.isHidden = true
        attachment.accessibilityLabel = "Remove attachment; keeps your text"; attachment.addTarget(self, action: #selector(removeAttachment), for: .touchUpInside)
        attachment.accessibilityIdentifier = "remove-comment-attachment"
        let removeMark = UILabel(); removeMark.text = "×"; removeMark.textAlignment = .center
        removeMark.font = ClassicTheme.font(18, bold: true); removeMark.textColor = .white
        removeMark.backgroundColor = UIColor.black.withAlphaComponent(0.8); removeMark.layer.cornerRadius = 9; removeMark.clipsToBounds = true
        removeMark.isUserInteractionEnabled = false; removeMark.isAccessibilityElement = false
        removeMark.translatesAutoresizingMaskIntoConstraints = false; attachment.addSubview(removeMark)
        NSLayoutConstraint.activate([removeMark.topAnchor.constraint(equalTo: attachment.topAnchor), removeMark.trailingAnchor.constraint(equalTo: attachment.trailingAnchor), removeMark.widthAnchor.constraint(equalToConstant: 18), removeMark.heightAnchor.constraint(equalToConstant: 18)])
        let composer = UIStackView(arrangedSubviews: [attachment, text, attach, send]); composer.spacing = 5; composer.alignment = .center
        composer.backgroundColor = ClassicTheme.bar; composer.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 3); composer.isLayoutMarginsRelativeArrangement = true
        composer.translatesAutoresizingMaskIntoConstraints = false; table.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(table); contentView.addSubview(composer)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: contentView.topAnchor), table.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), table.bottomAnchor.constraint(equalTo: composer.topAnchor),
            composer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), composer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            composer.heightAnchor.constraint(equalToConstant: 60), text.heightAnchor.constraint(equalToConstant: 40)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: .oldFunnyAccountChanged, object: nil)
        Task { [weak self] in guard let self else { return }; accountID = await app.api.account()?.accountID }
        load(replacing: true)
    }
    @objc private func draftChanged() { draft.edit(text.text ?? "") }
    @objc private func dismissKeyboard() { view.endEditing(true) }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Decide at touch-down: UIKit may move focus before shouldBegin runs.
        // The first tap on an author/attachment/row must only dismiss editing.
        dismissingKeyboardTap = text.isFirstResponder
        return dismissingKeyboardTap
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { dismissingKeyboardTap }
    private func consumeEditingTap() -> Bool {
        guard text.isFirstResponder else { return false }; view.endEditing(true); return true
    }
    @objc private func removeAttachment() { draft.attach(nil); renderAttachment() }
    private func renderAttachment() {
        attachmentTask?.cancel(); attachment.setImage(nil, for: .normal); attachment.isHidden = draft.attachment == nil
        guard let post = draft.attachment, let url = post.posterURL ?? post.mediaURL else { return }
        let loader = app.media
        attachmentTask = Task { [weak self] in
            guard let image = try? await loader.image(url), !Task.isCancelled, self?.draft.attachment?.id == post.id else { return }
            self?.attachment.setImage(image, for: .normal)
        }
    }
    @objc private func chooseAttachment() {
        view.endEditing(true)
        Task { [weak self] in
            guard let self else { return }
            guard let account = await app.api.account() else { app.signIn(from: self); return }
            let owner = generation
            let picker = PostPickerController(app: app, userID: account.accountID) { [weak self] post in
                guard let self, owner == generation else { return }; draft.attach(post); renderAttachment()
            }
            navigationController?.pushViewController(picker, animated: true)
        }
    }
    @objc private func refresh() { load(replacing: true) }
    @objc private func accountChanged() {
        task?.cancel(); generation = UUID(); loading = false
        comments = []; nextCursor = nil; usedCursors = []; text.text = nil
        draft = CommentDraft(); renderAttachment(); accountID = nil
        Task { [weak self] in guard let self else { return }; accountID = await app.api.account()?.accountID }
        table.reloadData(); load(replacing: true)
    }
    private func load(replacing: Bool) {
        guard !loading, replacing || nextCursor != nil else { return }
        loading = true; spinner.startAnimating(); let owner = generation
        let cursor = replacing ? nil : nextCursor
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if owner == generation { loading = false; spinner.stopAnimating(); table.refreshControl?.endRefreshing(); task = nil }
            }
            do {
                let page = try await app.api.comments(postID: postID, parentID: parentID, next: cursor)
                try Task.checkCancellation(); guard owner == generation else { return }
                if replacing { comments = []; usedCursors = [] }
                var ids = Set(comments.map(\.id)); comments += page.comments.filter { ids.insert($0.id).inserted }
                if let candidate = page.paging.next, usedCursors.insert(candidate).inserted { nextCursor = candidate } else { nextCursor = nil }
                table.reloadData()
                if comments.isEmpty {
                    let empty = UILabel(); empty.text = "No comments yet."; empty.textColor = .lightGray; empty.textAlignment = .center
                    table.backgroundView = empty
                } else { table.backgroundView = nil }
            } catch { if owner == generation { showError(error) } }
        }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { comments.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let comment = comments[indexPath.row]
        let cell = table.dequeueReusableCell(withIdentifier: "comment", for: indexPath) as! ClassicCommentCell
        cell.bind(comment, loader: app.media)
        cell.onAttachment = { [weak self] in
            guard let self, !consumeEditingTap(), let post = comment.attachments.first else { return }
            navigationController?.pushViewController(PostController(app: app, post: post, index: 0, source: "prof"), animated: true)
        }
        cell.onAuthor = { [weak self] in
            guard let self, !consumeEditingTap(), let id = comment.authorID else { return }
            navigationController?.pushViewController(FeedController(app: app, feed: .featured, timelineID: id, profileName: comment.author), animated: true)
        }
        return cell
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= comments.count - 4 { load(replacing: false) }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        table.deselectRow(at: indexPath, animated: true)
        guard !consumeEditingTap() else { return }
        let comment = comments[indexPath.row]
        if parentID == nil {
            navigationController?.pushViewController(CommentsController(app: app, postID: postID, parentID: comment.id, count: comment.replies, postAuthorID: postAuthorID), animated: true)
        }
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let comment = comments[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions = [UIAction(title: "Copy text", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = comment.text }]
            if parentID == nil {
                actions.append(UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self] _ in
                    guard let self else { return }
                    navigationController?.pushViewController(CommentsController(app: app, postID: postID, parentID: comment.id, count: comment.replies, postAuthorID: postAuthorID), animated: true)
                })
            }
            actions.append(UIAction(title: comment.isSmiled ? "Remove smile" : "Smile", image: UIImage(systemName: "face.smiling")) { [weak self] _ in self?.commentAction(comment, kind: "smile") })
            actions.append(UIAction(title: comment.isUnsmiled ? "Remove unsmile" : "Unsmile", image: UIImage(systemName: "hand.thumbsdown")) { [weak self] _ in self?.commentAction(comment, kind: "unsmile") })
            if let accountID, accountID == comment.authorID || accountID == postAuthorID {
                actions.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirm(comment, kind: "delete") })
            }
            actions.append(UIAction(title: "Report", image: UIImage(systemName: "flag"), attributes: .destructive) { [weak self] _ in self?.confirm(comment, kind: "report") })
            return UIMenu(children: actions)
        }
    }
    private var writing = false
    private func confirm(_ comment: Comment, kind: String) {
        let alert = UIAlertController(title: kind == "delete" ? "Delete this comment?" : "Report this comment?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: kind == "delete" ? "Delete" : "Report", style: .destructive) { [weak self] _ in self?.commentAction(comment, kind: kind) })
        present(alert, animated: true)
    }
    private func commentAction(_ comment: Comment, kind: String) {
        guard !writing, send.isEnabled else { return }; writing = true; let owner = generation
        Task { [weak self] in
            guard let self else { return }; defer { writing = false }
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            do {
                switch kind {
                case "smile": try await app.api.reactToComment(postID: postID, commentID: comment.id, unsmile: false, enabled: !comment.isSmiled)
                case "unsmile": try await app.api.reactToComment(postID: postID, commentID: comment.id, unsmile: true, enabled: !comment.isUnsmiled)
                case "delete": try await app.api.deleteComment(postID: postID, commentID: comment.id)
                case "report": try await app.api.reportComment(postID: postID, commentID: comment.id)
                default: return
                }
                guard owner == generation else { return }
                if kind == "delete" {
                    comments.removeAll { $0.id == comment.id }; table.reloadData()
                    if let count { self.count = max(0, count - 1); updateCount() }
                }
                refreshAfterMutation()
            } catch { if owner == generation { showError(error) } }
        }
    }
    private func refreshAfterMutation() {
        task?.cancel(); generation = UUID(); loading = false; load(replacing: true)
    }
    private func updateCount() {
        let kind = parentID == nil ? "comments" : "replies"
        classicBar.setTitle(count.map { "\($0) \(kind)" } ?? kind.capitalized)
        if let count { onCountChange?(count) }
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { postComment(); return false }
    @objc private func postComment() {
        guard send.isEnabled, !writing else { return }
        draft.edit(text.text ?? ""); let snapshot = draft, owner = generation
        guard snapshot.canSend else { showError(ClientError.invalidInput); return }
        send.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer { send.isEnabled = true }
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            do {
                try await app.api.sendComment(postID: postID, parentID: parentID, text: snapshot.text, attachmentID: snapshot.attachment?.id)
                guard owner == generation else { return }
                draft.clear(ifRevision: snapshot.revision); text.text = draft.text; renderAttachment()
                if let count { self.count = count + 1; updateCount() }
                view.endEditing(true)
                refreshAfterMutation()
            } catch {
                guard owner == generation else { return }
                // A network failure may follow server acceptance. Keep the draft
                // and ask the user to check the thread before any manual retry.
                let alert = UIAlertController(title: "Comment not confirmed", message: "Your text and attachment are still here. Refresh the thread and check whether it appeared before sending again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
            }
        }
    }
}
