import UIKit

final class PostMediaController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var onComments: (() -> Void)?, onRefresh: (() -> Void)?
    var onLeading: (() -> Void)? { didSet { updateLeading() } }
    let index: Int
    private let app: AppContext
    private let post: Post
    private let source: String
    private let section: String
    private let embedded: Bool
    private let outer = MediaViewportScrollView(), zoom = FittedMediaScrollView(), image = UIImageView()
    private let media = UIView(), titlePanel = UIView(), bodyPanel = UIView()
    private let smile = ClassicCounterButton(), comments = ClassicCounterButton()
    private let unsmile = ClassicTheme.button(.unsmile, label: "Unsmile")
    private let share = ClassicTheme.button(.share, label: "Share post")
    private let status = StatusView()
    private var mediaHeight: NSLayoutConstraint!
    private var video: ClassicVideo?
    private weak var controlsHost: UIView?, footerView: UIView?
    private var barView: ClassicBar?
    private var chromeVisible = true
    private var mediaTask: Task<Void, Never>?
    private var smiled: Bool
    private var unsmiled: Bool, republished: Bool, changingReaction = false, changingRepublish = false
    private var obscured = false
    init(app: AppContext, post: Post, index: Int, source: String, section: String = "Post", embedded: Bool = false) {
        self.app = app; self.post = post; self.index = index; self.source = source; self.embedded = embedded; smiled = post.isSmiled
        self.section = section
        unsmiled = post.isUnsmiled; republished = post.isRepublished
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { mediaTask?.cancel() }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: false) }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        view.accessibilityIdentifier = "post-media"
        let holder = UIView(); holder.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(holder)
        var top = view.topAnchor
        if !embedded {
            view.backgroundColor = ClassicTheme.bar
            let bar = ClassicBar(); bar.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(bar)
            barView = bar
            let header = AuthorHeader(); header.update(post: post, section: section, loader: app.media)
            header.action = { [weak self] in self?.profile() }; bar.setCenter(header)
            bar.onLeading = { [weak self] in
                guard let self else { return }; if let onLeading { onLeading() } else { navigationController?.popViewController(animated: true) }
            }
            updateLeading()
            bar.onTrailing = { [weak self] in
                guard let self else { return }; if let onRefresh { onRefresh() } else { loadMedia() }
            }
            NSLayoutConstraint.activate([bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 52)])
            top = bar.bottomAnchor
        }
        holder.backgroundColor = .black
        NSLayoutConstraint.activate([holder.topAnchor.constraint(equalTo: top), holder.leadingAnchor.constraint(equalTo: view.leadingAnchor), holder.trailingAnchor.constraint(equalTo: view.trailingAnchor), holder.bottomAnchor.constraint(equalTo: embedded ? view.bottomAnchor : view.safeAreaLayoutGuide.bottomAnchor)])
        outer.backgroundColor = .black; outer.showsVerticalScrollIndicator = false
        let container = UIView(); container.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [titlePanel, media, bodyPanel]); stack.axis = .vertical; stack.translatesAutoresizingMaskIntoConstraints = false
        addText(post.title, to: titlePanel, bold: true); addText(post.body, to: bodyPanel, bold: false)
        outer.addSubview(container); container.addSubview(stack)
        outer.translatesAutoresizingMaskIntoConstraints = false; holder.addSubview(outer)
        let preferredHeight = container.heightAnchor.constraint(equalTo: stack.heightAnchor); preferredHeight.priority = .defaultHigh
        mediaHeight = media.heightAnchor.constraint(equalToConstant: 300)
        outer.onLayout = { [weak self] size in self?.layoutMedia(in: size) }
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: outer.contentLayoutGuide.topAnchor), container.bottomAnchor.constraint(equalTo: outer.contentLayoutGuide.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: outer.contentLayoutGuide.leadingAnchor), container.trailingAnchor.constraint(equalTo: outer.contentLayoutGuide.trailingAnchor),
            container.widthAnchor.constraint(equalTo: outer.frameLayoutGuide.widthAnchor), container.heightAnchor.constraint(greaterThanOrEqualTo: outer.frameLayoutGuide.heightAnchor), preferredHeight,
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor), stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor), stack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor), mediaHeight
        ])
        zoom.delegate = self; zoom.minimumZoomScale = 1; zoom.maximumZoomScale = 6
        zoom.backgroundColor = .black; zoom.showsVerticalScrollIndicator = false; zoom.showsHorizontalScrollIndicator = false
        image.contentMode = .scaleAspectFit; zoom.addSubview(image); zoom.fittedContent = image
        image.isAccessibilityElement = true; image.accessibilityLabel = "Post image"; image.accessibilityIdentifier = "post-image"
        media.addSubview(zoom); zoom.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([zoom.topAnchor.constraint(equalTo: media.topAnchor), zoom.bottomAnchor.constraint(equalTo: media.bottomAnchor), zoom.leadingAnchor.constraint(equalTo: media.leadingAnchor), zoom.trailingAnchor.constraint(equalTo: media.trailingAnchor)])
        smile.icon = ClassicTheme.image("smile", fallback: "face.smiling")
        smile.addTarget(self, action: #selector(toggleSmile), for: .touchUpInside); updateSmile()
        unsmile.tintColor = unsmiled ? ClassicTheme.yellow : .white
        unsmile.addTarget(self, action: #selector(toggleUnsmile), for: .touchUpInside)
        unsmile.isHidden = !ViewerInteraction.allowsUnsmile(source: source)
        comments.icon = ClassicTheme.image("comments", fallback: "text.bubble"); comments.count = post.comments
        comments.accessibilityLabel = "\(post.comments) comments"; comments.addTarget(self, action: #selector(openComments), for: .touchUpInside)
        share.addTarget(self, action: #selector(sharePost), for: .touchUpInside)
        let spacer = UIView()
        let footer = UIStackView(arrangedSubviews: [smile, unsmile, spacer, comments, share]); footer.spacing = 6; footer.alignment = .center
        footer.backgroundColor = .black; footer.layoutMargins = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6); footer.isLayoutMarginsRelativeArrangement = true
        footer.translatesAutoresizingMaskIntoConstraints = false; holder.addSubview(footer)
        controlsHost = holder; footerView = footer
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: holder.topAnchor), outer.leadingAnchor.constraint(equalTo: holder.leadingAnchor), outer.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: footer.topAnchor), footer.leadingAnchor.constraint(equalTo: holder.leadingAnchor), footer.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: holder.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 54)
        ])
        media.addSubview(status); status.backgroundColor = .black; status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([status.leadingAnchor.constraint(equalTo: media.leadingAnchor), status.trailingAnchor.constraint(equalTo: media.trailingAnchor), status.topAnchor.constraint(equalTo: media.topAnchor), status.bottomAnchor.constraint(equalTo: media.bottomAnchor)])
        status.retry.addTarget(self, action: #selector(loadMedia), for: .touchUpInside)
        loadMedia()
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
        let tripleTap = UITapGestureRecognizer(target: self, action: #selector(tripleTap)); tripleTap.numberOfTapsRequired = 3; tripleTap.delegate = self; outer.addGestureRecognizer(tripleTap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTap)); doubleTap.numberOfTapsRequired = 2; doubleTap.delegate = self
        doubleTap.require(toFail: tripleTap); outer.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(mediaTap(_:))); singleTap.delegate = self
        singleTap.require(toFail: doubleTap); outer.addGestureRecognizer(singleTap)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(postOptions(_:))); hold.delegate = self; outer.addGestureRecognizer(hold)
    }
    func setCommentCount(_ count: Int) { comments.count = count; comments.accessibilityLabel = "\(count) comments" }
    private func addText(_ text: String, to panel: UIView, bold: Bool) {
        panel.isHidden = text.isEmpty
        guard !text.isEmpty else { return }
        let label = UILabel(); label.text = text; label.textColor = .white; label.font = ClassicTheme.font(bold ? 19 : 17, bold: bold)
        label.numberOfLines = 0; label.textAlignment = .center; label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12), label.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12), label.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8), label.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8)])
    }
    private func layoutMedia(in viewport: CGSize) {
        if viewport.width > 0 && viewport.height > 0 {
            let target = CGSize(width: viewport.width, height: 0)
            let textHeight = [titlePanel, bodyPanel].filter { !$0.isHidden }.reduce(CGFloat(0)) { $0 + $1.systemLayoutSizeFitting(target, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height }
            let height = max(100, min(viewport.width * CGFloat(post.height / post.width), max(100, viewport.height - textHeight)))
            if abs(mediaHeight.constant - height) > 0.5 { mediaHeight.constant = height }
        }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); pause() }
    func canScrollVertically(down: Bool) -> Bool {
        if zoom.zoomScale > zoom.minimumZoomScale + 0.01 { return true }
        let top = -outer.adjustedContentInset.top
        let bottom = max(top, outer.contentSize.height - outer.bounds.height + outer.adjustedContentInset.bottom)
        return down ? outer.contentOffset.y > top + 1 : outer.contentOffset.y < bottom - 1
    }
    @objc private func pause() { video?.suspend(); image.stopAnimating() }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if !obscured { image.startAnimating(); video?.refresh() } }
    func setObscured(_ value: Bool) { obscured = value; if value { pause() } else if isViewLoaded && view.window != nil { image.startAnimating(); video?.refresh() } }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { video?.surface ?? image }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { video?.setZoomed(true) }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { video?.setZoomed(scrollView.isZooming || scrollView.zoomScale > scrollView.minimumZoomScale * 1.01) }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        video?.setZoomed(scale > scrollView.minimumZoomScale * 1.01)
        #if CLASSIC_UI_PREVIEW
        if video != nil { self.view.accessibilityValue = "zoom=\(scale); minimum=\(scrollView.minimumZoomScale); pinching=\(scrollView.isZooming)" }
        #endif
    }
    private func updateLeading() {
        barView?.leading.setImage(onLeading == nil ? ClassicGlyph.back.image : ClassicGlyph.menu.image, for: .normal)
        barView?.leading.accessibilityLabel = onLeading == nil ? "Back" : "Open menu"
    }
    @objc private func mediaTap(_ gesture: UITapGestureRecognizer) {
        if let video, video.tap(at: gesture.location(in: video.surface)) { return }
        chromeVisible.toggle(); barView?.alpha = chromeVisible ? 1 : 0
        footerView?.alpha = chromeVisible ? 1 : 0; video?.setChromeVisible(chromeVisible)
    }
    @objc private func loadMedia() {
        mediaTask?.cancel()
        if post.isVideo {
            guard let url = post.mediaURL, let holder = controlsHost, let footer = footerView else { status.message("Video is unavailable.", canRetry: false); return }
            video?.suspend(); video?.surface.removeFromSuperview(); video?.sound.removeFromSuperview(); video?.scrubber.removeFromSuperview()
            let clip = ClassicVideo(app: app, url: url); video = clip
            clip.isCurrent = { [weak self] in
                guard let self, !obscured, view.window != nil else { return false }
                var owner: UIViewController? = self
                while let controller = owner {
                    if controller.presentedViewController != nil || controller.isBeingDismissed || controller.isMovingFromParent { return false }
                    owner = controller.parent
                }
                if let navigationController, let top = navigationController.topViewController, !isDescendant(of: top) { return false }
                return true
            }
            clip.onFailure = { [weak self] in self?.status.message("Could not load this video.") }
            image.isHidden = true; zoom.addSubview(clip.surface); zoom.fittedContent = clip.surface
            zoom.setZoomScale(zoom.minimumZoomScale, animated: false); zoom.setNeedsLayout()
            holder.addSubview(clip.scrubber); holder.addSubview(clip.sound)
            clip.scrubber.translatesAutoresizingMaskIntoConstraints = false; clip.sound.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                clip.scrubber.leadingAnchor.constraint(equalTo: holder.leadingAnchor), clip.scrubber.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                clip.scrubber.bottomAnchor.constraint(equalTo: footer.topAnchor), clip.scrubber.heightAnchor.constraint(equalToConstant: 24),
                clip.sound.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -8), clip.sound.bottomAnchor.constraint(equalTo: clip.scrubber.topAnchor, constant: -8),
                clip.sound.widthAnchor.constraint(equalToConstant: 44), clip.sound.heightAnchor.constraint(equalToConstant: 44)
            ])
            status.isHidden = true; clip.setChromeVisible(chromeVisible); clip.refresh(); return
        }
        guard let url = post.mediaURL ?? post.posterURL else { status.message("Media is unavailable.", canRetry: false); return }
        status.loading()
        mediaTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await app.media.image(url); try Task.checkCancellation()
                image.image = loaded; status.isHidden = true; if obscured { image.stopAnimating() }
            } catch { if !Task.isCancelled { status.message("Could not load this image.") } }
        }
    }
    private func isDescendant(of controller: UIViewController) -> Bool {
        var owner: UIViewController? = self
        while let item = owner { if item === controller { return true }; owner = item.parent }
        return false
    }
    @objc private func openComments() {
        pause(); onComments?()
    }
    @objc private func profile() {
        guard let id = post.authorID else { return }; pause()
        navigationController?.pushViewController(FeedController(app: app, feed: .featured, timelineID: id, profileName: post.author), animated: true)
    }
    private func updateSmile() {
        let count = max(0, post.smiles + (smiled == post.isSmiled ? 0 : (smiled ? 1 : -1)))
        smile.count = count; smile.tintColor = smiled ? ClassicTheme.yellow : .white
        smile.accessibilityLabel = "\(count) smiles, \(smiled ? "remove smile" : "smile")"
        smile.accessibilityTraits = smiled ? [.button, .selected] : .button
        #if CLASSIC_UI_PREVIEW
        if ProcessInfo.processInfo.arguments.contains("--ui-tests-reactions") { view.accessibilityValue = PreviewFixtures.reactionEvents.joined(separator: ",") }
        #endif
    }
    @objc private func toggleSmile() {
        guard !changingReaction else { return }; changingReaction = true; smile.isEnabled = false; unsmile.isEnabled = false
        Task { [weak self] in
            guard let self else { return }; defer { changingReaction = false; smile.isEnabled = true; unsmile.isEnabled = true }
            let session = await app.api.sessionEpoch()
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            guard view.window != nil else { return }
            do { try await app.api.smile(postID: post.id, enabled: !smiled, source: source, session: session); smiled.toggle(); if smiled { unsmiled = false }; updateSmile(); unsmile.tintColor = unsmiled ? ClassicTheme.yellow : .white }
            catch { showError(error) }
        }
    }
    @objc private func doubleTap() {
        // Android ignores signed-out double taps outside its BR exception.
        Task { [weak self] in
            guard let self, await app.api.account() != nil, view.window != nil, !obscured else { return }
            toggleSmile()
        }
    }
    @objc private func tripleTap() {
        guard ViewerInteraction.allowsUnsmile(source: source) else { return }
        Task { [weak self] in
            guard let self, await app.api.account() != nil, view.window != nil, !obscured else { return }
            toggleUnsmile()
        }
    }
    @objc private func toggleUnsmile() {
        guard ViewerInteraction.allowsUnsmile(source: source) else { return }
        guard !changingReaction else { return }; changingReaction = true; smile.isEnabled = false; unsmile.isEnabled = false
        Task { [weak self] in
            guard let self else { return }; defer { changingReaction = false; smile.isEnabled = true; unsmile.isEnabled = true }
            let session = await app.api.sessionEpoch()
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            guard view.window != nil else { return }
            do { try await app.api.unsmile(postID: post.id, enabled: !unsmiled, source: source, session: session); unsmiled.toggle(); if unsmiled { smiled = false }; updateSmile(); unsmile.tintColor = unsmiled ? ClassicTheme.yellow : .white }
            catch { showError(error) }
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var hit = touch.view
        while let item = hit, item !== outer { if item is UIControl { return false }; hit = item.superview }
        return true
    }
    @objc private func postOptions(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, presentedViewController == nil else { return }; pause()
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: republished ? "Remove republish" : "Republish", style: .default) { [weak self] _ in self?.confirmRepublish() })
        sheet.addAction(UIAlertAction(title: "Copy link", style: .default) { [weak self] _ in UIPasteboard.general.url = self?.postURL })
        sheet.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in self?.sharePost() })
        sheet.addAction(UIAlertAction(title: post.isVideo ? "Save video to Photos" : "Save image to Photos", style: .default) { [weak self] _ in self?.saveMedia() })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = outer; sheet.popoverPresentationController?.sourceRect = CGRect(origin: gesture.location(in: outer), size: .zero)
        present(sheet, animated: true)
    }
    private var postURL: URL { URL(string: "https://ifunny.co/\(post.isVideo ? "video" : "picture")/\(post.id)")! }
    private func confirmRepublish() {
        let alert = UIAlertController(title: republished ? "Remove this republish?" : "Republish to your profile?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: republished ? "Remove" : "Republish", style: .default) { [weak self] _ in self?.changeRepublish() })
        present(alert, animated: true)
    }
    private func changeRepublish() {
        guard !changingRepublish else { return }; changingRepublish = true
        Task { [weak self] in
            guard let self else { return }; defer { changingRepublish = false }
            let session = await app.api.sessionEpoch()
            guard await app.api.account() != nil else { app.signIn(from: self); return }
            guard view.window != nil else { return }
            do { try await app.api.republish(postID: post.id, enabled: !republished, source: source, session: session); republished.toggle() }
            catch { showError(error) }
        }
    }
    private func saveMedia() {
        Task { [weak self] in
            guard let self else { return }
            let result = await PhotoExporter.save(post, loader: app.media)
            guard view.window != nil else { return }
            let alert = UIAlertController(title: "Save to Photos", message: result, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
        }
    }
    @objc private func sharePost() {
        let url = postURL
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = share; present(controller, animated: true)
    }
}

private final class MediaViewportScrollView: UIScrollView {
    var onLayout: ((CGSize) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?(bounds.size) }
}

/// The inner scroll view can resize after the post controller's layout callback
/// (the containing stack resolves its media height separately). Fit here, where
/// the actual viewport is known; never reset a user's zoom/pan during a resize.
private final class FittedMediaScrollView: UIScrollView {
    weak var fittedContent: UIView?
    override func layoutSubviews() {
        super.layoutSubviews()
        guard abs(zoomScale - minimumZoomScale) < 0.001, let fittedContent,
              fittedContent.bounds.size != bounds.size else { return }
        fittedContent.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }
}

final class ClassicCounterButton: UIControl {
    private let symbol = UIImageView(), label = UILabel()
    var icon: UIImage? { didSet { symbol.image = icon } }
    var count = 0 { didSet { label.text = String(count) } }
    var showsCount = true { didSet { label.isHidden = !showsCount } }
    override var isEnabled: Bool { didSet { alpha = isEnabled ? 1 : 0.4 } }
    override init(frame: CGRect = .zero) {
        super.init(frame: frame); tintColor = .white
        symbol.contentMode = .scaleAspectFit; symbol.tintColor = .white
        label.textColor = .white; label.font = ClassicTheme.font(14, bold: true)
        let row = UIStackView(arrangedSubviews: [symbol, label]); row.spacing = 6; row.alignment = .center; row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), row.centerYAnchor.constraint(equalTo: centerYAnchor), symbol.widthAnchor.constraint(equalToConstant: 24), symbol.heightAnchor.constraint(equalToConstant: 24), heightAnchor.constraint(equalToConstant: 44), widthAnchor.constraint(greaterThanOrEqualToConstant: 68)])
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tintColorDidChange() { super.tintColorDidChange(); symbol.tintColor = tintColor; label.textColor = tintColor }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.55 : (isEnabled ? 1 : 0.4) } }
}
