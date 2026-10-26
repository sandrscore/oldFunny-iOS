import UIKit

/// Android comments/a routes deleted nonroot replies to comment_deleted_item,
/// a centered caption with 15dp padding and no live-comment child controls.
final class DeletedCommentCell: UITableViewCell {
    private let caption = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = ClassicTheme.bar; selectionStyle = .none
        caption.text = "Comment was eaten by a black hole"
        caption.font = ClassicTheme.font(15); caption.textColor = UIColor(red: 108 / 255, green: 108 / 255, blue: 115 / 255, alpha: 1)
        caption.textAlignment = .center; caption.numberOfLines = 1; caption.lineBreakMode = .byTruncatingMiddle
        caption.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(caption)
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            caption.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            caption.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            caption.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func bind(id: String) {
        accessibilityIdentifier = "comment-row-" + id
        caption.accessibilityIdentifier = "comment-body-" + id
    }
}
