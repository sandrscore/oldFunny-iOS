import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        ClassicTheme.install()
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        do {
            #if CLASSIC_UI_PREVIEW
            let app = try PreviewFixtures.makeApp()
            #else
            let app = try AppContext()
            #endif
            let feed = FeedController(app: app, feed: .featured)
            let navigation = ClassicNavigationController(rootViewController: feed)
            #if CLASSIC_UI_PREVIEW
            if ProcessInfo.processInfo.arguments.contains("--preview-profile") {
                navigation.setViewControllers([feed, ProfileController(app: app, userID: "PreviewUser", nickname: "ClassicFan")], animated: false)
            }
            if ProcessInfo.processInfo.arguments.contains("--preview-profile-search") {
                let browser = ProfileBrowser(app: app, userID: "PreviewUser", nickname: "ClassicFan", search: true)
                var query = ProfileSearchCriteria(); query.setTags(["cats", "fun"]); browser.setCriteria(query)
                navigation.setViewControllers([feed, ProfilePostsController(browser: browser)], animated: false)
            }
            #endif
            window.rootViewController = navigation
        } catch {
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            let message = UILabel()
            message.text = "Could not open oldFunny’s secure storage. Close the app and try again."
            message.numberOfLines = 0; message.textAlignment = .center
            controller.view.addSubview(message); message.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                message.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
                message.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 24),
                message.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -24)
            ])
            window.rootViewController = controller
        }
        self.window = window; window.makeKeyAndVisible()
    }
}

@MainActor
final class AppContext {
    let api: APIClient
    let reads: FeedReadService
    let media = MediaLoader()
    // Android's application-scoped sound flag starts off and is shared by pages.
    var videoSoundOn = false
    private var inactiveSince: Date?
    private var soundObservers = [NSObjectProtocol]()
    var onAccountChange: (() -> Void)?
    init() throws {
        let installation = try KeychainStore.installation()
        api = try APIClient(installation: installation,
            userAgent: Wire.apiUserAgent(systemVersion: UIDevice.current.systemVersion, model: UIDevice.current.model),
            store: KeychainStore())
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        reads = FeedReadService(api: api, directory: support.appendingPathComponent("ReadHistory", isDirectory: true))
        observeSoundLifecycle()
    }
    #if CLASSIC_UI_PREVIEW
    init(previewAPI: APIClient) {
        api = previewAPI
        // Isolated from real read history, including across UI test launches.
        reads = FeedReadService(api: api, directory: FileManager.default.temporaryDirectory.appendingPathComponent("PreviewReads-" + UUID().uuidString, isDirectory: true))
        observeSoundLifecycle()
    }
    #endif
    deinit { soundObservers.forEach { NotificationCenter.default.removeObserver($0) } }
    private func observeSoundLifecycle() {
        soundObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.inactiveSince = Date() } })
        soundObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let inactiveSince = self.inactiveSince, Date().timeIntervalSince(inactiveSince) > 600 { self.videoSoundOn = false }
                self.inactiveSince = nil
            }
        })
    }
    func signIn(from controller: UIViewController, completion: (() -> Void)? = nil) {
        let login = LoginController(app: self) { [weak self] in
            self?.onAccountChange?()
            NotificationCenter.default.post(name: .oldFunnyAccountChanged, object: nil)
            completion?()
        }
        controller.present(UINavigationController(rootViewController: login), animated: true)
    }
}

extension Notification.Name {
    static let oldFunnyAccountChanged = Notification.Name("oldFunnyAccountChanged")
}
