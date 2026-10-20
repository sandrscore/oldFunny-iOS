import UIKit

final class CommentsController: ClassicScreenController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let app: AppContext
    private let postID: String
    private let parentID: String?
    private let table = UITableView(frame: .zero, style: .plain)
    private let text = ClassicTextField(), send = ClassicTheme.button(.send, label: "Send comment")
    private let count: Int?
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var comments: [Comment] = [], nextCursor: String?, usedCursors = Set<String>()
    private var task: Task<Void, Never>?, loading = false
    private var generation = UUID()
    init(app: AppContext, postID: String, parentID: String? = nil, count: Int? = nil) {
        self.app = app; self.postID = postID; self.parentID = parentID; self.count = count
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad()
        let kind = parentID == nil ? "comments" : "replies"
        classicBar.setTitle(count.map { "\($0) \(kind)" } ?? (parentID == nil ? "Comments" : "Replies"))
        classicBar.onTrailing = { [weak self] in self?.refresh() }
        table.dataSource = self; table.delegate = self; table.backgroundColor = ClassicTheme.background
        table.register(ClassicCommentCell.self, forCellReuseIdentifier: "comment"); table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 90
        table.keyboardDismissMode = .interactive
        let refreshControl = UIRefreshControl(); refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged); table.refreshControl = refreshControl
        spinner.hidesWhenStopped = true; table.tableFooterView = spinner
        text.placeholder = "Say something funny…"; text.borderStyle = .none; text.textColor = UIColor(white: 0.25, alpha: 1)
        text.font = ClassicTheme.font(15); text.layer.cornerRadius = 5
        text.backgroundColor = UIColor(white: 0.90, alpha: 1); text.delegate = self; text.returnKeyType = .send
        send.tintColor = ClassicTheme.muted
        send.addTarget(self, action: #selector(postComment), for: .touchUpInside)
        let composer = UIStackView(arrangedSubviews: [text, send]); composer.spacing = 8; composer.alignment = .center
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
        load(replacing: true)
    }
    @objc private func refresh() { load(replacing: true) }
    @objc private func accountChanged() {
        task?.cancel(); generation = UUID(); loading = false
        comments = []; nextCursor = nil; usedCursors = []; text.text = nil
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
            guard let self, let post = comment.attachments.first else { return }
            navigationController?.pushViewController(PostController(app: app, post: post, index: 0, source: "prof"), animated: true)
        }
        cell.onAuthor = { [weak self] in
            guard let self, let id = comment.authorID else { return }
            navigationController?.pushViewController(FeedController(app: app, feed: .featured, timelineID: id, profileName: comment.author), animated: true)
        }
        return cell
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= comments.count - 4 { load(replacing: false) }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        table.deselectRow(at: indexPath, animated: true)
        let comment = comments[indexPath.row]
        if parentID == nil {
            navigationController?.pushViewController(CommentsController(app: app, postID: postID, parentID: comment.id, count: comment.replies), animated: true)
        }
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { postComment(); return false }
    @objc private func postComment() {
        guard send.isEnabled else { return }
        let snapshot = text.text ?? ""
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, snapshot.utf16.count <= 300 else { showError(ClientError.invalidInput); return }
        send.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer { send.isEnabled = true }
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            do {
                try await app.api.sendComment(postID: postID, parentID: parentID, text: snapshot)
                if text.text == snapshot { text.text = "" }
                view.endEditing(true)
                if !loading { load(replacing: true) }
            } catch {
                // A network failure may follow server acceptance. Keep the draft
                // and ask the user to check the thread before any manual retry.
                let alert = UIAlertController(title: "Comment not confirmed", message: "Your text is still here. Refresh the thread and check whether it appeared before sending again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
            }
        }
    }
}
