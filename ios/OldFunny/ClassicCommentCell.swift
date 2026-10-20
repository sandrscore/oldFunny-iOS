import UIKit

final class ClassicCommentCell: UITableViewCell {
    private let avatar = RemoteAvatarView(), name = UIButton(type: .custom)
    private let date = UILabel(), body = UILabel(), replies = UILabel()
    private let preview = UIButton(type: .custom), picture = UIImageView()
    private let smile = ClassicCounterButton(), unsmile = ClassicTheme.button(.unsmile, label: "Unsmile comment")
    private var previewHeight: NSLayoutConstraint!
    private var imageTask: Task<Void, Never>?
    private var commentID: String?
    var onAuthor: (() -> Void)?, onAttachment: (() -> Void)?
    var onSmile: (() -> Void)?, onUnsmile: (() -> Void)?
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = ClassicTheme.bar; selectionStyle = .none
        name.titleLabel?.font = ClassicTheme.font(15, bold: true); name.contentHorizontalAlignment = .leading
        name.setTitleColor(ClassicTheme.blue, for: .normal); name.addTarget(self, action: #selector(authorTapped), for: .touchUpInside)
        date.font = ClassicTheme.font(11); date.textColor = ClassicTheme.muted
        body.font = ClassicTheme.font(15); body.textColor = ClassicTheme.text; body.numberOfLines = 0; body.adjustsFontForContentSizeCategory = true
        replies.font = ClassicTheme.font(12); replies.textColor = ClassicTheme.blue
        picture.contentMode = .scaleAspectFill; picture.clipsToBounds = true; picture.backgroundColor = ClassicTheme.background
        picture.translatesAutoresizingMaskIntoConstraints = false; preview.addSubview(picture)
        NSLayoutConstraint.activate([picture.leadingAnchor.constraint(equalTo: preview.leadingAnchor), picture.trailingAnchor.constraint(equalTo: preview.trailingAnchor), picture.topAnchor.constraint(equalTo: preview.topAnchor), picture.bottomAnchor.constraint(equalTo: preview.bottomAnchor)])
        preview.accessibilityLabel = "Open attached post"; preview.addTarget(self, action: #selector(attachmentTapped), for: .touchUpInside)
        previewHeight = preview.heightAnchor.constraint(equalToConstant: 160); previewHeight.priority = .defaultHigh; previewHeight.isActive = true
        smile.icon = ClassicGlyph.smile.image; smile.addTarget(self, action: #selector(smileTapped), for: .touchUpInside)
        unsmile.addTarget(self, action: #selector(unsmileTapped), for: .touchUpInside)
        let reactions = UIStackView(arrangedSubviews: [smile, unsmile, UIView()]); reactions.spacing = 3; reactions.alignment = .center
        let stack = UIStackView(arrangedSubviews: [name, date, body, preview, replies, reactions]); stack.axis = .vertical; stack.spacing = 4
        for item in [avatar, stack] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12), avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 9),
            avatar.widthAnchor.constraint(equalToConstant: 32), avatar.heightAnchor.constraint(equalToConstant: 32),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10), stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { imageTask?.cancel() }
    override func prepareForReuse() { super.prepareForReuse(); imageTask?.cancel(); commentID = nil; picture.image = nil; onAuthor = nil; onAttachment = nil; onSmile = nil; onUnsmile = nil }
    func bind(_ comment: Comment, loader: MediaLoader, replyCount: Int? = nil) {
        imageTask?.cancel(); commentID = comment.id
        name.setTitle(comment.author, for: .normal); name.isEnabled = comment.authorID != nil
        avatar.set(comment.authorAvatarURL, loader: loader)
        if let value = comment.date { date.text = DateFormatter.localizedString(from: value, dateStyle: .short, timeStyle: .none); date.isHidden = false }
        else { date.text = nil; date.isHidden = true }
        body.text = comment.text; body.isHidden = comment.text.isEmpty
        let count = replyCount ?? comment.replies
        replies.text = "\(count) replies"; replies.isHidden = count == 0
        smile.count = comment.displayedScore ?? 0; smile.showsCount = comment.displayedScore != nil
        smile.tintColor = comment.isSmiled ? ClassicTheme.yellow : .white
        smile.accessibilityLabel = "\(comment.displayedScore.map { "\($0) comment score, " } ?? "")\(comment.isSmiled ? "remove comment smile" : "Smile comment")"
        smile.accessibilityIdentifier = "comment-smile-\(comment.id)"
        unsmile.tintColor = comment.isUnsmiled ? ClassicTheme.yellow : .white
        unsmile.accessibilityLabel = comment.isUnsmiled ? "Remove comment unsmile" : "Unsmile comment"
        unsmile.accessibilityIdentifier = "comment-unsmile-\(comment.id)"
        preview.isHidden = comment.attachments.isEmpty; picture.image = nil
        if let post = comment.attachments.first, let url = post.posterURL ?? post.mediaURL {
            previewHeight.constant = min(240, max(100, max(200, contentView.bounds.width - 65) * CGFloat(post.height / post.width)))
            imageTask = Task { [weak self] in
                guard let loaded = try? await loader.image(url), !Task.isCancelled, self?.commentID == comment.id else { return }
                self?.picture.image = loaded
            }
        }
    }
    @objc private func authorTapped() { onAuthor?() }
    @objc private func attachmentTapped() { onAttachment?() }
    @objc private func smileTapped() { onSmile?() }
    @objc private func unsmileTapped() { onUnsmile?() }
    func setActionsEnabled(_ enabled: Bool) { smile.isEnabled = enabled; unsmile.isEnabled = enabled }
}

final class ClassicTextField: UITextField {
    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: 10, dy: 4) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { textRect(forBounds: bounds) }
}
