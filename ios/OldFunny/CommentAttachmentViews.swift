import UIKit

/// One actual button per Android preview hit rectangle. Stack blank space stays
/// available to the comment row's options/selection gestures.
final class CommentAttachmentsView: UIStackView {
    var onOpen: ((CommentAttachment) -> Void)?
    private var cards = [CommentAttachmentButton]()
    override init(frame: CGRect = .zero) {
        super.init(frame: frame); axis = .vertical; alignment = .leading; spacing = 6
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func bind(_ values: [CommentAttachment], commentID: String, loader: MediaLoader) {
        cards.forEach { $0.cancel(); removeArrangedSubview($0); $0.removeFromSuperview() }; cards = []
        for (index, value) in values.enumerated() {
            let card = CommentAttachmentButton(value, loader: loader)
            card.accessibilityIdentifier = "comment-attachment-\(commentID)-\(index)"
            card.onOpen = { [weak self] in self?.onOpen?(value) }
            addArrangedSubview(card); cards.append(card)
        }
        isHidden = cards.isEmpty
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let available = bounds.width >= 64 ? bounds.width : max(64, (window?.bounds.width ?? 390) - 96)
        measure(availableWidth: available)
    }
    func measure(availableWidth available: CGFloat) {
        let width = max(1, Int((0.8 * min(320, max(64, available))).rounded()))
        cards.forEach { $0.size(maxWidth: width) }
    }
    func cancel() { cards.forEach { $0.cancel() } }
}

private final class CommentAttachmentButton: UIButton {
    let value: CommentAttachment
    var onOpen: (() -> Void)?
    private let bitmap = CommentPreviewBitmap(), message = UILabel(), badge = UILabel()
    private var request: Task<Void, Never>?
    private var cardWidth: NSLayoutConstraint!, cardHeight: NSLayoutConstraint!
    init(_ value: CommentAttachment, loader: MediaLoader) {
        self.value = value; super.init(frame: .zero)
        layer.cornerRadius = 3; clipsToBounds = true
        let color = value.backgroundARGB
        backgroundColor = UIColor(red: CGFloat((color >> 16) & 255) / 255, green: CGFloat((color >> 8) & 255) / 255, blue: CGFloat(color & 255) / 255, alpha: CGFloat(color >> 24) / 255)
        bitmap.fromTop = value.badge != "VIDEO"
        message.font = ClassicTheme.font(12); message.textColor = UIColor(white: 1 / 3, alpha: 1)
        message.textAlignment = .center; message.numberOfLines = 2
        badge.text = value.badge == "VIDEO" ? "▶" : value.badge; badge.font = ClassicTheme.font(10, bold: true)
        badge.textColor = .white; badge.textAlignment = .center; badge.backgroundColor = UIColor.black.withAlphaComponent(0.63)
        badge.layer.cornerRadius = 14; badge.clipsToBounds = true; badge.isHidden = value.badge.isEmpty || value.unavailable
        for view in [bitmap as UIView, message, badge] { view.isUserInteractionEnabled = false; view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        cardWidth = widthAnchor.constraint(equalToConstant: 200); cardHeight = heightAnchor.constraint(equalToConstant: 150)
        cardWidth.priority = .init(999); cardHeight.priority = .init(999)
        NSLayoutConstraint.activate([
            cardWidth, cardHeight, bitmap.leadingAnchor.constraint(equalTo: leadingAnchor), bitmap.trailingAnchor.constraint(equalTo: trailingAnchor),
            bitmap.topAnchor.constraint(equalTo: topAnchor), bitmap.bottomAnchor.constraint(equalTo: bottomAnchor),
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4), message.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6), badge.widthAnchor.constraint(equalToConstant: 28), badge.heightAnchor.constraint(equalToConstant: 28)
        ])
        accessibilityLabel = "Open attached post"; isAccessibilityElement = true
        accessibilityValue = value.badge.isEmpty ? nil : value.badge
        addTarget(self, action: #selector(open), for: .touchUpInside)
        if value.unavailable { unavailable("Post unavailable") }
        else if let url = value.previewURL {
            let agent = Wire.apiUserAgent(systemVersion: UIDevice.current.systemVersion, model: UIDevice.current.model)
            request = Task { [weak self] in
                do {
                    let image = try await loader.commentImage(url, userAgent: agent); try Task.checkCancellation()
                    self?.bitmap.image = image
                } catch is CancellationError { }
                catch { if !Task.isCancelled { self?.unavailable("Preview unavailable - tap to open") } }
            }
        } else { unavailable("Preview unavailable - tap to open") }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { request?.cancel() }
    func cancel() { request?.cancel(); request = nil }
    func size(maxWidth: Int) {
        guard let size = try? CommentPreviewCrop.size(imageWidth: value.width, imageHeight: value.height, maxWidth: maxWidth, minHeight: 58) else { return }
        if cardWidth.constant != CGFloat(size.width) { cardWidth.constant = CGFloat(size.width) }
        if cardHeight.constant != CGFloat(size.height) { cardHeight.constant = CGFloat(size.height) }
    }
    private func unavailable(_ text: String) {
        message.text = text; backgroundColor = UIColor(white: 222 / 255, alpha: 1)
        accessibilityValue = text + (value.badge.isEmpty ? "" : "; " + value.badge)
    }
    @objc private func open() { onOpen?() }
}

private final class CommentPreviewBitmap: UIView {
    var image: UIImage? { didSet { setNeedsDisplay() } }
    var fromTop = true
    override init(frame: CGRect = .zero) { super.init(frame: frame); isOpaque = false; backgroundColor = .clear; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let image, let cg = image.cgImage, bounds.width >= 1, bounds.height >= 1,
              let crop = try? CommentPreviewCrop.source(imageWidth: cg.width, imageHeight: cg.height, width: Int(bounds.width.rounded()), height: Int(bounds.height.rounded()), fromTop: fromTop) else { return }
        let scaleX = bounds.width / CGFloat(crop.right - crop.left), scaleY = bounds.height / CGFloat(crop.bottom - crop.top)
        image.draw(in: CGRect(x: -CGFloat(crop.left) * scaleX, y: -CGFloat(crop.top) * scaleY, width: CGFloat(cg.width) * scaleX, height: CGFloat(cg.height) * scaleY))
    }
}
