import UIKit

@MainActor
enum ClassicTheme {
    static let yellow = UIColor(red: 1, green: 0.76, blue: 0.24, alpha: 1)
    static let background = UIColor(red: 0.098, green: 0.098, blue: 0.106, alpha: 1)
    static let bar = UIColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1)
    static let drawer = UIColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 1)
    static let muted = UIColor(white: 0.49, alpha: 1)
    static let text = UIColor(white: 0.86, alpha: 1)
    static let blue = UIColor(red: 0.30, green: 0.61, blue: 0.77, alpha: 1)
    static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        let face = UIFont(name: bold ? "HelveticaNeue-Medium" : "HelveticaNeue", size: size) ?? .systemFont(ofSize: size)
        return UIFontMetrics.default.scaledFont(for: face, maximumPointSize: size * 1.35)
    }
    static func install() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bar
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.boldSystemFont(ofSize: 19)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = .white
        UIBarButtonItem.appearance().tintColor = .white
    }
    static func image(_ name: String, fallback: String) -> UIImage? {
        // These recovered catalog renditions are fully transparent placeholders.
        // Use native vector equivalents while preserving the reviewed PNGs.
        switch name {
        case "smile": return ClassicGlyph.smile.image
        case "comments": return ClassicGlyph.comment.image
        case "subscribe": return ClassicGlyph.subscription.image
        default: break
        }
        return UIImage(named: name)?.withRenderingMode(.alwaysTemplate) ?? UIImage(systemName: fallback)
    }
    static func button(_ glyph: ClassicGlyph, label: String) -> ClassicIconButton {
        let button = ClassicIconButton()
        button.setImage(glyph.image, for: .normal); button.tintColor = .white
        button.accessibilityLabel = label
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }
}

extension UIViewController {
    func showError(_ error: Error) {
        if error is CancellationError { return }
        let message = (error as? ClientError)?.errorDescription ?? "Something went wrong. Please try again."
        let alert = UIAlertController(title: "oldFunny", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        if presentedViewController == nil { present(alert, animated: true) }
    }
}

@MainActor
final class StatusView: UIView {
    let label = UILabel()
    let retry = UIButton(type: .system)
    let spinner = UIActivityIndicatorView(style: .large)
    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        backgroundColor = ClassicTheme.background
        label.textColor = .white; label.numberOfLines = 0; label.textAlignment = .center
        retry.setTitle("Try again", for: .normal); retry.tintColor = ClassicTheme.yellow
        let stack = UIStackView(arrangedSubviews: [spinner, label, retry])
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor), stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func loading() { isHidden = false; label.text = ""; retry.isHidden = true; spinner.startAnimating() }
    func message(_ message: String, canRetry: Bool = true) {
        isHidden = false; spinner.stopAnimating(); label.text = message; retry.isHidden = !canRetry
    }
}
