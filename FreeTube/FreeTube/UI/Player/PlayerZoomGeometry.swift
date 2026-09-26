import Foundation
import CoreGraphics

/// Pure fit/fill geometry shared by the fullscreen pinch interaction and its tests.
nonisolated enum PlayerZoomGeometry {
    static func fillScale(video: CGSize, viewport: CGSize) -> CGFloat {
        guard video.width.isFinite, video.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite,
              video.width > 0, video.height > 0,
              viewport.width > 0, viewport.height > 0 else { return 1 }
        let videoRatio = video.width / video.height
        let viewportRatio = viewport.width / viewport.height
        return max(videoRatio / viewportRatio, viewportRatio / videoRatio)
    }

    static func clamped(_ scale: CGFloat, fillScale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(max(1, scale), max(3, fillScale * 2))
    }

    static func settled(_ scale: CGFloat, fillScale: CGFloat) -> CGFloat {
        let scale = clamped(scale, fillScale: fillScale)
        let normalDistance = abs(scale - 1)
        let fillDistance = abs(scale - fillScale)
        if fillScale > 1.01, fillDistance < normalDistance, fillDistance / fillScale < 0.10 {
            return fillScale
        }
        if normalDistance < 0.10 { return 1 }
        return scale
    }

    /// Bound the actual aspect-fit picture, not its letterboxed AVPlayer hosting rectangle.
    static func offset(_ offset: CGSize, scale: CGFloat, video: CGSize, viewport: CGSize) -> CGSize {
        guard video.width.isFinite, video.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite,
              offset.width.isFinite, offset.height.isFinite, scale.isFinite,
              video.width > 0, video.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let fittedScale = min(viewport.width / video.width, viewport.height / video.height)
        let horizontalLimit = max(0, (video.width * fittedScale * scale - viewport.width) / 2)
        let verticalLimit = max(0, (video.height * fittedScale * scale - viewport.height) / 2)
        return CGSize(
            width: min(horizontalLimit, max(-horizontalLimit, offset.width)),
            height: min(verticalLimit, max(-verticalLimit, offset.height))
        )
    }
}
