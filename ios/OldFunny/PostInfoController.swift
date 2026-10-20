import UIKit

final class PostInfoController: ClassicScreenController {
    private let app: AppContext
    private let post: Post
    var onClose: (() -> Void)?
    init(app: AppContext, post: Post) { self.app = app; self.post = post; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); classicBar.setTitle("Post information")
        view.accessibilityIdentifier = "post-information"
        classicBar.onLeading = { [weak self] in self?.onClose?() }
        classicBar.trailing.setImage(ClassicGlyph.share.image, for: .normal); classicBar.trailing.accessibilityLabel = "Share post link"
        classicBar.onTrailing = { [weak self] in self?.share() }
        let scroll = UIScrollView(), rows = UIStackView(); rows.axis = .vertical; rows.spacing = 18
        scroll.translatesAutoresizingMaskIntoConstraints = false; rows.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scroll); scroll.addSubview(rows)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), scroll.topAnchor.constraint(equalTo: contentView.topAnchor), scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 18), rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -18), rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 22), rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -22), rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -36)
        ])
        func user(_ name: String, _ id: String?) {
            let button = UIButton(type: .custom); button.setTitle(name, for: .normal); button.setTitleColor(ClassicTheme.blue, for: .normal)
            button.titleLabel?.font = ClassicTheme.font(19, bold: true); button.contentHorizontalAlignment = .leading
            button.isEnabled = id != nil; button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in
                guard let self, let id else { return }
                navigationController?.pushViewController(FeedController(app: app, feed: .featured, timelineID: id, profileName: name), animated: true)
            }, for: .touchUpInside); rows.addArrangedSubview(button)
        }
        func line(_ text: String) {
            let label = UILabel(); label.text = text; label.numberOfLines = 0
            label.font = ClassicTheme.font(16); label.textColor = ClassicTheme.text; rows.addArrangedSubview(label)
        }
        user(post.author, post.authorID)
        if let name = post.originalAuthor { line("Originally by"); user(name, post.originalAuthorID) }
        if let date = post.date { line(DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .short)) }
        line("\(post.smiles) smiles     \(post.republishes) republishes\n\(post.views) views     \(post.comments) comments")
        if !post.title.isEmpty { line(post.title) }; if !post.body.isEmpty { line(post.body) }
        if !post.tags.isEmpty { line(post.tags.map { "#" + $0 }.joined(separator: "  ")) }
    }
    private func share() {
        let url = URL(string: "https://ifunny.co/\(post.isVideo ? "video" : "picture")/\(post.id)")!
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = classicBar.trailing; present(sheet, animated: true)
    }
}
