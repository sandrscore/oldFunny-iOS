import UIKit

/// Small code-drawn controls keep the classic flat chrome independent of the
/// current iOS button style. Only the already-reviewed recovered icons are used.
@MainActor
enum ClassicGlyph {
    case menu, back, refresh, share, profile, account, send, chevron, smile, unsmile, comment, subscription
    var image: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.white.setStroke(); UIColor.white.setFill()
            let path = UIBezierPath(); path.lineWidth = 2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            func line(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.addLine(to: b) }
            switch self {
            case .menu:
                for y in [6, 12, 18] { line(CGPoint(x: 3, y: CGFloat(y)), CGPoint(x: 21, y: CGFloat(y))) }
            case .back:
                line(CGPoint(x: 20, y: 12), CGPoint(x: 4, y: 12))
                line(CGPoint(x: 11, y: 5), CGPoint(x: 4, y: 12)); path.addLine(to: CGPoint(x: 11, y: 19))
            case .refresh:
                path.addArc(withCenter: CGPoint(x: 12, y: 12), radius: 8, startAngle: 0.3, endAngle: 5.45, clockwise: true)
                line(CGPoint(x: 20, y: 3), CGPoint(x: 20, y: 9)); path.addLine(to: CGPoint(x: 14, y: 9))
            case .share:
                line(CGPoint(x: 6, y: 12), CGPoint(x: 18, y: 5)); line(CGPoint(x: 6, y: 12), CGPoint(x: 18, y: 19))
                for point in [CGPoint(x: 5, y: 12), CGPoint(x: 19, y: 4), CGPoint(x: 19, y: 20)] {
                    UIBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
                }
            case .profile:
                UIBezierPath(ovalIn: CGRect(x: 8, y: 2, width: 8, height: 10)).fill()
                path.move(to: CGPoint(x: 3, y: 22)); path.addCurve(to: CGPoint(x: 21, y: 22), controlPoint1: CGPoint(x: 3, y: 10), controlPoint2: CGPoint(x: 21, y: 10)); path.close(); path.fill()
            case .account:
                path.addArc(withCenter: CGPoint(x: 12, y: 12), radius: 9, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                for x in [7, 12, 17] { UIBezierPath(ovalIn: CGRect(x: x - 1, y: 11, width: 2, height: 2)).fill() }
            case .send:
                line(CGPoint(x: 3, y: 12), CGPoint(x: 21, y: 12))
                line(CGPoint(x: 14, y: 5), CGPoint(x: 21, y: 12)); path.addLine(to: CGPoint(x: 14, y: 19))
            case .chevron:
                path.move(to: CGPoint(x: 8, y: 5)); path.addLine(to: CGPoint(x: 15, y: 12)); path.addLine(to: CGPoint(x: 8, y: 19))
            case .smile, .unsmile:
                UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 20, height: 20)).fill()
                context.cgContext.saveGState(); context.cgContext.setBlendMode(.clear)
                for x in [8, 15] { UIBezierPath(ovalIn: CGRect(x: CGFloat(x) - 1, y: 7, width: 2, height: 3)).fill() }
                let mouth = UIBezierPath(); mouth.lineWidth = 1.5
                if self == .smile { mouth.addArc(withCenter: CGPoint(x: 12, y: 12), radius: 5, startAngle: 0.2, endAngle: .pi - 0.2, clockwise: true) }
                else { mouth.move(to: CGPoint(x: 7, y: 17)); mouth.addQuadCurve(to: CGPoint(x: 17, y: 17), controlPoint: CGPoint(x: 12, y: 10)) }
                mouth.stroke()
                context.cgContext.restoreGState()
            case .comment:
                UIBezierPath(roundedRect: CGRect(x: 2, y: 3, width: 20, height: 16), cornerRadius: 7).fill()
                let tail = UIBezierPath(); tail.move(to: CGPoint(x: 6, y: 16)); tail.addLine(to: CGPoint(x: 4, y: 23)); tail.addLine(to: CGPoint(x: 13, y: 17)); tail.close(); tail.fill()
                context.cgContext.saveGState(); context.cgContext.setBlendMode(.clear)
                let marks = UIBezierPath(); marks.lineWidth = 1.3
                marks.move(to: CGPoint(x: 7, y: 9)); marks.addLine(to: CGPoint(x: 17, y: 9)); marks.move(to: CGPoint(x: 7, y: 13)); marks.addLine(to: CGPoint(x: 13, y: 13)); marks.stroke()
                context.cgContext.restoreGState()
            case .subscription:
                UIBezierPath(roundedRect: CGRect(x: 2, y: 3, width: 20, height: 18), cornerRadius: 5).fill()
                context.cgContext.saveGState(); context.cgContext.setBlendMode(.clear)
                let check = UIBezierPath(); check.lineWidth = 2.2; check.lineCapStyle = .round; check.lineJoinStyle = .round
                check.move(to: CGPoint(x: 7, y: 12)); check.addLine(to: CGPoint(x: 11, y: 16)); check.addLine(to: CGPoint(x: 17, y: 8)); check.stroke()
                context.cgContext.restoreGState()
            }
            path.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }
}

final class ClassicNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { topViewController }
}

