import UIKit

/// Only taps on the actual linked glyphs consume the comment row gesture.
/// Ordinary text/blank space and long holds retain the row's native actions.
final class MentionLabel: UILabel, UIGestureRecognizerDelegate {
    var onMention: ((MentionSpan) -> Void)?, canOpen: (() -> Bool)?
    private var mentions = [MentionSpan]()
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(open(_:)))
    override init(frame: CGRect = .zero) {
        super.init(frame: frame); tap.delegate = self; addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(_ text: String, mentions: [MentionSpan]) {
        self.mentions = mentions; isUserInteractionEnabled = !mentions.isEmpty
        let value = NSMutableAttributedString(string: text, attributes: [.font: font ?? ClassicTheme.font(15), .foregroundColor: textColor ?? ClassicTheme.text])
        for mention in mentions {
            value.addAttributes([.foregroundColor: UIColor(red: 41 / 255, green: 121 / 255, blue: 1, alpha: 1), .font: ClassicTheme.font(15, bold: true)], range: mention.range)
        }
        attributedText = value
        accessibilityCustomActions = mentions.map { mention in
            UIAccessibilityCustomAction(name: "Open mentioned profile " + mention.nickname) { [weak self] _ in
                guard let self, canOpen?() != false else { return false }; onMention?(mention); return true
            }
        }
    }
    private func mention(at point: CGPoint) -> MentionSpan? {
        guard bounds.contains(point), let attributedText, !mentions.isEmpty else { return nil }
        let storage = NSTextStorage(attributedString: attributedText), layout = NSLayoutManager()
        let container = NSTextContainer(size: bounds.size); container.lineFragmentPadding = 0
        container.maximumNumberOfLines = numberOfLines; container.lineBreakMode = lineBreakMode
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let local = CGPoint(x: point.x, y: point.y - max(0, (bounds.height - used.height) / 2))
        let glyph = layout.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: nil)
        guard glyph < layout.numberOfGlyphs, layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return nil }
        let index = layout.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        return mentions.first { index >= $0.start && index < $0.end }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        canOpen?() != false && mention(at: touch.location(in: self)) != nil
    }
    @objc private func open(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, canOpen?() != false, let mention = mention(at: gesture.location(in: self)) else { return }; onMention?(mention)
    }
}
