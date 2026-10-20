import UIKit
import AVFoundation

/// A single retained player. The transformed video, including its pause mark,
/// belongs to the same zoom surface as a picture; controls stay above the footer.
@MainActor
final class ClassicVideo: NSObject {
    let surface = VideoSurface(), scrubber = VideoScrubber()
    let sound = UIButton(type: .system)
    var isCurrent: (() -> Bool)?, onFailure: (() -> Void)?
    private let app: AppContext, player: AVPlayer, item: AVPlayerItem
    private var seeks = VideoSeekState(), manuallyPaused = false, active = false
    private var hasAudio = false, chromeVisible = true, zoomed = false
    private var timer: Timer?, timeObserver: Any?, endObserver: NSObjectProtocol?
    private var lifecycleObservers = [NSObjectProtocol]()
    private var audioTask: Task<Void, Never>?
    private var duration: Int64 = 0, position: Int64 = 0
    private var reportedFailure = false
    #if CLASSIC_UI_PREVIEW
    private let decodedFrames = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
    private var decodedTime: Int64 = -1
    #endif

    init(app: AppContext, url: URL) {
        self.app = app
        var local = url
        #if CLASSIC_UI_PREVIEW
        // Missing fixtures must fail closed, never request preview.invalid.
        if url.host == "preview.invalid" {
            local = Bundle.main.url(forResource: "fixture-video", withExtension: "mp4")
                ?? URL(fileURLWithPath: "/missing-offline-video.mp4")
        }
        #endif
        item = AVPlayerItem(url: local); player = AVPlayer(playerItem: item)
        super.init()
        #if CLASSIC_UI_PREVIEW
        item.add(decodedFrames)
        #endif
        player.isMuted = !app.videoSoundOn; player.actionAtItemEnd = .none
        surface.videoLayer.player = player; surface.videoLayer.videoGravity = .resizeAspect
        surface.accessibilityIdentifier = "post-video"
        surface.isAccessibilityElement = true; surface.accessibilityTraits = .button
        surface.accessibilityLabel = "Video playback"; surface.onActivate = { [weak self] in self?.tapInside() ?? false }
        sound.setImage(UIImage(systemName: "speaker.slash.fill"), for: .normal); sound.tintColor = .white
        sound.accessibilityIdentifier = "video-sound"
        sound.addTarget(self, action: #selector(toggleSound), for: .touchUpInside)
        scrubber.begin = { [weak self] fraction in self?.beginSeek(fraction) ?? false }
        scrubber.move = { [weak self] fraction in self?.requestSeek(fraction) }
        scrubber.release = { [weak self] in self?.releaseSeek() }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] _ in
            self?.refresh()
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            execute(seeks.restart(current: current, ready: ready, manuallyPaused: manuallyPaused))
        }
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            lifecycleObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        }
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        audioTask = Task { [weak self, item] in
            let tracks = try? await item.asset.loadTracks(withMediaType: .audio)
            guard !Task.isCancelled, let self else { return }
            hasAudio = tracks?.isEmpty == false; refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    deinit {
        timer?.invalidate(); audioTask?.cancel(); player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    private var ready: Bool { item.status == .readyToPlay }
    private var current: Bool {
        surface.window != nil && !surface.isHidden && UIApplication.shared.applicationState == .active && isCurrent?() == true
    }
    private var playing: Bool { player.rate > 0 }
    private func millis(_ time: CMTime) -> Int64 {
        let seconds = time.seconds
        guard seconds.isFinite, seconds > 0, seconds < Double(Int64.max) / 1000 else { return 0 }
        return Int64(seconds * 1000)
    }
    func suspend() {
        active = false; seeks.suspend(); scrubber.cancelTracking(with: nil)
        player.pause(); refreshControls()
    }
    func refresh() {
        let visible = current
        if !visible { if active || playing || seeks.dragging { suspend() }; return }
        if !active {
            active = true; seeks.returned(manuallyPaused: manuallyPaused)
            player.isMuted = !app.videoSoundOn
            if ready && !manuallyPaused && !seeks.blocksStart { player.play() }
        } else if ready && !manuallyPaused && !seeks.blocksStart && player.timeControlStatus == .paused {
            player.play()
        }
        duration = millis(item.duration)
        if !seeks.dragging && seeks.inFlight == nil { position = millis(player.currentTime()) }
        if item.status == .failed && !reportedFailure { reportedFailure = true; onFailure?() }
        refreshControls()
    }
    func setChromeVisible(_ value: Bool) { chromeVisible = value; refreshControls() }
    func setZoomed(_ value: Bool) { zoomed = value; refreshControls() }
    /// Caller converts the touch through the actual zoom/pan transform.
    func tap(at point: CGPoint) -> Bool {
        guard surface.videoLayer.videoRect.contains(point) else { return false }
        return tapInside()
    }
    private func tapInside() -> Bool {
        guard current, ready else { return false }
        if seeks.blocksStart { return true }
        if playing { manuallyPaused = true; player.pause() }
        else { manuallyPaused = false; player.play() }
        refreshControls(); return true
    }
    private func beginSeek(_ fraction: Double) -> Bool {
        let commands = seeks.begin(fraction: fraction, duration: duration, playing: playing,
            manuallyPaused: manuallyPaused, current: current, ready: ready)
        guard seeks.dragging else { return false }
        position = seeks.position; execute(commands); refreshControls(); return true
    }
    private func requestSeek(_ fraction: Double) {
        execute(seeks.request(fraction: fraction, duration: duration, current: current, ready: ready))
        position = seeks.position; refreshControls()
    }
    private func releaseSeek() {
        execute(seeks.release(current: current, ready: ready, manuallyPaused: manuallyPaused)); refreshControls()
    }
    private func execute(_ commands: [VideoSeekState.Command]) {
        for command in commands {
            switch command {
            case .pause: player.pause()
            case .play: if current && ready && !manuallyPaused && !seeks.blocksStart { player.play() }
            case .seek(let request):
                player.seek(to: CMTime(value: request.milliseconds, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        execute(seeks.completed(request.id, finished: finished, current: current, ready: ready, manuallyPaused: manuallyPaused))
                        refreshControls()
                    }
                }
            }
        }
    }
    @objc private func toggleSound() {
        guard current, hasAudio else { return }
        app.videoSoundOn.toggle(); player.isMuted = !app.videoSoundOn
        if app.videoSoundOn && playing { execute(seeks.restart(current: current, ready: ready, manuallyPaused: manuallyPaused)) }
        refreshControls()
    }
    private func refreshControls() {
        let visible = active && current && ready
        scrubber.isHidden = !(visible && chromeVisible && VideoSeekState.hasScrubber(duration: duration))
        scrubber.position = position; scrubber.duration = duration; scrubber.setNeedsDisplay()
        scrubber.accessibilityValue = VideoSeekState.timestamp(position) + " / " + VideoSeekState.timestamp(duration)
        surface.paused = visible && manuallyPaused && !seeks.dragging
        surface.accessibilityValue = !visible ? "Inactive" : manuallyPaused ? "Paused" : "Playing"
        sound.isHidden = !(visible && hasAudio && !zoomed)
        sound.setImage(UIImage(systemName: app.videoSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill"), for: .normal)
        sound.accessibilityLabel = app.videoSoundOn ? "Mute video" : "Unmute video"
        #if CLASSIC_UI_PREVIEW
        var frameTime = CMTime.invalid
        if decodedFrames.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: &frameTime) != nil, frameTime.isValid { decodedTime = millis(frameTime) }
        scrubber.accessibilityValue = "\(position)/\(duration); \(seeks.inFlight == nil ? "idle" : "seeking"); \(manuallyPaused ? "paused" : "playing"); frame=\(decodedTime); visible=\(surface.videoLayer.isReadyForDisplay)"
        #endif
    }
}

final class VideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private let mark = PausedVideoMark()
    var paused = false { didSet { mark.isHidden = !paused; setNeedsLayout() } }
    var onActivate: (() -> Bool)?
    override init(frame: CGRect = .zero) {
        super.init(frame: frame); addSubview(mark); mark.isUserInteractionEnabled = false; mark.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let rect = videoLayer.videoRect
        mark.bounds = CGRect(x: 0, y: 0, width: 60, height: 60); mark.center = CGPoint(x: rect.midX, y: rect.midY)
    }
    override func accessibilityActivate() -> Bool { onActivate?() ?? false }
}

private final class PausedVideoMark: UIView {
    override init(frame: CGRect = .zero) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        UIColor.black.withAlphaComponent(0.4).setFill(); UIBezierPath(ovalIn: bounds).fill()
        let path = UIBezierPath(); path.move(to: CGPoint(x: 22, y: 16)); path.addLine(to: CGPoint(x: 46, y: 30)); path.addLine(to: CGPoint(x: 22, y: 44)); path.close()
        UIColor.white.withAlphaComponent(0.9).setFill(); path.fill()
    }
}

