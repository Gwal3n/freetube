import UIKit

/// The app's pull-to-refresh glyph: a ring that fills with the pull, then spins with a gap
/// while refreshing.
@available(iOS 17.0, *)
final class PullRefreshRingView: UIView {
    private static let diameter: CGFloat = 20
    private static let spinKey = "spin"

    private let ring = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        ring.fillColor = nil
        ring.lineWidth = 2.5
        ring.lineCap = .round
        ring.strokeEnd = 0
        layer.addSublayer(ring)
        applyColor()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.applyColor()
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ring.frame = bounds
        ring.path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: Self.diameter / 2,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        ).cgPath
    }

    /// `progress` is the pull toward the trigger distance (0...1).
    func update(progress: CGFloat, isRefreshing: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isRefreshing {
            ring.strokeEnd = 0.75
            alpha = 1
            if ring.animation(forKey: Self.spinKey) == nil {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = CGFloat.pi * 2
                spin.duration = 0.8
                spin.repeatCount = .infinity
                spin.isRemovedOnCompletion = false
                ring.add(spin, forKey: Self.spinKey)
            }
        } else {
            ring.removeAnimation(forKey: Self.spinKey)
            ring.strokeEnd = progress
            alpha = progress > 0.02 ? 0.4 + 0.6 * progress : 0
        }
        CATransaction.commit()
    }

    private func applyColor() {
        ring.strokeColor = UIColor.secondaryLabel.resolvedColor(with: traitCollection).cgColor
    }
}
