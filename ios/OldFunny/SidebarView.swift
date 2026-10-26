import UIKit

final class SidebarView: UIView {
    enum Destination { case feed(Feed), profile, account }
    var onSelect: ((Destination) -> Void)?, onClose: (() -> Void)?
    var onSubscriptionsHold: (() -> Void)?
    private weak var subscriptionsRow: UIButton?
    private let subscriptionsBadge = UILabel()
    private let panel = UIView()
    private let rows = UIStackView()
    init(selected: Feed) {
        super.init(frame: .zero); accessibilityViewIsModal = true
        let shade = UIControl(); shade.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        shade.addTarget(self, action: #selector(close), for: .touchUpInside)
        panel.backgroundColor = ClassicTheme.drawer
        panel.layer.shadowColor = UIColor.black.cgColor; panel.layer.shadowOpacity = 0.45; panel.layer.shadowRadius = 12
        rows.axis = .vertical; rows.spacing = 0
        for item in [shade, panel, rows] { item.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(shade); addSubview(panel); panel.addSubview(rows)
        let preferredWidth = panel.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.78); preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            shade.topAnchor.constraint(equalTo: topAnchor), shade.bottomAnchor.constraint(equalTo: bottomAnchor),
            shade.leadingAnchor.constraint(equalTo: leadingAnchor), shade.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor), panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            preferredWidth, panel.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            rows.leadingAnchor.constraint(equalTo: panel.leadingAnchor), rows.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            rows.topAnchor.constraint(equalTo: panel.topAnchor, constant: 6), rows.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6)
        ])
        addRow("Featured", image: ClassicTheme.image("featured", fallback: "sparkles"), selected: selected == .featured, destination: .feed(.featured))
        addRow("Collective", image: UIImage(systemName: "square.stack.fill"), selected: selected == .collective, destination: .feed(.collective))
        addRow("Subscriptions", image: ClassicTheme.image("subscribe", fallback: "checkmark.circle.fill"), selected: selected == .subscriptions, destination: .feed(.subscriptions))
        addRow("Profile", image: ClassicGlyph.profile.image, selected: false, destination: .profile)
        let separator = UIView(); separator.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true; rows.addArrangedSubview(separator)
        addRow("Account", image: ClassicGlyph.account.image, selected: false, destination: .account)
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(close)); swipe.direction = .left; panel.addGestureRecognizer(swipe)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func addRow(_ title: String, image: UIImage?, selected: Bool, destination: Destination) {
        let row = UIButton(type: .custom)
        row.setTitle(title, for: .normal); row.setTitleColor(selected ? ClassicTheme.yellow : ClassicTheme.text, for: .normal)
        row.titleLabel?.font = ClassicTheme.font(17); row.contentHorizontalAlignment = .leading
        row.setImage(image, for: .normal); row.tintColor = selected ? ClassicTheme.yellow : ClassicTheme.text
        row.imageView?.contentMode = .scaleAspectFit
        var configuration = UIButton.Configuration.plain(); configuration.image = image
        configuration.imagePadding = 15; configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 12)
        configuration.title = title; configuration.baseForegroundColor = selected ? ClassicTheme.yellow : ClassicTheme.text
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var value = attributes; value.font = ClassicTheme.font(17); return value }
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22)
        // Render the existing icon at the classic menu size without changing its resource.
        if let image { configuration.image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in image.draw(in: CGRect(x: 1, y: 1, width: 22, height: 22)) }.withRenderingMode(.alwaysTemplate) }
        row.configuration = configuration
        if case .feed(.subscriptions) = destination {
            subscriptionsRow = row
            subscriptionsBadge.font = ClassicTheme.font(13, bold: true); subscriptionsBadge.textColor = .white
            subscriptionsBadge.backgroundColor = .systemRed; subscriptionsBadge.textAlignment = .center
            subscriptionsBadge.layer.cornerRadius = 10; subscriptionsBadge.clipsToBounds = true
            subscriptionsBadge.isHidden = true; subscriptionsBadge.translatesAutoresizingMaskIntoConstraints = false
            subscriptionsBadge.isUserInteractionEnabled = false; subscriptionsBadge.isAccessibilityElement = false
            row.addSubview(subscriptionsBadge)
            NSLayoutConstraint.activate([subscriptionsBadge.centerYAnchor.constraint(equalTo: row.centerYAnchor), subscriptionsBadge.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12), subscriptionsBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 30), subscriptionsBadge.heightAnchor.constraint(equalToConstant: 22)])
            row.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(subscriptionsHold(_:))))
            row.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Mark as viewed", target: self, selector: #selector(accessibleSubscriptionsHold))]
        }
        row.heightAnchor.constraint(equalToConstant: 52).isActive = true
        row.accessibilityTraits = selected ? [.button, .selected] : .button
        row.addAction(UIAction { [weak self] _ in self?.onSelect?(destination) }, for: .touchUpInside)
        rows.addArrangedSubview(row)
    }
    func setSubscriptionsUnread(_ count: Int?, clearing: Bool) {
        subscriptionsBadge.isHidden = count == nil || count == 0
        subscriptionsBadge.text = count.map { " \($0) " }
        subscriptionsRow?.accessibilityValue = clearing ? "Marking as viewed" : count.map { "\($0) unread" }
    }
    @objc private func subscriptionsHold(_ gesture: UILongPressGestureRecognizer) { if gesture.state == .began { onSubscriptionsHold?() } }
    @objc private func accessibleSubscriptionsHold() -> Bool { onSubscriptionsHold?(); return true }
    @objc private func close() { onClose?() }
}
