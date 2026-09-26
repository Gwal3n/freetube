import Foundation

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
        return min(max(1, scale), max(3, fillScale))
    }

    static func settled(_ scale: CGFloat, fillScale: CGFloat) -> CGFloat {
        let scale = clamped(scale, fillScale: fillScale)
        if abs(scale - 1) < 0.08 { return 1 }
        if fillScale > 1.08, abs(scale - fillScale) / fillScale < 0.05 { return fillScale }
        return scale
    }
}
