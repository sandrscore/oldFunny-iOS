import UIKit

final class CommentsController: ClassicScreenController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate {
    private let app: AppContext
    private let postID: String
    private let parentID: String?
    private var rootComment: Comment?
    private let postAuthorID: String?
    var onClose: (() -> Void)?
    var onCountChange: ((Int) -> Void)?
    private var onPostCountDelta: ((Int) -> Void)?, onRootDeleted: (() -> Void)?
    var isEmbeddedPanel = false
    private let table = UITableView(frame: .zero, style: .plain)
    private let text = ClassicTextField(), send = ClassicTheme.button(.send, label: "Send comment")
    private var count: Int?
    private var draft = CommentDraft(), accountID: String?
    private let attach = UIButton(type: .custom), attachment = UIButton(type: .custom)
    private let recipientLabel = UILabel(), recipientRow = UIStackView()
    private var replyThreads = [String: CommentsController](), replyCounts = [String: Int]()
    private var attachmentTask: Task<Void, Never>?
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var comments: [Comment] = [], nextCursor: String?, usedCursors = Set<String>()
    private var task: Task<Void, Never>?, loading = false
    private var generation = UUID()
    private var readGeneration = UUID(), hasLoadedReplies = false, refreshWhenIdle = false
    private var dismissingKeyboardTap = false
    private var mentionComposer: CommentMentionComposer?, mentionPanel: MentionSuggestionsView?
    private var mentionHeight: NSLayoutConstraint?
    init(app: AppContext, postID: String, parentID: String? = nil, count: Int? = nil, postAuthorID: String? = nil, rootComment: Comment? = nil) {
        self.app = app; self.postID = postID; self.parentID = parentID; self.count = count; self.postAuthorID = postAuthorID
        self.rootComment = rootComment
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
        recipientLabel.font = ClassicTheme.font(14); recipientLabel.textColor = ClassicTheme.blue
        recipientLabel.accessibilityIdentifier = "reply-recipient"
        let closeRecipient = UIButton(type: .custom); closeRecipient.setTitle("×", for: .normal); closeRecipient.titleLabel?.font = ClassicTheme.font(24)
        closeRecipient.accessibilityLabel = "Cancel recipient and clear reply text"; closeRecipient.addTarget(self, action: #selector(clearRecipient), for: .touchUpInside)
        closeRecipient.widthAnchor.constraint(equalToConstant: 44).isActive = true; closeRecipient.heightAnchor.constraint(equalToConstant: 44).isActive = true
        recipientRow.addArrangedSubview(recipientLabel); recipientRow.addArrangedSubview(closeRecipient)
        recipientRow.alignment = .center; recipientRow.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 3); recipientRow.isLayoutMarginsRelativeArrangement = true
        let footer = UIStackView(arrangedSubviews: [recipientRow, composer]); footer.axis = .vertical; footer.backgroundColor = ClassicTheme.bar
        renderRecipient()
        footer.translatesAutoresizingMaskIntoConstraints = false; table.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(table); contentView.addSubview(footer)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: contentView.topAnchor), table.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), table.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            composer.heightAnchor.constraint(equalToConstant: 60), text.heightAnchor.constraint(equalToConstant: 40)
        ])
        let suggestions = MentionSuggestionsView(app: app, host: self); mentionPanel = suggestions
        suggestions.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(suggestions)
        let height = suggestions.heightAnchor.constraint(equalToConstant: 56); mentionHeight = height
        NSLayoutConstraint.activate([suggestions.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), suggestions.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), suggestions.bottomAnchor.constraint(equalTo: footer.topAnchor), height])
        suggestions.availableHeight = { [weak footer] in max(56, (footer?.frame.minY ?? 360) - 56) }
        suggestions.onHeight = { [weak self] value in
            let resolved = max(56, value) // Hidden overlay need not collapse its internal rows.
            guard let self, let mentionHeight, abs(mentionHeight.constant - resolved) > 0.5 else { return }
            mentionHeight.constant = resolved; contentView.layoutIfNeeded()
        }
        let mentions = CommentMentionComposer(input: text, suggestions: suggestions); mentionComposer = mentions
        mentions.onChange = { [weak self] document in
            guard let self else { return }; draft.edit(document)
            traceMentionDraft()
        }
        mentions.restore(MentionDocument(text: draft.text, mentions: draft.mentions))
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: .oldFunnyAccountChanged, object: nil)
        Task { [weak self] in guard let self else { return }; accountID = await app.api.account()?.accountID }
        load(replacing: true)
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); mentionComposer?.setActive(true) }
    override func viewWillDisappear(_ animated: Bool) { mentionComposer?.setActive(false); super.viewWillDisappear(animated) }
    @objc private func draftChanged() { if let mentionComposer { mentionComposer.didEdit() } else { draft.edit(text.text ?? "") } }
    private func traceMentionDraft() {
        #if CLASSIC_UI_PREVIEW
        view.accessibilityValue = "mentions=" + (MentionDocument(text: draft.text, mentions: draft.mentions).wire() ?? "") + "; request=" + PreviewFixtures.mentionRequest
        #endif
    }
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        mentionComposer?.shouldEdit(range, replacement: string) ?? true
    }
    func textFieldDidChangeSelection(_ textField: UITextField) { mentionComposer?.updateSelection() }
    func textFieldDidBeginEditing(_ textField: UITextField) { mentionComposer?.updateSelection() }
    func textFieldDidEndEditing(_ textField: UITextField) { mentionComposer?.endEditing() }
    private func renderRecipient() {
        recipientRow.isHidden = draft.recipient == nil
        recipientLabel.text = draft.recipient.map { "Reply to \($0.nickname)" }
    }
    private func selectRecipient(_ comment: Comment) {
        draft.reply(to: comment.id == parentID ? nil : comment); renderRecipient(); text.becomeFirstResponder()
    }
    @objc private func clearRecipient() {
        // Android AnswersFragment.onReplyToCloseClick clears reply text and
        // dismisses the keyboard; the independently chosen post remains.
        draft.reply(to: nil); draft.edit(""); text.text = ""; mentionComposer?.restore(MentionDocument()); renderRecipient(); view.endEditing(true)
    }
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
    @objc private func refresh() {
        if writing || !send.isEnabled { refreshWhenIdle = true }
        else { load(replacing: true) }
    }
    @objc private func accountChanged() {
        task?.cancel(); generation = UUID(); readGeneration = UUID(); loading = false; hasLoadedReplies = false
        comments = []; nextCursor = nil; usedCursors = []; text.text = nil
        draft = CommentDraft(); mentionComposer?.resetAccount(); renderAttachment(); renderRecipient(); replyThreads = [:]; replyCounts = [:]; accountID = nil
        Task { [weak self] in guard let self else { return }; accountID = await app.api.account()?.accountID }
        table.reloadData(); refresh()
    }
    private func load(replacing: Bool) {
        guard !writing, send.isEnabled, !loading, replacing || nextCursor != nil else { return }
        loading = true; spinner.startAnimating(); let owner = readGeneration
        let cursor = replacing ? nil : nextCursor
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if owner == readGeneration { loading = false; spinner.stopAnimating(); table.refreshControl?.endRefreshing(); task = nil }
            }
            do {
                let page = try await app.api.comments(postID: postID, parentID: parentID, next: cursor)
                try Task.checkCancellation(); guard owner == readGeneration else { return }
                if replacing { comments = []; usedCursors = [] }
                var ids = Set(comments.map(\.id)); comments += page.comments.filter { ids.insert($0.id).inserted }
                if parentID == nil { for comment in comments where comment.isDeleted { replyThreads[comment.id]?.markRootDeleted() } }
                if let replyCount = page.replyCount {
                    if hasLoadedReplies, let count, replyCount != count { onPostCountDelta?(replyCount - count) }
                    count = replyCount; hasLoadedReplies = true; updateCount()
                }
                if let candidate = page.paging.next, usedCursors.insert(candidate).inserted { nextCursor = candidate } else { nextCursor = nil }
                table.reloadData()
                if comments.isEmpty {
                    let empty = UILabel(); empty.text = parentID == nil ? "No comments yet." : "No replies yet."; empty.textColor = .lightGray; empty.textAlignment = .center
                    table.backgroundView = empty
                } else { table.backgroundView = nil }
            } catch { if owner == readGeneration { showError(error) } }
        }
    }
    private var showsRoot: Bool { parentID != nil && rootComment != nil }
    func numberOfSections(in tableView: UITableView) -> Int { showsRoot ? 2 : 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { showsRoot && section == 0 ? 1 : comments.count }
    private func comment(at indexPath: IndexPath) -> Comment { showsRoot && indexPath.section == 0 ? rootComment! : comments[indexPath.row] }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let comment = comment(at: indexPath)
        let cell = table.dequeueReusableCell(withIdentifier: "comment", for: indexPath) as! ClassicCommentCell
        cell.bind(comment, loader: app.media, replyCount: showsRoot && indexPath.section == 0 ? count : replyCounts[comment.id])
        cell.setActionsEnabled(!writing && send.isEnabled)
        cell.onSmile = { [weak self] in
            guard let self, !consumeEditingTap() else { return }; commentAction(comment, kind: "smile")
        }
        cell.onUnsmile = { [weak self] in
            guard let self, !consumeEditingTap() else { return }; commentAction(comment, kind: "unsmile")
        }
        cell.onAttachment = { [weak self] in
            guard let self, !consumeEditingTap(), let post = comment.attachments.first else { return }
            navigationController?.pushViewController(PostController(app: app, post: post, index: 0, source: "prof"), animated: true)
        }
        cell.onAuthor = { [weak self] in
            guard let self, !consumeEditingTap(), let id = comment.authorID else { return }
            navigationController?.pushViewController(ProfileController(app: app, userID: id, nickname: comment.author), animated: true)
        }
        cell.canOpenMention = { [weak self] in self?.text.isFirstResponder == false }
        cell.onMention = { [weak self] mention in
            guard let self, !consumeEditingTap() else { return }
            navigationController?.pushViewController(ProfileController(app: app, userID: mention.userID, nickname: mention.nickname), animated: true)
        }
        return cell
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if showsRoot && indexPath.section == 0 { return }
        if indexPath.row >= comments.count - 4 { load(replacing: false) }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        table.deselectRow(at: indexPath, animated: true)
        guard !consumeEditingTap() else { return }
        reply(to: comment(at: indexPath))
    }
    private func reply(to comment: Comment) {
        if parentID != nil { if !comment.isDeleted { selectRecipient(comment) }; return }
        let child: CommentsController
        if let cached = replyThreads[comment.id] { child = cached }
        else {
            child = CommentsController(app: app, postID: postID, parentID: comment.id, count: replyCounts[comment.id] ?? comment.replies, postAuthorID: postAuthorID, rootComment: comment)
            child.onCountChange = { [weak self] count in self?.replyCounts[comment.id] = count; self?.table.reloadData() }
            child.onPostCountDelta = { [weak self] delta in self?.applyPostCountDelta(delta) }
            child.onRootDeleted = { [weak self] in
                guard let self else { return }
                if let index = comments.firstIndex(where: { $0.id == comment.id }) { comments[index].markDeleted() }
                applyPostCountDelta(-1); table.reloadData()
            }
            replyThreads[comment.id] = child
        }
        navigationController?.pushViewController(child, animated: true)
    }
    private func markRootDeleted() {
        rootComment?.markDeleted(); if isViewLoaded { table.reloadData() }
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let comment = comment(at: indexPath)
        guard !comment.isDeleted else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions = [UIAction(title: "Copy text", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = comment.text }]
            actions.append(UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self] _ in self?.reply(to: comment) })
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
    private func setRowActionsEnabled(_ enabled: Bool) {
        for case let cell as ClassicCommentCell in table.visibleCells { cell.setActionsEnabled(enabled) }
    }
    private func confirm(_ comment: Comment, kind: String) {
        let alert = UIAlertController(title: kind == "delete" ? "Delete this comment?" : "Report this comment?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: kind == "delete" ? "Delete" : "Report", style: .destructive) { [weak self] _ in self?.commentAction(comment, kind: kind) })
        present(alert, animated: true)
    }
    private func commentAction(_ comment: Comment, kind: String) {
        guard !comment.isDeleted, !writing, send.isEnabled else { return }; writing = true; pauseReads(); setRowActionsEnabled(false); let owner = generation
        Task { [weak self] in
            guard let self else { return }; var refresh = false
            defer { writing = false; setRowActionsEnabled(send.isEnabled); if refresh || refreshWhenIdle { refreshWhenIdle = false; refreshAfterMutation() } }
            let session = await app.api.sessionEpoch()
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            guard owner == generation else { return }
            do {
                switch kind {
                case "smile": try await app.api.reactToComment(postID: postID, commentID: comment.id, unsmile: false, enabled: !comment.isSmiled, session: session)
                case "unsmile": try await app.api.reactToComment(postID: postID, commentID: comment.id, unsmile: true, enabled: !comment.isUnsmiled, session: session)
                case "delete": try await app.api.deleteComment(postID: postID, commentID: comment.id, session: session)
                case "report": try await app.api.reportComment(postID: postID, commentID: comment.id, session: session)
                default: return
                }
                guard owner == generation else { return }
                if kind == "delete" {
                    if comment.id == parentID {
                        markRootDeleted(); onRootDeleted?()
                    } else {
                        if parentID != nil || comment.replies > 0 {
                            if let index = comments.firstIndex(where: { $0.id == comment.id }) { comments[index].markDeleted() }
                        } else { comments.removeAll { $0.id == comment.id } }
                        if let count { self.count = max(0, count - 1); updateCount() }
                        if parentID != nil { onPostCountDelta?(-1) }
                        else { replyThreads[comment.id]?.markRootDeleted() }
                    }
                    table.reloadData()
                }
                refresh = true
            } catch { if owner == generation { showError(error) } }
        }
    }
    private func refreshAfterMutation() {
        pauseReads(); load(replacing: true)
    }
    private func pauseReads() {
        task?.cancel(); readGeneration = UUID(); loading = false
        spinner.stopAnimating(); table.refreshControl?.endRefreshing()
    }
    private func applyPostCountDelta(_ delta: Int) {
        if parentID == nil {
            if let count { self.count = max(0, count + delta); updateCount() }
        } else { onPostCountDelta?(delta) }
    }
    private func updateCount() {
        let kind = parentID == nil ? "comments" : "replies"
        classicBar.setTitle(count.map { "\($0) \(kind)" } ?? kind.capitalized)
        if let count { onCountChange?(count) }
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { postComment(); return false }
    @objc private func postComment() {
        guard send.isEnabled, !writing else { return }
        mentionComposer?.didEdit()
        draft.edit(text.text ?? ""); let snapshot = draft, owner = generation
        guard snapshot.canSend else { showError(ClientError.invalidInput); return }
        send.isEnabled = false; pauseReads(); setRowActionsEnabled(false)
        Task { [weak self] in
            guard let self else { return }
            var refresh = false
            defer { send.isEnabled = true; setRowActionsEnabled(!writing); if refresh || refreshWhenIdle { refreshWhenIdle = false; refreshAfterMutation() } }
            let session = await app.api.sessionEpoch()
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            guard owner == generation else { return }
            do {
                try await app.api.sendComment(postID: postID, parentID: snapshot.replyParentID(root: parentID), text: snapshot.text, attachmentID: snapshot.attachment?.id, mentions: snapshot.mentions, session: session)
                traceMentionDraft()
                guard owner == generation else { return }
                draft.clear(ifRevision: snapshot.revision); text.text = draft.text
                mentionComposer?.restore(MentionDocument(text: draft.text, mentions: draft.mentions)); renderAttachment(); renderRecipient()
                if let count { self.count = count + 1; updateCount() }
                if parentID != nil { onPostCountDelta?(1) }
                view.endEditing(true)
                refresh = true
            } catch {
                guard owner == generation else { return }
                traceMentionDraft()
                // A network failure may follow server acceptance. Keep the draft
                // and ask the user to check the thread before any manual retry.
                let alert = UIAlertController(title: "Comment not confirmed", message: "Your text and attachment are still here. Refresh the thread and check whether it appeared before sending again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
            }
        }
    }
}