final class ClassicIconButton: UIControl {
    private let symbol = UIImageView()
    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        symbol.contentMode = .scaleAspectFit; symbol.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbol)
        NSLayoutConstraint.activate([symbol.centerXAnchor.constraint(equalTo: centerXAnchor), symbol.centerYAnchor.constraint(equalTo: centerYAnchor), symbol.widthAnchor.constraint(equalToConstant: 24), symbol.heightAnchor.constraint(equalToConstant: 24)])
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setImage(_ image: UIImage?, for state: UIControl.State) { symbol.image = image }
    override func tintColorDidChange() { super.tintColorDidChange(); symbol.tintColor = tintColor }
    override var isEnabled: Bool { didSet { alpha = isEnabled ? 1 : 0.4 } }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.5 : (isEnabled ? 1 : 0.4) } }
}

final class ClassicBar: UIView {
    let leading = ClassicTheme.button(.back, label: "Back")
    let trailing = ClassicTheme.button(.refresh, label: "Refresh")
    let centerContent = UIView()
    var onLeading: (() -> Void)?, onTrailing: (() -> Void)?
    override init(frame: CGRect = .zero) {
        super.init(frame: frame); backgroundColor = ClassicTheme.bar
        let row = UIStackView(arrangedSubviews: [leading, centerContent, trailing]); row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            row.centerYAnchor.constraint(equalTo: centerYAnchor), row.heightAnchor.constraint(equalToConstant: 44)
        ])
        leading.addTarget(self, action: #selector(leftTapped), for: .touchUpInside)
        trailing.addTarget(self, action: #selector(rightTapped), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func leftTapped() { onLeading?() }
    @objc private func rightTapped() { onTrailing?() }
    func setCenter(_ view: UIView) {
        centerContent.subviews.forEach { $0.removeFromSuperview() }; centerContent.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: centerContent.leadingAnchor), view.trailingAnchor.constraint(equalTo: centerContent.trailingAnchor), view.topAnchor.constraint(equalTo: centerContent.topAnchor), view.bottomAnchor.constraint(equalTo: centerContent.bottomAnchor)])
    }
    func setTitle(_ title: String) {
        let label = UILabel(); label.text = title; label.textColor = .white
        label.font = ClassicTheme.font(19, bold: true); label.adjustsFontForContentSizeCategory = true
        setCenter(label)
    }
}

class ClassicScreenController: UIViewController {
    let classicBar = ClassicBar(), contentView = UIView()
    private var barHeight: NSLayoutConstraint!
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = ClassicTheme.bar
        // Create the default symbol after this controller has its UIKit view
        // context, as the media/info headers already do for their symbols.
        classicBar.trailing.setImage(ClassicGlyph.refresh.image, for: .normal)
        classicBar.trailing.tintColor = .white
        contentView.backgroundColor = ClassicTheme.background
        for item in [classicBar, contentView] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        barHeight = classicBar.heightAnchor.constraint(equalToConstant: 52)
        NSLayoutConstraint.activate([
            classicBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), classicBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            classicBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), barHeight,
            contentView.topAnchor.constraint(equalTo: classicBar.bottomAnchor), contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor), contentView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        classicBar.onLeading = { [weak self] in self?.navigationController?.popViewController(animated: true) }
    }
    func setClassicBarHidden(_ hidden: Bool) { classicBar.isHidden = hidden; barHeight.constant = hidden ? 0 : 52 }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: false) }
}

final class RemoteAvatarView: UIImageView {
    private var task: Task<Void, Never>?
    override init(frame: CGRect = .zero) {
        super.init(frame: frame); contentMode = .scaleAspectFill; clipsToBounds = true
        backgroundColor = UIColor(white: 0.27, alpha: 1); isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }
    override func layoutSubviews() { super.layoutSubviews(); layer.cornerRadius = bounds.width / 2 }
    func set(_ url: URL?, loader: MediaLoader) {
        task?.cancel(); image = ClassicGlyph.profile.image; tintColor = ClassicTheme.muted
        guard let url else { return }
        task = Task { [weak self] in
            guard let loaded = try? await loader.image(url), !Task.isCancelled else { return }
            self?.image = loaded
        }
    }
}

final class AuthorHeader: UIControl {
    private let avatar = RemoteAvatarView()
    private var avatarWidth: NSLayoutConstraint!
    private let name = UILabel(), detail = UILabel()
    var action: (() -> Void)?
    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        name.textColor = .white; name.font = ClassicTheme.font(17); name.lineBreakMode = .byTruncatingTail
        detail.textColor = ClassicTheme.muted; detail.font = ClassicTheme.font(11)
        let names = UIStackView(arrangedSubviews: [name, detail]); names.axis = .vertical; names.spacing = 1
        let row = UIStackView(arrangedSubviews: [avatar, names]); row.spacing = 8; row.alignment = .center
        row.isUserInteractionEnabled = false; row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
        avatarWidth = avatar.widthAnchor.constraint(equalToConstant: 30)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatarWidth, avatar.heightAnchor.constraint(equalToConstant: 30)
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside); isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() { action?() }
    func update(post: Post?, section: String, loader: MediaLoader) {
        name.text = post?.author ?? section; detail.text = section; detail.isHidden = post == nil
        avatarWidth.constant = post == nil ? 0 : 30
        avatar.isHidden = post == nil; avatar.set(post?.authorAvatarURL, loader: loader)
        isEnabled = post?.authorID != nil; accessibilityLabel = post.map { "\($0.author), \(section), open profile" } ?? section
    }
}
