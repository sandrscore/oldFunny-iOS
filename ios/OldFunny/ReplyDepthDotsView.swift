import UIKit

/// Android answer_item's DotsDrawable: 2dp radius, 6dp between circles.
/// The cell supplies the depth-1 count after the phone/tablet resource cap.
final class ReplyDepthDotsView: UIView {
    var count = 0 {
        didSet {
            guard count != oldValue else { return }
            isHidden = count == 0; invalidateIntrinsicContentSize(); setNeedsDisplay()
        }
    }
    override init(frame: CGRect = .zero) {
        super.init(frame: frame); backgroundColor = .clear; isOpaque = false
        isUserInteractionEnabled = false; isAccessibilityElement = false; isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        CGSize(width: count > 0 ? CGFloat(count * 4 + (count - 1) * 6) : 0, height: 4)
    }
    override func draw(_ rect: CGRect) {
        UIColor(red: 108 / 255, green: 108 / 255, blue: 115 / 255, alpha: 1).setFill()
        for index in 0..<max(0, count) {
            UIBezierPath(ovalIn: CGRect(x: CGFloat(index * 10), y: bounds.midY - 2, width: 4, height: 4)).fill()
        }
    }
}
