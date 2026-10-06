import SwiftUI
import UIKit

/// Owns the app-wide player presentation without delegating layout or gestures to UIKit.
/// Playback remains in `PlayerStateManager`; this view moves one video surface between expanded, floating, and
/// dismissed presentations of that shared state.
@available(iOS 17.0, *)
struct SwiftUIPlayerContainer<Content: View>: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let content: Content

    @State private var presentationTranslation: CGFloat = 0
    @State private var dragIsVertical: Bool?
    @State private var expandedDragStartedDown = false
    @State private var expandedDragCanCollapse = false
    @State private var captionPresentationReady = true
    @State private var chromePresentationReady = true
    @State private var floatingCorner: FloatingCorner = .bottomTrailing
    @State private var floatingDragTranslation: CGSize = .zero
    @State private var floatingDismissTranslation: CGSize = .zero
    @State private var floatingGestureActive = false
    @State private var floatingActionsSuppressed = false
    @State private var floatingIsDismissing = false
    @State private var floatingShouldFade = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let transition = transitionProgress(in: proxy.size)
            let systemInsets = PlayerLayoutMetrics.safeAreaInsets
            let expandedTopInset = verticalSizeClass == .compact
                || player.portraitPlayerFullscreenActive
                ? 0
                : systemInsets.top
            let miniBottomPadding = PlayerLayoutMetrics.bottomTabBarClearance
            let floatingWidth = min(216, max(160, proxy.size.width - 36))
            let floatingSize = CGSize(width: floatingWidth, height: floatingWidth * 9 / 16)
            let floatingBase = floatingCorner.center(
                in: proxy.size,
                window: floatingSize,
                topInset: systemInsets.top,
                bottomInset: miniBottomPadding
            )
            let floatingPosition = CGPoint(
                x: floatingBase.x + floatingDragTranslation.width + floatingDismissTranslation.width,
                y: floatingBase.y + floatingDragTranslation.height + floatingDismissTranslation.height
            )

            ZStack(alignment: .bottom) {
                content
                    .allowsHitTesting(!player.fullScreenPresented)

                if player.miniPlayerVisible {
                    Color.black
                        .opacity(max(0, 1 - transition * 1.4))
                        .allowsHitTesting(false)
                        .zIndex(1)
                        .transition(.opacity)

                    FullScreenPlayer(
                        captionPresentationReady: captionPresentationReady,
                        chromePresentationReady: chromePresentationReady
                    )
                        .frame(
                            width: player.fullScreenPresented ? proxy.size.width : floatingSize.width,
                            height: player.fullScreenPresented
                                ? max(0, proxy.size.height - expandedTopInset)
                                : floatingSize.height
                        )
                        // Keep the player's existing viewport and controls below the status
                        // area, but make its clipping host edge-to-edge. Only the scaled media
                        // can then extend into that top inset during an upward fullscreen drag.
                        .padding(.top, player.fullScreenPresented ? expandedTopInset : 0)
                        .frame(
                            width: player.fullScreenPresented ? proxy.size.width : floatingSize.width,
                            height: player.fullScreenPresented ? proxy.size.height : floatingSize.height,
                            alignment: .top
                        )
                        .background(Color.black)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: player.fullScreenPresented
                                    ? 26 * sqrt(max(0, transition)) : 14,
                                style: .continuous
                            )
                        )
                        .shadow(
                            color: player.fullScreenPresented ? .clear : .black.opacity(0.32),
                            radius: player.fullScreenPresented ? 0 : 14,
                            y: player.fullScreenPresented ? 0 : 5
                        )
                        // Position the hosting view itself, not just its SwiftUI drawing. The
                        // AVPlayerViewController inside can commit a frame ahead of an `.offset`
                        // animation, exposing video at the destination while the chrome moves.
                        .position(
                            x: player.fullScreenPresented ? proxy.size.width / 2 : floatingPosition.x,
                            y: player.fullScreenPresented
                                ? expandedPlayerCenterY(transition: transition, in: proxy.size)
                                : floatingPosition.y
                        )
                        .opacity(floatingIsDismissing && floatingShouldFade ? 0 : 1)
                        .zIndex(2)
                        .transition(.opacity)
                        // The UIKit-backed player stays mounted as its host moves between the
                        // expanded viewport and the floating window. The mini host is not a
                        // touch target: only the compact SwiftUI chrome accepts gestures.
                        .simultaneousGesture(expandedPresentationGesture(in: proxy.size))
                        // Keep this outermost. Gesture modifiers install hit-test participation;
                        // disabling the compact video host protects List and Form rows underneath.
                        .allowsHitTesting(player.fullScreenPresented)

                    FloatingMiniPlayerChrome(
                        actionsEnabled: !floatingActionsSuppressed && !floatingIsDismissing,
                        onExpand: expandPlayer,
                        onDismiss: dismissFloatingPlayer
                    )
                        .frame(width: floatingSize.width, height: floatingSize.height)
                        .position(floatingPosition)
                        .opacity(player.fullScreenPresented || (floatingIsDismissing && floatingShouldFade) ? 0 : 1)
                        .zIndex(3)
                        .simultaneousGesture(floatingGesture(in: proxy.size, window: floatingSize, base: floatingBase))
                        .allowsHitTesting(!player.fullScreenPresented && !floatingIsDismissing)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Expansion and collapse already supply their own interactive springs. A second
            // animation bound to this Bool can reanimate the mini glass after it reappears.
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: player.miniPlayerVisible)
        }
        // Keep the tab shell's geometry identical in expanded, mini, and dismissed states. Only
        // FullScreenPlayer itself is inset below the portrait status area.
        .ignoresSafeArea()
        .onChange(of: player.playerExpansionRequest) { _, _ in
            // Feed/Search selections and first playback launches arrive here instead of mutating
            // `fullScreenPresented` behind the container's back. Use the exact same coordinated
            // path as a direct tap on the miniplayer.
            guard player.miniPlayerVisible, !player.fullScreenPresented else { return }
            expandPlayer()
        }
        .onChange(of: player.fullScreenPresented) { _, isPresented in
            if !isPresented {
                captionPresentationReady = true
                chromePresentationReady = true
            }
        }
        .onChange(of: player.miniPlayerVisible) { _, visible in
            if !visible {
                floatingDragTranslation = .zero
                floatingDismissTranslation = .zero
                floatingIsDismissing = false
                floatingShouldFade = false
                floatingGestureActive = false
                floatingActionsSuppressed = false
            }
        }
    }

    private func transitionProgress(in size: CGSize) -> CGFloat {
        if player.fullScreenPresented {
            let fullTravel = size.height + 28
            return min(1, max(0, presentationTranslation / fullTravel))
        }
        let distance = max(280, min(420, size.height * 0.46))
        return min(1, max(0, 1 + presentationTranslation / distance))
    }

    /// During a downward drag the sheet moves one point for every point travelled by the finger.
    /// Settled and mini-to-expanded transitions still animate across the complete viewport.
    private func expandedPlayerCenterY(transition: CGFloat, in size: CGSize) -> CGFloat {
        let settledCenter = size.height / 2
        if player.fullScreenPresented, presentationTranslation > 0 {
            return settledCenter + presentationTranslation
        }
        return settledCenter + transition * (size.height + 28)
    }

    private func expandedPresentationGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard player.fullScreenPresented,
                      verticalSizeClass != .compact,
                      player.playerPresentationGestureEnabled,
                      !player.chapterListPresented else { return }
                let directionWasUndetermined = dragIsVertical == nil
                establishAxis(for: value.translation)
                guard dragIsVertical == true else { return }
                if directionWasUndetermined {
                    expandedDragStartedDown = value.translation.height > 0
                    let expandedTopInset = verticalSizeClass == .compact ? 0 : PlayerLayoutMetrics.safeAreaInsets.top
                    let startedOnVideo = value.startLocation.y >= expandedTopInset
                        && value.startLocation.y <= expandedTopInset + player.expandedPlayerSurfaceHeight
                    // A playlist sheet may cover the lower part of the video. Its own scrolling
                    // and dismissal retain ownership; only a drag on the uncovered video can
                    // collapse the player while the sheet is open.
                    expandedDragCanCollapse = startedOnVideo
                        || (!player.playlistPanelPresented && player.playerPanelAtTop)
                }
                guard expandedDragStartedDown, expandedDragCanCollapse else { return }
                player.playerPresentationGestureActive = true
                // A small amount of initial resistance preserves the pleasant top-edge rubber
                // band before the whole player begins following the finger.
                presentationTranslation = max(0, value.translation.height - 12)
            }
            .onEnded { value in
                defer {
                    dragIsVertical = nil
                    expandedDragStartedDown = false
                    expandedDragCanCollapse = false
                    player.playerPresentationGestureActive = false
                }
                guard player.fullScreenPresented,
                      dragIsVertical == true,
                      expandedDragStartedDown,
                      expandedDragCanCollapse else {
                    presentationTranslation = 0
                    return
                }
                // The finger's last direction wins. A quick upward reversal must not commit a
                // collapse merely because the sheet is still past its downward distance mark.
                let isReversingUpward = value.velocity.height < -180
                let shouldCollapse = !isReversingUpward && (
                    presentationTranslation > 110
                    || value.predictedEndTranslation.height > 230
                )
                withAnimation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.08)) {
                    presentationTranslation = 0
                    if shouldCollapse {
                        player.chapterListPresented = false
                        player.fullScreenPresented = false
                    }
                }
            }
    }

    private func floatingGesture(in size: CGSize, window: CGSize, base: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard !player.fullScreenPresented, !floatingIsDismissing else { return }
                floatingGestureActive = true
                floatingActionsSuppressed = true
                floatingDragTranslation = value.translation
            }
            .onEnded { value in
                guard !player.fullScreenPresented, !floatingIsDismissing else { return }
                floatingGestureActive = false
                let actual = CGPoint(
                    x: base.x + value.translation.width,
                    y: base.y + value.translation.height
                )
                let projected = CGPoint(
                    x: base.x + value.predictedEndTranslation.width,
                    y: base.y + value.predictedEndTranslation.height
                )
                let speed = hypot(value.velocity.width, value.velocity.height)
                let movedOffscreen = actual.x < -window.width * 0.2
                    || actual.x > size.width + window.width * 0.2
                    || actual.y < -window.height * 0.2
                    || actual.y > size.height + window.height * 0.2
                let flickedOffscreen = speed > 650 && (
                    projected.x < -window.width * 0.3
                    || projected.x > size.width + window.width * 0.3
                    || projected.y < -window.height * 0.3
                    || projected.y > size.height + window.height * 0.3
                )
                if movedOffscreen || flickedOffscreen {
                    dismissFloatingPlayer(toward: projected, in: size, from: actual)
                    return
                }

                let nextCorner = FloatingCorner.nearest(to: projected, in: size)
                withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.36, dampingFraction: 0.82)) {
                    floatingCorner = nextCorner
                    floatingDragTranslation = .zero
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    if !floatingGestureActive { floatingActionsSuppressed = false }
                }
            }
    }

    private func establishAxis(for translation: CGSize) {
        guard dragIsVertical == nil,
              max(abs(translation.width), abs(translation.height)) >= 8 else { return }
        dragIsVertical = abs(translation.height) > abs(translation.width) * 1.1
    }

    private func expandPlayer() {
        // Timeline-driven captions can otherwise appear at their final screen position before
        // the mini-to-full player host has completed its upward handoff.
        captionPresentationReady = false
        chromePresentationReady = false
        withAnimation(
            reduceMotion ? nil : .interactiveSpring(response: 0.4, dampingFraction: 0.88),
            completionCriteria: .logicallyComplete
        ) {
            presentationTranslation = 0
            floatingDragTranslation = .zero
            floatingDismissTranslation = .zero
            floatingGestureActive = false
            floatingActionsSuppressed = false
            player.fullScreenPresented = true
        } completion: {
            guard player.fullScreenPresented else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                captionPresentationReady = true
                chromePresentationReady = true
            }
        }
        player.requestInlinePlaybackRestoration()
    }

    private func dismissFloatingPlayer() {
        floatingActionsSuppressed = true
        guard !reduceMotion else {
            finishFloatingDismissal()
            return
        }
        withAnimation(
            .smooth(duration: 0.18),
            completionCriteria: .logicallyComplete
        ) {
            floatingIsDismissing = true
            floatingShouldFade = true
        } completion: {
            finishFloatingDismissal()
        }
    }

    private func dismissFloatingPlayer(toward projected: CGPoint, in size: CGSize, from actual: CGPoint) {
        floatingActionsSuppressed = true
        let horizontal = abs(projected.x - actual.x) >= abs(projected.y - actual.y)
        let target = CGPoint(
            x: horizontal
                ? (projected.x < actual.x ? -150 : size.width + 150) : actual.x,
            y: horizontal
                ? actual.y : (projected.y < actual.y ? -100 : size.height + 100)
        )
        guard !reduceMotion else {
            finishFloatingDismissal()
            return
        }
        withAnimation(.smooth(duration: 0.2), completionCriteria: .logicallyComplete) {
            floatingDismissTranslation = CGSize(
                width: target.x - actual.x,
                height: target.y - actual.y
            )
            floatingIsDismissing = true
            floatingShouldFade = false
        } completion: {
            finishFloatingDismissal()
        }
    }

    private func finishFloatingDismissal() {
        player.dismiss()
        presentationTranslation = 0
        floatingDragTranslation = .zero
        floatingDismissTranslation = .zero
        floatingIsDismissing = false
        floatingShouldFade = false
        floatingGestureActive = false
        floatingActionsSuppressed = false
    }
}

/// Four predictable resting places leave the window draggable without letting it obscure
/// the status bar or native tab bar. A drag remains free under the finger until release.
@available(iOS 17.0, *)
private enum FloatingCorner {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    func center(in viewport: CGSize, window: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> CGPoint {
        let margin: CGFloat = 14
        let leading = margin + window.width / 2
        let trailing = max(leading, viewport.width - margin - window.width / 2)
        let top = topInset + margin + window.height / 2
        let bottom = max(top, viewport.height - bottomInset - margin - window.height / 2)
        switch self {
        case .topLeading: return CGPoint(x: leading, y: top)
        case .topTrailing: return CGPoint(x: trailing, y: top)
        case .bottomLeading: return CGPoint(x: leading, y: bottom)
        case .bottomTrailing: return CGPoint(x: trailing, y: bottom)
        }
    }

    static func nearest(to point: CGPoint, in viewport: CGSize) -> FloatingCorner {
        let top = point.y < viewport.height / 2
        let leading = point.x < viewport.width / 2
        switch (top, leading) {
        case (true, true): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }
}
