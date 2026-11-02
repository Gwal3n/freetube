import CoreGraphics
import UIKit

/// One layout snapshot for the expanded or floating player at the current viewport size.
/// Keeps the dependent surface, control, and panel measurements in one calculation.
@available(iOS 17.0, *)
struct PlayerViewportGeometry {
    let sidePanelWidth: CGFloat
    let surfaceWidth: CGFloat
    let collapseRange: CGFloat
    let surfaceHeight: CGFloat
    let controlFrame: CGRect
    let timelineBottomPadding: CGFloat
    let captionBottomPadding: CGFloat
    let minimumPanelContentHeight: CGFloat

    init(
        viewportSize: CGSize,
        expandedViewportHeight: CGFloat,
        presentationSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        isFloating: Bool,
        isLandscape: Bool,
        usesPortraitFullscreen: Bool,
        sidePanelPresented: Bool,
        panelScrollOffset: CGFloat,
        collapseProgress: CGFloat,
        controlsVisible: Bool
    ) {
        let sidePanelWidth: CGFloat = !isFloating && isLandscape && sidePanelPresented
            ? min(360, viewportSize.width * 0.38)
            : 0
        let surfaceWidth = viewportSize.width - sidePanelWidth

        // Landscape controls use the available height; portrait starts at the compact ratio.
        let compactSurfaceHeight = isFloating || isLandscape
            ? viewportSize.height
            : PlayerViewportLayout.compactSurfaceHeight(
                width: surfaceWidth,
                presentationSize: presentationSize
            )
        let expandedSurfaceHeight = isFloating || usesPortraitFullscreen
            ? viewportSize.height
            : isLandscape
                ? compactSurfaceHeight
                : PlayerViewportLayout.expandedSurfaceHeight(
                    width: surfaceWidth,
                    viewportHeight: max(viewportSize.height, expandedViewportHeight),
                    isLandscape: isLandscape,
                    presentationSize: presentationSize
                )
        let collapseRange = usesPortraitFullscreen
            ? 0
            : max(0, expandedSurfaceHeight - compactSurfaceHeight)
        let consumedCollapse = min(max(panelScrollOffset, 0), collapseRange)

        // The playlist browser overlays the lower content and must not resize or lift the video.
        let uncollapsedSurfaceHeight = expandedSurfaceHeight - consumedCollapse
        let floatingAspectHeight = surfaceWidth * 9 / 16
        let floatingAspectMix = min(1, max(0, (collapseProgress - 0.65) / 0.35))
        let desiredSurfaceHeight = uncollapsedSurfaceHeight
            + (floatingAspectHeight - uncollapsedSurfaceHeight) * floatingAspectMix
        let surfaceHeight = collapseProgress > 0
            ? min(desiredSurfaceHeight, viewportSize.height) : desiredSurfaceHeight

        let controlFrame = PlayerViewportLayout.controlFrame(
            surfaceSize: CGSize(width: surfaceWidth, height: surfaceHeight),
            isLandscape: isLandscape,
            hasChapterSidebar: sidePanelWidth > 0,
            presentationSize: presentationSize,
            safeAreaInsets: safeAreaInsets
        )
        let timelineBottomPadding = max(
            PlayerViewportLayout.timelineBottomPadding(
                availableSize: controlFrame.size,
                isLandscape: isLandscape
            ),
            isLandscape || usesPortraitFullscreen
                ? safeAreaInsets.bottom + 14
                : 0
        )
        let captionBottomPadding = controlsVisible
            ? timelineBottomPadding + 28
            : isLandscape || usesPortraitFullscreen
                ? safeAreaInsets.bottom + 18
                : 14
        let minimumPanelContentHeight = max(
            0,
            viewportSize.height - compactSurfaceHeight + collapseRange
        )

        self.sidePanelWidth = sidePanelWidth
        self.surfaceWidth = surfaceWidth
        self.collapseRange = collapseRange
        self.surfaceHeight = surfaceHeight
        self.controlFrame = controlFrame
        self.timelineBottomPadding = timelineBottomPadding
        self.captionBottomPadding = captionBottomPadding
        self.minimumPanelContentHeight = minimumPanelContentHeight
    }
}
