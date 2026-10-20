import UIKit

/// A retained Android-style post scene. Panel changes never push/pop navigation
/// and preserve the post's zoom, comments position and unsent draft.
final class PostController: UIViewController, UIGestureRecognizerDelegate {
    let index: Int
    let post: Post
    private let app: AppContext
    private let source: String
    private let media: PostMediaController
    private var comments: CommentsController?, information: PostInfoController?
    private(set) var panel: ViewerPanel = .media
    private var current: UIViewController
    private var transitioning = false, obscured = false
    private var firstDirection: VerticalSwipe?
    private weak var initialHit: UIView?
    private lazy var vertical = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
    var onMenu: (() -> Void)? { didSet { media.onLeading = onMenu } }
    var onRefresh: (() -> Void)? { didSet { media.onRefresh = onRefresh } }
    var onPanelChange: ((ViewerPanel) -> Void)?

    init(app: AppContext, post: Post, index: Int, source: String, section: String = "Post") {
        self.app = app; self.post = post; self.index = index; self.source = source
        media = PostMediaController(app: app, post: post, index: index, source: source, section: section)
        current = media
        super.init(nibName: nil, bundle: nil)
        media.onComments = { [weak self] in self?.showPanel(.comments) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); current.beginAppearanceTransition(true, animated: animated) }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); current.endAppearanceTransition(); setObscured(false) }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); setObscured(true); current.beginAppearanceTransition(false, animated: animated) }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); current.endAppearanceTransition() }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black; view.clipsToBounds = true
        view.accessibilityIdentifier = "post-scene"
        attach(media); vertical.delegate = self; vertical.maximumNumberOfTouches = 1
        vertical.cancelsTouchesInView = false; view.addGestureRecognizer(vertical)
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Open comments", target: self, selector: #selector(accessibleComments)),
            UIAccessibilityCustomAction(name: "Post information", target: self, selector: #selector(accessibleInformation)),
            UIAccessibilityCustomAction(name: "Return to post", target: self, selector: #selector(accessibleMedia))
        ]
    }
    @objc private func accessibleComments() -> Bool { showPanel(.comments); return true }
    @objc private func accessibleInformation() -> Bool { showPanel(.information); return true }
    @objc private func accessibleMedia() -> Bool { showPanel(.media); return true }
    private func attach(_ child: UIViewController) {
        addChild(child); view.addSubview(child.view); child.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), child.view.topAnchor.constraint(equalTo: view.topAnchor), child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        child.didMove(toParent: self)
    }
    func showPanel(_ target: ViewerPanel, animated: Bool = true) {
        loadViewIfNeeded()
        guard target != panel, !transitioning else { return }
        view.endEditing(true)
        // Nonadjacent accessibility/button routes go through media first.
        if panel != .media && target != .media {
            showPanel(.media, animated: false); showPanel(target, animated: animated); return
        }
        let incoming: UIViewController
        switch target {
        case .media: incoming = media
        case .comments:
            if comments == nil {
                let child = CommentsController(app: app, postID: post.id, count: post.comments, postAuthorID: post.authorID)
                child.onClose = { [weak self] in self?.showPanel(.media) }; child.isEmbeddedPanel = true
                child.onCountChange = { [weak self] count in self?.media.setCommentCount(count) }
                comments = child
            }
            incoming = comments!
        case .information:
            if information == nil {
                let child = PostInfoController(app: app, post: post)
                child.onClose = { [weak self] in self?.showPanel(.media) }; information = child
            }
            incoming = information!
        }
        let outgoing = current, previous = panel
        transitioning = true; panel = target; current = incoming
        if incoming.parent == nil { attach(incoming) }
        incoming.view.isHidden = false; view.bringSubviewToFront(incoming.view); view.layoutIfNeeded()
        let forward = (previous == .media && target == .comments) || (previous == .information && target == .media)
        let distance = view.bounds.height * (forward ? 1 : -1)
        incoming.view.transform = CGAffineTransform(translationX: 0, y: distance)
        media.setObscured(target != .media || obscured)
        outgoing.beginAppearanceTransition(false, animated: animated); incoming.beginAppearanceTransition(true, animated: animated)
        let finish: (Bool) -> Void = { [weak self] _ in
            outgoing.view.isHidden = true; outgoing.view.transform = .identity
            incoming.view.transform = .identity
            outgoing.endAppearanceTransition(); incoming.endAppearanceTransition()
            self?.transitioning = false; self?.onPanelChange?(target)
            UIAccessibility.post(notification: .screenChanged, argument: incoming.view)
        }
        let changes = { outgoing.view.transform = CGAffineTransform(translationX: 0, y: -distance); incoming.view.transform = .identity }
        if animated && !UIAccessibility.isReduceMotionEnabled { UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut], animations: changes, completion: finish) }
        else { changes(); finish(true) }
    }
    func setObscured(_ value: Bool) { obscured = value; media.setObscured(value || panel != .media) }
    func returnToMedia() -> Bool {
        guard panel != .media else { return false }; view.endEditing(true); showPanel(.media); return true
    }
    private func editing(in view: UIView) -> Bool { view.isFirstResponder || view.subviews.contains { editing(in: $0) } }
    private func childCanScroll(_ gesture: UIPanGestureRecognizer, down: Bool) -> Bool {
        if panel == .media { return media.canScrollVertically(down: down) }
        var hit = initialHit
        while let item = hit, item !== view {
            if let scroll = item as? UIScrollView, scroll.isScrollEnabled {
                let top = -scroll.adjustedContentInset.top
                let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                if scroll.zoomScale > scroll.minimumZoomScale + 0.01 || (down ? scroll.contentOffset.y > top + 1 : scroll.contentOffset.y < bottom - 1) { return true }
            }
            hit = item.superview
        }
        return false
    }
    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gesture === vertical else { return true }
        initialHit = touch.view
        return true
    }
    private func traceGesture(_ event: String) {
        #if CLASSIC_UI_PREVIEW
        let delta = vertical.translation(in: view), speed = vertical.velocity(in: view)
        view.accessibilityValue = "\(event); panel=\(panel.rawValue); dy=\(Int(delta.y)); vx=\(Int(speed.x)); vy=\(Int(speed.y)); first=\(String(describing: firstDirection)); editing=\(editing(in: view))"
        #endif
    }
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture === vertical, !transitioning, !obscured, presentedViewController == nil, !editing(in: view) else { traceGesture("blocked scene/editing"); return false }
        let speed = vertical.velocity(in: view), down = speed.y > 0
        let direction: VerticalSwipe = down ? .down : .up
        guard ViewerInteraction.destination(from: panel, swipe: direction) != nil else { traceGesture("blocked direction"); return false }
        // Use the original touch target. At high speed the first delivered pan
        // sample can already be over a different row/control below the header.
        var hit = initialHit
        while let item = hit, item !== view { if item is UIControl || item is UITextView { traceGesture("blocked starting control"); return false }; hit = item.superview }
        guard abs(speed.y) > abs(speed.x), !childCanScroll(vertical, down: down) else { traceGesture("blocked axis/child scroll"); return false }
        firstDirection = direction; traceGesture("admitted"); return true
    }
    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gesture === vertical && other is UIPanGestureRecognizer
    }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .cancelled || gesture.state == .failed { firstDirection = nil; initialHit = nil; traceGesture("cancelled"); return }
        guard gesture.state == .ended else { return }
        defer { firstDirection = nil; initialHit = nil }
        let delta = gesture.translation(in: view), speed = gesture.velocity(in: view)
        let direction: VerticalSwipe = delta.y > 0 ? .down : .up
        guard firstDirection == direction,
              ViewerInteraction.accepts(dx: Double(delta.x), dy: Double(delta.y), vx: Double(speed.x), vy: Double(speed.y), displayScale: Double(view.window?.screen.scale ?? UIScreen.main.scale), childCanScroll: false, editing: editing(in: view)),
              let target = ViewerInteraction.destination(from: panel, swipe: direction) else { traceGesture("rejected fling"); return }
        traceGesture("accepted fling")
        view.endEditing(true); showPanel(target)
    }
}
