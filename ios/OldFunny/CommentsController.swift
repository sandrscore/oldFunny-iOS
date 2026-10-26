import UIKit

final class CommentsController: ClassicScreenController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate {
    private let app: AppContext
    private let postID: String
    private let parentID: String?
    private var rootComment: Comment?
    private let postAuthorID: String?
    var onClose: (() -> Void)?
    var onCountChange: ((Int) -> Void)?
    private var onPostCountDelta: ((Int) -> Void)?, onRootDeleted: ((Int) -> Void)?
    var isEmbeddedPanel = false
    private let table = UITableView(frame: .zero, style: .plain)
    private let text = ClassicTextField(), send = ClassicTheme.button(.send, label: "Send comment")
    private var count: Int?
    private var draft = CommentDraft(), accountID: String?
    private let attach = UIButton(type: .custom), attachment = UIButton(type: .custom)
    private let recipientLabel = UILabel(), recipientRow = UIStackView()
    private var replyThreads = [String: CommentsController](), replyCounts = [String: Int]()
    private var attachmentTask: Task<Void, Never>?
    private var openingAttachment: Task<Void, Never>?
    private var attachmentOpenID: UUID?
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var comments: [Comment] = [], nextCursor: String?, usedCursors = Set<String>()
    private var task: Task<Void, Never>?, loading = false
    private var generation = UUID()
    private var readGeneration = UUID(), hasLoadedReplies = false, refreshWhenIdle = false
    private var dismissingKeyboardTap = false
    private var mentionComposer: CommentMentionComposer?, mentionPanel: MentionSuggestionsView?
    private var mentionHeight: NSLayoutConstraint?
    private var pendingRecipient: Comment?
    private var selecting = false, selectedIDs = [String](), uncertainDeletion = false
    private let selectionEntry = UIButton(type: .system)
    private lazy var selectionHold = UILongPressGestureRecognizer(target: self, action: #selector(selectHeldRow(_:)))
    init(app: AppContext, postID: String, parentID: String? = nil, count: Int? = nil, postAuthorID: String? = nil, rootComment: Comment? = nil) {
        self.app = app; self.postID = postID; self.parentID = parentID; self.count = count; self.postAuthorID = postAuthorID
        self.rootComment = rootComment
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel(); attachmentTask?.cancel(); openingAttachment?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "comments-screen"; text.accessibilityIdentifier = "comment-draft"
        selectionEntry.setImage(UIImage(systemName: "pencil"), for: .normal); selectionEntry.tintColor = .white
        selectionEntry.accessibilityLabel = "Select comments"
        let selectionWidth = selectionEntry.widthAnchor.constraint(equalToConstant: 44); selectionWidth.priority = .init(999); selectionWidth.isActive = true
        selectionEntry.addTarget(self, action: #selector(beginSelection), for: .touchUpInside)
        renderHeader()
        table.dataSource = self; table.delegate = self; table.backgroundColor = ClassicTheme.background
        table.register(ClassicCommentCell.self, forCellReuseIdentifier: "comment"); table.separatorStyle = .none
        table.register(DeletedCommentCell.self, forCellReuseIdentifier: "deleted-comment")
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 90
        table.keyboardDismissMode = .interactive
        let finishEditing = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        finishEditing.delegate = self; finishEditing.cancelsTouchesInView = true
        finishEditing.delaysTouchesBegan = true; table.addGestureRecognizer(finishEditing)
        selectionHold.delegate = self; table.addGestureRecognizer(selectionHold)
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
        Task { [weak self] in guard let self else { return }; accountID = await app.api.account()?.accountID; renderHeader() }
        load(replacing: true)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); mentionComposer?.setActive(true)
        if let recipient = pendingRecipient { pendingRecipient = nil; selectRecipient(recipient) }
        if uncertainDeletion && !selecting { refresh() }
    }
    override func viewWillDisappear(_ animated: Bool) {
        openingAttachment?.cancel(); openingAttachment = nil; attachmentOpenID = nil
        mentionComposer?.setActive(false); if selecting { endSelection() }; super.viewWillDisappear(animated)
    }
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
    func textFieldDidBeginEditing(_ textField: UITextField) { if selecting { endSelection() }; mentionComposer?.updateSelection() }
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
        if gestureRecognizer === selectionHold {
            guard !writing, send.isEnabled, !uncertainDeletion,
                  let path = table.indexPathForRow(at: touch.location(in: table)) else { return false }
            let row = comment(at: path)
            return !row.isDeleted
        }
        // Decide at touch-down: UIKit may move focus before shouldBegin runs.
        // The first tap on an author/attachment/row must only dismiss editing.
        dismissingKeyboardTap = text.isFirstResponder
        return dismissingKeyboardTap
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { gestureRecognizer === selectionHold ? canSelectComments && !writing && send.isEnabled : dismissingKeyboardTap }
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
        openingAttachment?.cancel(); openingAttachment = nil; attachmentOpenID = nil
        task?.cancel(); generation = UUID(); readGeneration = UUID(); loading = false; hasLoadedReplies = false
        comments = []; nextCursor = nil; usedCursors = []; text.text = nil
        draft = CommentDraft(); pendingRecipient = nil; mentionComposer?.resetAccount(); renderAttachment(); renderRecipient(); replyThreads = [:]; replyCounts = [:]; accountID = nil
        selecting = false; selectedIDs = []; uncertainDeletion = false; renderHeader()
        Task { [weak self] in guard let self else { return }; accountID = await app.api.account()?.accountID; renderHeader() }
        table.reloadData(); refresh()
    }
    private func load(replacing: Bool) {
        guard !writing, send.isEnabled, !loading, replacing || nextCursor != nil else { return }
        loading = true; spinner.startAnimating(); let owner = readGeneration
        let cursor = replacing ? nil : nextCursor
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if owner == readGeneration { loading = false; spinner.stopAnimating(); table.refreshControl?.endRefreshing(); task = nil; renderHeader() }
            }
            do {
                let page = try await app.api.comments(postID: postID, parentID: parentID, next: cursor)
                try Task.checkCancellation(); guard owner == readGeneration else { return }
                if replacing { comments = []; usedCursors = [] }
                if replacing { uncertainDeletion = false }
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
        if parentID != nil, comment.id != parentID, comment.isDeleted {
            let cell = table.dequeueReusableCell(withIdentifier: "deleted-comment", for: indexPath) as! DeletedCommentCell
            cell.bind(id: comment.id); return cell
        }
        let cell = table.dequeueReusableCell(withIdentifier: "comment", for: indexPath) as! ClassicCommentCell
        let dots = parentID == nil ? 0 : CommentBehavior.replyDots(depth: comment.depth, shortestViewportSide: Double(min(view.bounds.width, view.bounds.height)))
        cell.bind(comment, loader: app.media, replyCount: showsRoot && indexPath.section == 0 ? count : replyCounts[comment.id], replyDots: dots, showsReplyControl: parentID == nil)
        cell.setBatchSelected(selectedIDs.contains(comment.id))
        cell.setActionsEnabled(!writing && send.isEnabled)
        cell.onSmile = { [weak self] in
            guard let self, !consumeEditingTap() else { return }; if selecting { toggleSelection(comment); return }; commentAction(comment, kind: "smile")
        }
        cell.onUnsmile = { [weak self] in
            guard let self, !consumeEditingTap() else { return }; if selecting { toggleSelection(comment); return }; commentAction(comment, kind: "unsmile")
        }
        cell.onReplies = { [weak self] in
            guard let self, !consumeEditingTap() else { return }
            if selecting { toggleSelection(comment); return }
            openReplies(to: comment)
        }
        cell.onAttachment = { [weak self] attachment in
            guard let self, !consumeEditingTap() else { return }
            if selecting { toggleSelection(comment); return }
            openAttachment(attachment)
        }
        cell.onAuthor = { [weak self] in
            guard let self, !consumeEditingTap(), let id = comment.authorID else { return }
            if selecting { toggleSelection(comment); return }
            navigationController?.pushViewController(ProfileController(app: app, userID: id, nickname: comment.author), animated: true)
        }
        cell.canOpenMention = { [weak self] in self?.text.isFirstResponder == false && self?.selecting == false }
        cell.onMention = { [weak self] mention in
            guard let self, !consumeEditingTap() else { return }
            navigationController?.pushViewController(ProfileController(app: app, userID: mention.userID, nickname: mention.nickname), animated: true)
        }
        return cell
    }
    private func openAttachment(_ attachment: CommentAttachment) {
        guard !writing, openingAttachment == nil else { return }
        if attachment.unavailable { showSelectionNotice("Post unavailable", message: "This post is no longer available."); return }
        let owner = generation
        guard let id = attachment.contentID else {
            if let url = attachment.previewURL {
                UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                    guard !opened else { return }
                    Task { @MainActor [weak self] in
                        guard let self, owner == generation else { return }
                        showSelectionNotice("Couldn't open this post", message: "The preview could not be opened.")
                    }
                }
            } else { showSelectionNotice("Couldn't open this post", message: "No usable post or preview address was supplied.") }
            return
        }
        let attempt = UUID(); attachmentOpenID = attempt
        openingAttachment = Task { [weak self] in
            guard let self else { return }
            defer { if attachmentOpenID == attempt { openingAttachment = nil; attachmentOpenID = nil } }
            do {
                let post = try await app.api.content(postID: id)
                try Task.checkCancellation(); guard owner == generation, view.window != nil else { return }
                #if CLASSIC_UI_PREVIEW
                if ProcessInfo.processInfo.arguments.contains("--ui-tests-attachment-cards") { view.accessibilityValue = PreviewFixtures.attachmentReads.joined(separator: ",") }
                #endif
                navigationController?.pushViewController(PostController(app: app, post: post, index: 0, source: "prof"), animated: true)
            } catch is CancellationError { }
            catch { if owner == generation && !Task.isCancelled { showError(error) } }
        }
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if showsRoot && indexPath.section == 0 { return }
        if indexPath.row >= comments.count - 4 { load(replacing: false) }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        table.deselectRow(at: indexPath, animated: true)
        guard !consumeEditingTap() else { return }
        if selecting { toggleSelection(comment(at: indexPath)); return }
        showOptions(for: comment(at: indexPath))
    }
    private func requestReply(to comment: Comment) {
        guard !comment.isDeleted, !writing, send.isEnabled,
              parentID == nil || comment.depth < CommentBehavior.maximumReplyDepth else { return }
        let owner = generation
        Task { [weak self] in
            guard let self else { return }
            let signedIn = await app.api.account() != nil
            guard owner == generation else { return }
            guard signedIn else { app.signIn(from: self); return }
            if parentID != nil { selectRecipient(comment) }
            else { openReplies(to: comment, focusReply: true) }
        }
    }
    private func openReplies(to comment: Comment, focusReply: Bool = false) {
        guard parentID == nil, !writing else { return }
        let child: CommentsController
        if let cached = replyThreads[comment.id] { child = cached }
        else {
            child = CommentsController(app: app, postID: postID, parentID: comment.id, count: replyCounts[comment.id] ?? comment.replies, postAuthorID: postAuthorID, rootComment: comment)
            child.onCountChange = { [weak self] count in self?.replyCounts[comment.id] = count; self?.table.reloadData() }
            child.onPostCountDelta = { [weak self] delta in self?.applyPostCountDelta(delta) }
            child.onRootDeleted = { [weak self] replies in
                guard let self else { return }
                removeMainRoot(id: comment.id, replies: replies)
            }
            replyThreads[comment.id] = child
        }
        if focusReply { child.pendingRecipient = comment }
        navigationController?.pushViewController(child, animated: true)
    }
    private func markRootDeleted() {
        // Read-side refresh may retain an already-deleted root as context.
        // A confirmed root DELETE uses removeMainRoot and closes the thread.
        rootComment?.markDeleted(); if isViewLoaded { table.reloadData() }
    }
    private func removeMainRoot(id: String, replies: Int) {
        if let count { self.count = max(0, count - min(count, max(0, replies)) - 1) }
        comments.removeAll { $0.id == id }; replyCounts[id] = nil; replyThreads[id] = nil
        updateCount(); table.reloadData()
        if comments.isEmpty {
            let empty = UILabel(); empty.text = "No comments yet."; empty.textColor = .lightGray; empty.textAlignment = .center
            table.backgroundView = empty
        }
    }
    private func returnAfterRootDeletion() {
        let back: () -> Void = { [weak self] in self?.navigationController?.popViewController(animated: true) }
        // An offline/fast receipt can arrive during the confirmation alert's
        // dismissal. Finish that transition before popping its presenter.
        if let transition = presentedViewController?.transitionCoordinator,
           transition.animate(alongsideTransition: nil, completion: { _ in back() }) { return }
        if presentedViewController != nil { dismiss(animated: false, completion: back) }
        else { back() }
    }
    private var canSelectComments: Bool {
        accountID != nil && accountID == postAuthorID && (count ?? 0) > 0
            && comments.contains { !$0.isDeleted && $0.id != parentID }
    }
    private func renderHeader() {
        let kind = parentID == nil ? "comments" : "replies"
        let title = UILabel(); title.textColor = .white; title.font = ClassicTheme.font(19, bold: true)
        title.text = selecting ? "\(selectedIDs.count) selected" : count.map { "\($0) \(kind)" } ?? kind.capitalized
        selectionEntry.isHidden = selecting || !canSelectComments; selectionEntry.isEnabled = !writing && send.isEnabled && !uncertainDeletion && !loading
        let row = UIStackView(arrangedSubviews: [title, selectionEntry]); row.alignment = .fill
        classicBar.setCenter(row)
        classicBar.leading.accessibilityLabel = selecting ? "Cancel comment selection" : "Back"
        classicBar.leading.isEnabled = !selecting || !writing
        classicBar.onLeading = { [weak self] in
            guard let self else { return }
            if selecting { endSelection() }
            else if let onClose { onClose() }
            else { navigationController?.popViewController(animated: true) }
        }
        classicBar.trailing.setImage(selecting ? UIImage(systemName: "trash") : ClassicGlyph.refresh.image, for: .normal)
        classicBar.trailing.accessibilityLabel = selecting ? "Delete selected comments" : "Refresh"
        classicBar.trailing.isEnabled = !selecting || (!selectedIDs.isEmpty && !writing && send.isEnabled && !uncertainDeletion)
        classicBar.onTrailing = { [weak self] in
            guard let self else { return }; if selecting { confirmSelectionDeletion() } else { refresh() }
        }
        #if CLASSIC_UI_PREVIEW
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-bulk-delete") {
            view.accessibilityValue = "selected=" + selectedIDs.joined(separator: ",") + "; request=" + PreviewFixtures.bulkRequest
        }
        #endif
    }
    @objc private func beginSelection() {
        guard canSelectComments, !writing, send.isEnabled, !uncertainDeletion, !loading else { return }
        view.endEditing(true); selecting = true; selectedIDs = []; uncertainDeletion = false
        renderHeader(); table.reloadData()
    }
    private func endSelection() {
        let shouldRefresh = uncertainDeletion
        selecting = false; selectedIDs = []; renderHeader(); table.reloadData()
        if shouldRefresh { refresh() }
    }
    @objc private func selectHeldRow(_ hold: UILongPressGestureRecognizer) {
        guard hold.state == .began, let path = table.indexPathForRow(at: hold.location(in: table)) else { return }
        let row = comment(at: path)
        if !(canSelectComments && row.id != parentID) { showOptions(for: row); return }
        if !selecting { beginSelection() }; toggleSelection(row)
    }
    private func toggleSelection(_ comment: Comment) {
        guard selecting, canSelectComments, !writing, send.isEnabled, !uncertainDeletion,
              comment.id != parentID, !comment.isDeleted else { return }
        if let index = selectedIDs.firstIndex(of: comment.id) { selectedIDs.remove(at: index) }
        else { selectedIDs.append(comment.id) }
        renderHeader(); table.reloadData()
    }
    private func confirmSelectionDeletion() {
        guard selecting, !selectedIDs.isEmpty, !writing, send.isEnabled, !uncertainDeletion else { return }
        let alert = UIAlertController(title: "Delete \(selectedIDs.count) selected comments?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in self?.deleteSelection() })
        present(alert, animated: true)
    }
    private func deleteSelection() {
        guard selecting, canSelectComments, !writing, send.isEnabled, !uncertainDeletion else { return }
        let selected = selectedIDs.compactMap { id in comments.first { $0.id == id && !$0.isDeleted } }
        guard !selected.isEmpty, selected.count == selectedIDs.count else { endSelection(); refresh(); return }
        let ids = selected.map(\.id), owner = generation
        writing = true; pauseReads(); setRowActionsEnabled(false); renderHeader()
        Task { [weak self] in
            guard let self else { return }
            defer { writing = false; setRowActionsEnabled(send.isEnabled); renderHeader(); if refreshWhenIdle { refreshWhenIdle = false; refreshAfterMutation() } }
            let session = await app.api.sessionEpoch()
            guard await app.api.account()?.accountID == postAuthorID, owner == generation else { return }
            do {
                let receipt = try await app.api.deleteComments(postID: postID, commentIDs: ids, session: session)
                guard owner == generation else { return }
                let accepted = Set(receipt.acceptedIDs)
                for row in selected where accepted.contains(row.id) {
                    if parentID == nil {
                        if let count { self.count = max(0, count - min(count, replyCounts[row.id] ?? row.replies) - 1) }
                        comments.removeAll { $0.id == row.id }; replyCounts[row.id] = nil; replyThreads[row.id] = nil
                    } else {
                        if let index = comments.firstIndex(where: { $0.id == row.id }) { comments[index].markDeleted() }
                        if let count { self.count = max(0, count - 1) }; onPostCountDelta?(-1)
                    }
                }
                selectedIDs.removeAll { accepted.contains($0) }; updateCount(); table.reloadData()
                if comments.isEmpty {
                    let empty = UILabel(); empty.text = parentID == nil ? "No comments yet." : "No replies yet."; empty.textColor = .lightGray; empty.textAlignment = .center
                    table.backgroundView = empty
                }
                if receipt.remainingIDs.isEmpty { endSelection() }
                else { showSelectionNotice("Some comments were not deleted", message: "Only confirmed deletions were applied. The remaining comments stay selected.") }
            } catch {
                guard owner == generation else { return }
                uncertainDeletion = true
                showSelectionNotice("Deletion not confirmed", message: "Your selection and draft are still here. Cancel selection and refresh the thread before trying again.")
            }
        }
    }
    private func showSelectionNotice(_ title: String, message: String) {
        guard view.window != nil, !view.isHidden, presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
    }
    private func showOptions(for comment: Comment) {
        guard !comment.isDeleted, !writing, send.isEnabled, !uncertainDeletion, !selecting, presentedViewController == nil else { return }
        let owner = generation
        let alert = UIAlertController(title: "Comment options", message: nil, preferredStyle: .alert)
        let options = CommentBehavior.options(authorID: comment.authorID, originalAuthorID: postAuthorID,
                                              accountID: accountID, depth: comment.depth, inReplies: parentID != nil)
        for option in options {
            let label: String
            switch option {
            case .reply: label = "Reply"
            case .profile: label = "Profile"
            case .report: label = "Report"
            case .delete: label = "Delete"
            case .remove: label = "Remove"
            }
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self, weak alert] _ in
                // Finish the options dismissal before presenting confirmation,
                // sign-in or a reply screen; fast offline actions exercise this.
                alert?.dismiss(animated: true) { [weak self] in
                    guard let self, owner == generation else { return }
                    switch option {
                    case .reply: requestReply(to: comment)
                    case .profile:
                        if let id = comment.authorID { navigationController?.pushViewController(ProfileController(app: app, userID: id, nickname: comment.author), animated: true) }
                    case .report: confirm(comment, kind: "report")
                    case .delete: confirm(comment, kind: "delete")
                    case .remove: confirm(comment, kind: "remove")
                    }
                }
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); present(alert, animated: true)
    }
    private var writing = false
    private func setRowActionsEnabled(_ enabled: Bool) {
        for case let cell as ClassicCommentCell in table.visibleCells { cell.setActionsEnabled(enabled) }
    }
    private func confirm(_ comment: Comment, kind: String) {
        let owner = generation
        let label = kind == "delete" ? "Delete" : kind == "remove" ? "Remove" : "Report"
        let alert = UIAlertController(title: "\(label) this comment?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: label, style: .destructive) { [weak self] _ in
            guard let self, owner == generation else { return }; commentAction(comment, kind: kind)
        })
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
                case "delete", "remove": try await app.api.deleteComment(postID: postID, commentID: comment.id, session: session)
                case "report": try await app.api.reportComment(postID: postID, commentID: comment.id, session: session)
                default: return
                }
                guard owner == generation else { return }
                if kind == "delete" || kind == "remove" {
                    if comment.id == parentID {
                        // AnswersFragment's successful root deletion removes
                        // the complete thread, reports its total, and finishes
                        // AnswersActivity. Keep late read callbacks detached.
                        let replies = count ?? comment.replies
                        onRootDeleted?(replies)
                        onPostCountDelta = nil; onCountChange = nil; refreshWhenIdle = false
                        returnAfterRootDeletion()
                        return
                    } else if parentID == nil {
                        removeMainRoot(id: comment.id, replies: replyCounts[comment.id] ?? comment.replies)
                    } else {
                        if let index = comments.firstIndex(where: { $0.id == comment.id }) { comments[index].markDeleted() }
                        if let count { self.count = max(0, count - 1); updateCount() }
                        onPostCountDelta?(-1)
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
        renderHeader()
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
