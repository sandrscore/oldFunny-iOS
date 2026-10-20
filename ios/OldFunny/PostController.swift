import UIKit
import AVKit

final class PostController: UIViewController, UIScrollViewDelegate {
    let index: Int
    private let app: AppContext
    private let post: Post
    private let source: String
    private let scroll = UIScrollView(), image = UIImageView()
    private let author = UIButton(type: .system), smile = UIButton(type: .system)
    private let comments = UIButton(type: .system), share = UIButton(type: .system)
    private let status = StatusView()
    private var video: AVPlayerViewController?
    private var mediaTask: Task<Void, Never>?
    private var smiled: Bool
    init(app: AppContext, post: Post, index: Int, source: String) {
        self.app = app; self.post = post; self.index = index; self.source = source; smiled = post.isSmiled
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { mediaTask?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = ClassicTheme.background
        author.setTitle(post.author, for: .normal); author.tintColor = ClassicTheme.yellow
        author.contentHorizontalAlignment = .left; author.addTarget(self, action: #selector(profile), for: .touchUpInside)
        let title = UILabel(); title.text = post.title; title.textColor = .white; title.numberOfLines = 0
        title.font = .boldSystemFont(ofSize: 19); title.textAlignment = .center; title.isHidden = post.title.isEmpty; title.numberOfLines = 4
        let body = UILabel(); body.text = post.body; body.textColor = .white; body.numberOfLines = 0
        body.font = .systemFont(ofSize: 17); body.textAlignment = .center; body.isHidden = post.body.isEmpty; body.numberOfLines = 8
        scroll.delegate = self; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4
        scroll.backgroundColor = .black; image.contentMode = .scaleAspectFit
        scroll.addSubview(image)
        let media = UIView(); media.backgroundColor = .black
        media.addSubview(scroll); scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: media.topAnchor), scroll.bottomAnchor.constraint(equalTo: media.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: media.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: media.trailingAnchor)
        ])
        smile.setImage(ClassicTheme.image("smile", fallback: "face.smiling"), for: .normal)
        smile.addTarget(self, action: #selector(toggleSmile), for: .touchUpInside); updateSmile()
        comments.setImage(ClassicTheme.image("comments", fallback: "text.bubble"), for: .normal)
        comments.setTitle(" \(post.comments)", for: .normal); comments.addTarget(self, action: #selector(openComments), for: .touchUpInside)
        share.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        share.addTarget(self, action: #selector(sharePost), for: .touchUpInside)
        let controls = UIStackView(arrangedSubviews: [smile, comments, share])
        controls.axis = .horizontal; controls.distribution = .fillEqually; controls.heightAnchor.constraint(equalToConstant: 48).isActive = true
        for control in [smile, comments, share] { control.tintColor = ClassicTheme.yellow }
        let stack = UIStackView(arrangedSubviews: [author, title, media, body, controls])
        stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            author.heightAnchor.constraint(equalToConstant: 30), media.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])
        media.addSubview(status); status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: media.leadingAnchor), status.trailingAnchor.constraint(equalTo: media.trailingAnchor),
            status.topAnchor.constraint(equalTo: media.topAnchor), status.bottomAnchor.constraint(equalTo: media.bottomAnchor)
        ])
        status.retry.addTarget(self, action: #selector(loadMedia), for: .touchUpInside)
        if post.isVideo, let url = post.mediaURL {
            let player = AVPlayerViewController(); player.player = AVPlayer(url: url)
            player.player?.isMuted = post.type == "gif"
            addChild(player); media.insertSubview(player.view, belowSubview: status); player.didMove(toParent: self)
            player.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                player.view.leadingAnchor.constraint(equalTo: media.leadingAnchor), player.view.trailingAnchor.constraint(equalTo: media.trailingAnchor),
                player.view.topAnchor.constraint(equalTo: media.topAnchor), player.view.bottomAnchor.constraint(equalTo: media.bottomAnchor)
            ])
            video = player; scroll.isHidden = true; status.isHidden = true
        } else { loadMedia() }
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); if scroll.zoomScale == 1 { image.frame = scroll.bounds; scroll.contentSize = scroll.bounds.size } }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); pause() }
    @objc private func pause() { video?.player?.pause(); image.stopAnimating() }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); image.startAnimating() }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    @objc private func loadMedia() {
        guard video == nil else { return }
        mediaTask?.cancel()
        guard let url = post.mediaURL ?? post.posterURL else { status.message("Media is unavailable.", canRetry: false); return }
        status.loading()
        mediaTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await app.media.image(url)
                try Task.checkCancellation(); image.image = loaded; status.isHidden = true
            } catch {
                if Task.isCancelled { return }
                status.message("Could not load this image.")
            }
        }
    }
    @objc private func openComments() {
        pause(); navigationController?.pushViewController(CommentsController(app: app, postID: post.id), animated: true)
    }
    @objc private func profile() {
        guard let id = post.authorID else { return }
        pause(); navigationController?.pushViewController(FeedController(app: app, feed: .featured, timelineID: id, profileName: post.author), animated: true)
    }
    private func updateSmile() { smile.setTitle(" \(max(0, post.smiles + (smiled == post.isSmiled ? 0 : (smiled ? 1 : -1))))", for: .normal); smile.tintColor = smiled ? .systemRed : ClassicTheme.yellow }
    @objc private func toggleSmile() {
        smile.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer { smile.isEnabled = true }
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            do { try await app.api.smile(postID: post.id, enabled: !smiled, source: source); smiled.toggle(); updateSmile() }
            catch { showError(error) }
        }
    }
    @objc private func sharePost() {
        let url = URL(string: "https://ifunny.co/\(post.isVideo ? "video" : "picture")/\(post.id)")!
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = share
        present(controller, animated: true)
    }
}
