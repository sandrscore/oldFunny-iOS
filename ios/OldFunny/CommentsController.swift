import UIKit

final class CommentsController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let app: AppContext
    private let postID: String
    private let parentID: String?
    private let table = UITableView(frame: .zero, style: .plain)
    private let text = UITextField(), send = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var comments: [Comment] = [], next: String?, usedCursors = Set<String>()
    private var task: Task<Void, Never>?, loading = false
    private var generation = UUID()
    init(app: AppContext, postID: String, parentID: String? = nil) {
        self.app = app; self.postID = postID; self.parentID = parentID
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); title = parentID == nil ? "Comments" : "Replies"; view.backgroundColor = ClassicTheme.background
        table.dataSource = self; table.delegate = self; table.backgroundColor = ClassicTheme.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "comment")
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 90
        table.keyboardDismissMode = .interactive
        let refreshControl = UIRefreshControl(); refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged); table.refreshControl = refreshControl
        spinner.hidesWhenStopped = true; table.tableFooterView = spinner
        text.placeholder = "Write a comment…"; text.borderStyle = .roundedRect; text.textColor = .black
        text.backgroundColor = .white; text.delegate = self; text.returnKeyType = .send
        send.setImage(UIImage(systemName: "paperplane.fill"), for: .normal); send.tintColor = ClassicTheme.yellow
        send.addTarget(self, action: #selector(postComment), for: .touchUpInside)
        let composer = UIStackView(arrangedSubviews: [text, send]); composer.spacing = 10
        composer.translatesAutoresizingMaskIntoConstraints = false; table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table); view.addSubview(composer)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
            composer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            composer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            composer.heightAnchor.constraint(equalToConstant: 42), send.widthAnchor.constraint(equalToConstant: 44)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: .oldFunnyAccountChanged, object: nil)
        load(replacing: true)
    }
    @objc private func refresh() { load(replacing: true) }
    @objc private func accountChanged() {
        task?.cancel(); generation = UUID(); loading = false
        comments = []; next = nil; usedCursors = []; text.text = nil
        table.reloadData(); load(replacing: true)
    }
    private func load(replacing: Bool) {
        guard !loading, replacing || next != nil else { return }
        loading = true; spinner.startAnimating(); let owner = generation
        let cursor = replacing ? nil : next
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
                if let candidate = page.paging.next, usedCursors.insert(candidate).inserted { next = candidate } else { next = nil }
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
        let cell = table.dequeueReusableCell(withIdentifier: "comment", for: indexPath)
        cell.backgroundColor = ClassicTheme.background
        var configuration = cell.defaultContentConfiguration()
        configuration.text = comment.author; configuration.textProperties.color = ClassicTheme.yellow
        var body = comment.text
        if !comment.attachments.isEmpty { body += (body.isEmpty ? "" : "\n") + "▧ Attached post" }
        if comment.replies > 0 { body += "\n\(comment.replies) replies" }
        configuration.secondaryText = body; configuration.secondaryTextProperties.color = .white
        configuration.secondaryTextProperties.numberOfLines = 0; cell.contentConfiguration = configuration
        cell.accessoryType = comment.attachments.isEmpty && comment.replies == 0 ? .none : .disclosureIndicator
        return cell
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= comments.count - 4 { load(replacing: false) }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        table.deselectRow(at: indexPath, animated: true)
        let comment = comments[indexPath.row]
        let actions = UIAlertController(title: comment.author, message: nil, preferredStyle: .actionSheet)
        if let post = comment.attachments.first {
            actions.addAction(UIAlertAction(title: "View attached post", style: .default) { [weak self] _ in
                guard let self else { return }
                navigationController?.pushViewController(PostController(app: app, post: post, index: 0, source: "prof"), animated: true)
            })
        }
        if parentID == nil {
            actions.addAction(UIAlertAction(title: "Replies", style: .default) { [weak self] _ in
                guard let self else { return }
                navigationController?.pushViewController(CommentsController(app: app, postID: postID, parentID: comment.id), animated: true)
            })
        }
        actions.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        actions.popoverPresentationController?.sourceView = table.cellForRow(at: indexPath)
        present(actions, animated: true)
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
