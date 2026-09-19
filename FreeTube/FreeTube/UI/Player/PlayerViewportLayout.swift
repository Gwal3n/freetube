import CoreGraphics
import UIKit

/// Pure geometry policy for the expanded player viewport.
///
/// Keeping these calculations outside `FullScreenPlayer` prevents its view body from becoming a
/// second source of layout rules. The type has no state and deliberately does not own any player
/// behavior; it only returns the same frames and offsets used by the existing presentation.
enum PlayerViewportLayout {
    /// Baseline portrait height. Standard and tall media retain the familiar 16:9 player, while
    /// genuinely cinematic sources may use their wider native ratio instead of carrying a band
    /// of empty black canvas. The lower bound avoids impractically thin chrome for malformed or
    /// extreme presentation sizes.
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
        return max(8, aspectHeight - availableSize.height + 16)
    }

    /// Keeps landscape chrome inside the visible widescreen picture and outside the notch. Tall
    /// videos deliberately retain the complete safe width so their controls remain usable rather
    /// than being squeezed into the narrow portrait image at the centre of a landscape display.
    static func controlFrame(
        surfaceSize: CGSize,
        isLandscape: Bool,
        hasChapterSidebar: Bool,
        presentationSize: CGSize,
        safeAreaInsets: UIEdgeInsets
    ) -> CGRect {
        let full = CGRect(origin: .zero, size: surfaceSize)
        guard isLandscape, surfaceSize.width > 0, surfaceSize.height > 0 else { return full }

        let safeMinX = min(surfaceSize.width, safeAreaInsets.left)
        let safeMaxX = max(
            safeMinX,
            surfaceSize.width - (hasChapterSidebar ? 0 : safeAreaInsets.right)
        )
        let safeWidth = safeMaxX - safeMinX
        let isTallVideo = presentationSize.width > 0
            && presentationSize.height > 0
            && presentationSize.height > presentationSize.width
        guard !isTallVideo else {
            return CGRect(x: safeMinX, y: 0, width: safeWidth, height: surfaceSize.height)
        }

        let aspect = presentationSize.width > 0 && presentationSize.height > 0
            ? presentationSize.width / presentationSize.height
            : 16 / 9
        let fittedWidth = min(safeWidth, surfaceSize.height * aspect)
        return CGRect(
            x: safeMinX + (safeWidth - fittedWidth) / 2,
            y: 0,
            width: fittedWidth,
            height: surfaceSize.height
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

    /// Tracks the timeline thumb while keeping the 116pt-wide preview plus edge clearance wholly
    /// inside the player surface at both ends of the video.
    static func storyboardPreviewX(
        time: TimeInterval,
        duration: TimeInterval,
        surfaceWidth: CGFloat
    ) -> CGFloat {
        guard duration.isFinite, duration > 0, time.isFinite, surfaceWidth > 0 else {
            return surfaceWidth / 2
        }
        let fraction = min(max(time / duration, 0), 1)
        let trackX = 12 + (surfaceWidth - 24) * CGFloat(fraction)
        let minimumCenterX: CGFloat = 66
        guard surfaceWidth >= minimumCenterX * 2 else { return surfaceWidth / 2 }
        return min(max(trackX, minimumCenterX), surfaceWidth - minimumCenterX)
    }
}
