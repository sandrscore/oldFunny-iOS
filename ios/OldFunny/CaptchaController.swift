import UIKit
import WebKit

final class CaptchaController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let challenge: URL
    private var completion: ((Bool) -> Void)?
    private var browser: WKWebView!
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(challenge: URL, completion: @escaping (Bool) -> Void) {
        self.challenge = challenge; self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad(); title = "Verify with iFunny"; view.backgroundColor = ClassicTheme.background
        navigationController?.isModalInPresentation = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reload))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = self; browser.uiDelegate = self
        // Keep WebKit's browser User-Agent so the CAPTCHA provider sees its
        // real rendering engine. No API Authorization header or password enters it.
        browser.translatesAutoresizingMaskIntoConstraints = false
        status.text = "Complete verification here to continue signing in."
        status.textColor = .white; status.numberOfLines = 0; status.font = .systemFont(ofSize: 14)
        spinner.hidesWhenStopped = true; spinner.color = ClassicTheme.yellow
        let header = UIStackView(arrangedSubviews: [spinner, status]); header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header); view.addSubview(browser)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            browser.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            browser.leadingAnchor.constraint(equalTo: view.leadingAnchor), browser.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browser.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(cancel), name: UIApplication.didEnterBackgroundNotification, object: nil)
        reload()
    }
    @objc private func reload() {
        guard completion != nil, CaptchaPolicy.isChallenge(challenge) else { finish(false); return }
        status.text = "Complete verification here to continue signing in."; spinner.startAnimating()
        browser.load(URLRequest(url: challenge))
    }
    @objc private func cancel() { finish(false) }
    private func finish(_ verified: Bool) {
        guard let completed = completion else { return }; completion = nil
        browser?.stopLoading(); browser?.navigationDelegate = nil; browser?.uiDelegate = nil
        dismiss(animated: UIApplication.shared.applicationState == .active) { completed(verified) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard completion != nil, let destination = navigationAction.request.url else { decisionHandler(.cancel); return }
        let source = navigationAction.sourceFrame.request.url ?? webView.url
        let mainTarget = navigationAction.targetFrame?.isMainFrame ?? true
        switch CaptchaPolicy.decide(destination: destination, source: source,
                                    sourceIsMainFrame: navigationAction.sourceFrame.isMainFrame, targetIsMainFrame: mainTarget) {
        case .resolved:
            decisionHandler(.cancel); finish(true)
        case .block:
            decisionHandler(.cancel)
            if mainTarget { spinner.stopAnimating(); status.text = "That link cannot finish verification here. Complete the challenge or cancel and try signing in again." }
        case .allowPage:
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel); webView.load(navigationAction.request)
            } else { decisionHandler(.allow) }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { spinner.stopAnimating() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        guard completion != nil, (error as? URLError)?.code != .cancelled else { return }
        spinner.stopAnimating()
        status.text = ClientError.networkFailure(error).errorDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        spinner.stopAnimating(); status.text = "Verification stopped loading. Tap refresh to try again."
    }
}
