import UIKit

final class AccountController: ClassicScreenController {
    private let app: AppContext
    private var account: Credential?
    private let name = UILabel(), action = UIButton(type: .custom)
    init(app: AppContext, account: Credential?) { self.app = app; self.account = account; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); classicBar.setTitle("Account"); classicBar.trailing.isEnabled = false; classicBar.trailing.alpha = 0
        classicBar.trailing.accessibilityElementsHidden = true
        name.font = ClassicTheme.font(23); name.textColor = .white; name.numberOfLines = 0
        action.titleLabel?.font = ClassicTheme.font(17); action.setTitleColor(ClassicTheme.yellow, for: .normal)
        action.contentHorizontalAlignment = .leading; action.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [name, action]); stack.axis = .vertical; stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28), stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20), action.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)])
        render()
    }
    private func render() { name.text = account?.nickname ?? "Welcome to oldFunny"; action.setTitle(account == nil ? "Sign in" : "Remove account from oldFunny", for: .normal) }
    @objc private func tapped() {
        guard account != nil else {
            app.signIn(from: self) { [weak self] in
                Task { [weak self] in guard let self else { return }; account = await app.api.account(); render() }
            }; return
        }
        let alert = UIAlertController(title: "Remove account?", message: "This removes the saved sign-in from oldFunny on this phone.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await self.app.api.forgetSession(); self.account = nil; self.render()
                    self.app.onAccountChange?(); NotificationCenter.default.post(name: .oldFunnyAccountChanged, object: nil)
                } catch { self.showError(error) }
            }
        })
        present(alert, animated: true)
    }
}
