import Observation
import SwiftUI
import UIKit

/// Combines native pinch and two-finger pan samples into one SwiftUI media transform. A single
/// baseline is retained until both recognizers finish, so lifting one finger never jumps it.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerZoomModel {
    private(set) var scale: CGFloat = 1
    private(set) var offset: CGSize = .zero
    private(set) var isInteracting = false
    private(set) var feedbackTrigger = 0
    private var videoSize: CGSize = .zero
    private var viewportSize: CGSize = .zero
    private var reduceMotion = false
    private var pinchActive = false
    private var panActive = false
    private var baseScale: CGFloat = 1
    private var baseOffset: CGSize = .zero
    private var magnitude: CGFloat = 1
    private var translation: CGSize = .zero
    private var pinchPanOrigin: CGSize = .zero
    private var focalPoint: CGPoint = .zero
    private var lastDetent = 1

    private var fillScale: CGFloat {
        PlayerZoomGeometry.fillScale(video: videoSize, viewport: viewportSize)
    }

    func configure(video: CGSize, viewport: CGSize, reduceMotion: Bool) {
        videoSize = video
        viewportSize = viewport
        self.reduceMotion = reduceMotion
    }

    func pinch(_ magnitude: CGFloat, focalPoint: CGPoint, state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            beginIfNeeded()
            pinchActive = true
            pinchPanOrigin = translation
            // Coordinator reports relative to the currently panned media centre. Convert that
            // to the stationary viewport centre before preserving the point under the fingers.
            self.focalPoint = CGPoint(x: focalPoint.x + offset.width, y: focalPoint.y + offset.height)
            self.magnitude = magnitude
            update()
        case .changed:
            guard pinchActive else { return }
            self.magnitude = magnitude
            update()
        case .ended:
            guard pinchActive else { return }
            self.magnitude = magnitude
            update()
            pinchActive = false
            finishIfNeeded()
        case .cancelled, .failed:
            pinchActive = false
            finishIfNeeded()
        default: break
        }
    }

    func pan(_ translation: CGSize, state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            beginIfNeeded()
            panActive = true
            self.translation = translation
            update()
        case .changed:
            guard panActive else { return }
            self.translation = translation
            update()
        case .ended:
            guard panActive else { return }
            self.translation = translation
            update()
            panActive = false
            finishIfNeeded()
        case .cancelled, .failed:
            panActive = false
            finishIfNeeded()
        default: break
        }
    }

    private func beginIfNeeded() {
        guard !isInteracting else { return }
        baseScale = scale
        baseOffset = offset
        magnitude = 1
        translation = .zero
        pinchPanOrigin = .zero
        focalPoint = .zero
        isInteracting = true
    }

    private func update() {
        let newScale = PlayerZoomGeometry.clamped(baseScale * magnitude, fillScale: fillScale)
        let ratio = newScale / max(1, baseScale)
        let newOffset = CGSize(
            width: (baseOffset.width + pinchPanOrigin.width) * ratio
                + focalPoint.x * (1 - ratio) + translation.width - pinchPanOrigin.width,
            height: (baseOffset.height + pinchPanOrigin.height) * ratio
                + focalPoint.y * (1 - ratio) + translation.height - pinchPanOrigin.height
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scale = newScale
            offset = PlayerZoomGeometry.offset(newOffset, scale: scale, video: videoSize, viewport: viewportSize)
        }
        let detent = abs(scale - 1) < 0.035 ? 1
            : fillScale > 1.01 && abs(scale - fillScale) / fillScale < 0.025 ? 2 : 0
        if detent != 0, detent != lastDetent {
            feedbackTrigger += 1
            lastDetent = detent
        }
    }

    private func finishIfNeeded() {
        guard !pinchActive, !panActive, isInteracting else { return }
        isInteracting = false
        let target = PlayerZoomGeometry.settled(scale, fillScale: fillScale)
        let detent = target == 1 ? 1 : target == fillScale ? 2 : 0
        if detent != 0, detent != lastDetent {
            feedbackTrigger += 1
            lastDetent = detent
        }
        // Normal and screen-fill are centred detents. Arbitrary zoom retains its focal point.
        let targetOffset = target == 1 || target == fillScale ? CGSize.zero
            : PlayerZoomGeometry.offset(offset, scale: target, video: videoSize, viewport: viewportSize)
        withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0)) {
            scale = target
            offset = targetOffset
        }
    }

    func reset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pinchActive = false
            panActive = false
            isInteracting = false
            scale = 1
            offset = .zero
            lastDetent = 1
        }
    }
}