/// A thumb-free, full-width 24pt touch region, matching the Android scrubber.
final class VideoScrubber: UIControl {
    var begin: ((Double) -> Bool)?, move: ((Double) -> Void)?, release: (() -> Void)?
    var position: Int64 = 0, duration: Int64 = 0
    override init(frame: CGRect = .zero) {
        super.init(frame: frame); backgroundColor = .clear; isOpaque = false
        accessibilityIdentifier = "video-scrubber"; accessibilityLabel = "Video playback position"
        isAccessibilityElement = true; accessibilityTraits = .adjustable
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func fraction(_ touch: UITouch) -> Double { bounds.width > 0 ? Double(touch.location(in: self).x / bounds.width) : 0 }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { begin?(fraction(touch)) ?? false }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { move?(fraction(touch)); return true }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { if let touch { move?(fraction(touch)) }; release?(); setNeedsDisplay() }
    override func cancelTracking(with event: UIEvent?) { super.cancelTracking(with: event); release?(); setNeedsDisplay() }
    override func accessibilityIncrement() { adjust(0.05) }
    override func accessibilityDecrement() { adjust(-0.05) }
    private func adjust(_ step: Double) {
        guard duration > 0 else { return }; let value = Double(position) / Double(duration) + step
        if begin?(value) == true { release?() }
    }
    override func draw(_ rect: CGRect) {
        let height: CGFloat = isTracking ? 3 : 2
        UIColor.white.withAlphaComponent(53.0 / 255).setFill(); UIRectFill(CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height))
        UIColor.white.withAlphaComponent(207.0 / 255).setFill()
        let progress = duration > 0 ? CGFloat(min(1, max(0, Double(position) / Double(duration)))) : 0
        UIRectFill(CGRect(x: 0, y: bounds.height - height, width: bounds.width * progress, height: height))
        if isTracking {
            let text = VideoSeekState.timestamp(position) + " / " + VideoSeekState.timestamp(duration)
            let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.8); shadow.shadowOffset = CGSize(width: 0, height: 1); shadow.shadowBlurRadius = 1
            let attributes: [NSAttributedString.Key: Any] = [.font: ClassicTheme.font(12), .foregroundColor: UIColor.white, .shadow: shadow]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - height - 4 - size.height), withAttributes: attributes)
        }
    }
}
