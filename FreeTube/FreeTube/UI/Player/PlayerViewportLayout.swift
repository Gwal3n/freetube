import CoreGraphics
import UIKit

/// Stateless viewport geometry for the expanded player.
enum PlayerViewportLayout {
    static func compactSurfaceHeight(
        width: CGFloat,
        presentationSize: CGSize
    ) -> CGFloat {
        guard width > 0 else { return 0 }
        let sixteenByNine = width * 9 / 16
        guard presentationSize.width > 0, presentationSize.height > 0 else {
            return sixteenByNine
        }
        let naturalHeight = width * presentationSize.height / presentationSize.width
        guard naturalHeight < sixteenByNine else { return sixteenByNine }
        return max(naturalHeight, width * 9 / 21)
    }

    static func timelineBottomPadding(
        availableSize: CGSize,
        isLandscape: Bool
    ) -> CGFloat {
        // The timeline's labels and touch target extend below the visible track. Twenty-eight
        // points keeps that complete control clear of the home indicator without making it feel
        // detached from the lower edge of the video.
        if isLandscape { return 28 }
        let aspectHeight = availableSize.width * 9 / 16
        if availableSize.height < aspectHeight - 1 { return 8 }
        return max(8, aspectHeight - availableSize.height + 16)
    }

    /// Aspect-fits chrome to the visible picture inside the player surface (same box AVPlayer
    /// letterboxes into with `.resizeAspect`). Landscape still respects the notch / home
    /// indicator; tall videos keep the usable safe width rather than a skinny centre strip.
    static func controlFrame(
        surfaceSize: CGSize,
        isLandscape: Bool,
        hasChapterSidebar: Bool,
        presentationSize: CGSize,
        safeAreaInsets: UIEdgeInsets
    ) -> CGRect {
        let full = CGRect(origin: .zero, size: surfaceSize)
        guard surfaceSize.width > 0, surfaceSize.height > 0 else { return full }

        let safeMinX: CGFloat
        let safeMaxX: CGFloat
        if isLandscape {
            safeMinX = min(surfaceSize.width, safeAreaInsets.left)
            safeMaxX = max(
                safeMinX,
                surfaceSize.width - (hasChapterSidebar ? 0 : safeAreaInsets.right)
            )
        } else {
            safeMinX = 0
            safeMaxX = surfaceSize.width
        }
        let safeWidth = max(0, safeMaxX - safeMinX)
        let safeHeight = surfaceSize.height
        guard safeWidth > 0, safeHeight > 0 else { return full }

        // Until AVPlayer reports a size, fill the surface — guessing 16:9 misaligns tall videos.
        guard presentationSize.width > 0, presentationSize.height > 0 else {
            return CGRect(x: safeMinX, y: 0, width: safeWidth, height: safeHeight)
        }

        let isTallVideo = presentationSize.height > presentationSize.width
        if isLandscape, isTallVideo {
            return CGRect(x: safeMinX, y: 0, width: safeWidth, height: safeHeight)
        }

        let aspect = presentationSize.width / presentationSize.height
        let fittedWidth = min(safeWidth, safeHeight * aspect)
        let fittedHeight = min(safeHeight, fittedWidth / aspect)
        return CGRect(
            x: safeMinX + (safeWidth - fittedWidth) / 2,
            y: (safeHeight - fittedHeight) / 2,
            width: fittedWidth,
            height: fittedHeight
        )
    }

    /// Uses the video's display-correct dimensions for portrait/tall media, bounded so the lower
    /// content remains reachable before the header compresses to 16:9.
    static func expandedSurfaceHeight(
        width: CGFloat,
        viewportHeight: CGFloat,
        isLandscape: Bool,
        presentationSize: CGSize
    ) -> CGFloat {
        guard width > 0 else { return 0 }
        let compactHeight = compactSurfaceHeight(
            width: width,
            presentationSize: presentationSize
        )
        guard !isLandscape,
              presentationSize.width > 0,
              presentationSize.height > 0 else { return compactHeight }
        let naturalHeight = width * presentationSize.height / presentationSize.width
        return min(max(naturalHeight, compactHeight), viewportHeight * 0.72)
    }

    /// Tracks the timeline thumb while keeping the preview wholly inside the player surface at
    /// both ends of the video. `edgeClearance` reserves each side's time label, so the preview
    /// stops beside it rather than sliding over it.
    static func storyboardPreviewX(
        time: TimeInterval,
        duration: TimeInterval,
        surfaceWidth: CGFloat,
        previewWidth: CGFloat = 116,
        edgeClearance: CGFloat = 8
    ) -> CGFloat {
        guard duration.isFinite, duration > 0, time.isFinite, surfaceWidth > 0 else {
            return surfaceWidth / 2
        }
        let fraction = min(max(time / duration, 0), 1)
        let trackX = 12 + (surfaceWidth - 24) * CGFloat(fraction)
        let minimumCenterX = previewWidth / 2 + edgeClearance
        guard surfaceWidth >= minimumCenterX * 2 else { return surfaceWidth / 2 }
        return min(max(trackX, minimumCenterX), surfaceWidth - minimumCenterX)
    }
}
