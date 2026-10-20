import UIKit

enum ClassicTheme {
    static let yellow = UIColor(red: 1, green: 0.82, blue: 0.02, alpha: 1)
    static let background = UIColor(white: 0.12, alpha: 1)
    static func install() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.17, alpha: 1)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.boldSystemFont(ofSize: 19)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = yellow
        UIBarButtonItem.appearance().tintColor = yellow
    }
    static func image(_ name: String, fallback: String) -> UIImage? {
        UIImage(named: name)?.withRenderingMode(.alwaysTemplate) ?? UIImage(systemName: fallback)
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
