import UIKit

final class LoginController: UIViewController {
    private let app: AppContext
    private let completed: () -> Void
    private let username = UITextField(), password = UITextField()
    private let submit = UIButton(type: .system)
    private var task: Task<Void, Never>?
    init(app: AppContext, completed: @escaping () -> Void) { self.app = app; self.completed = completed; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Sign in"; view.backgroundColor = ClassicTheme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        username.placeholder = "Email or username"; username.textContentType = .username
        username.keyboardType = .emailAddress; username.autocapitalizationType = .none; username.autocorrectionType = .no
        password.placeholder = "Password"; password.isSecureTextEntry = true; password.textContentType = .password
        for field in [username, password] { field.borderStyle = .roundedRect; field.backgroundColor = .white; field.textColor = .black }
        submit.setTitle("Sign in", for: .normal); submit.tintColor = ClassicTheme.yellow
        submit.addTarget(self, action: #selector(signIn), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [username, password, submit])
        stack.axis = .vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 36),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            username.heightAnchor.constraint(equalToConstant: 46), password.heightAnchor.constraint(equalToConstant: 46)
        ])
    }
    @objc private func cancel() { task?.cancel(); password.text = nil; dismiss(animated: true) }
    @objc private func signIn() {
        guard task == nil else { return }
        let name = username.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = password.text ?? ""
        guard !name.isEmpty, !secret.isEmpty else { showError(ClientError.invalidInput); return }
        password.text = nil; view.endEditing(true); submit.isEnabled = false
        isModalInPresentation = true; navigationController?.isModalInPresentation = true
        navigationItem.leftBarButtonItem?.isEnabled = false
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.task = nil; self.submit.isEnabled = true; self.isModalInPresentation = false
                self.navigationController?.isModalInPresentation = false
                self.navigationItem.leftBarButtonItem?.isEnabled = true
            }
            do {
                do {
                    try await app.api.signIn(username: name, password: secret)
                } catch ClientError.captcha(let url) {
                    // The password stays in this task's memory during one
                    // manual verification, then is released on cancel/failure.
                    guard await verify(url) else { return }
                    try Task.checkCancellation()
                    // Resume once only after the real page's completion signal.
                    // Server acceptance and account lookup still gate storage.
                    try await app.api.signIn(username: name, password: secret)
                }
                dismiss(animated: true, completion: completed)
            } catch ClientError.captcha {
                let alert = UIAlertController(title: "Verification not accepted", message: "iFunny requested verification again. Please try signing in again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
            } catch { showError(error) }
        }
    }
    private func verify(_ url: URL) async -> Bool {
        guard CaptchaPolicy.isChallenge(url) else { return false }
        return await withCheckedContinuation { continuation in
            let controller = CaptchaController(challenge: url) { result in continuation.resume(returning: result) }
            present(UINavigationController(rootViewController: controller), animated: true)
        }
    }
}
