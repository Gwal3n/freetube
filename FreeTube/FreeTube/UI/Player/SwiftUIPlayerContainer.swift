import SwiftUI
import UIKit

/// Owns the app-wide player presentation without delegating layout or gestures to UIKit.
/// Playback remains in `PlayerStateManager`; this view only moves between expanded, mini, and
/// dismissed presentations of that shared state.
@available(iOS 17.0, *)
struct SwiftUIPlayerContainer<Content: View>: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let thumbnail: UIImage?
    let content: Content

    @State private var presentationTranslation: CGFloat = 0
    @State private var miniDismissTranslation: CGFloat = 0
    @State private var dragIsVertical: Bool?
    @State private var expandedDragStartedDown = false
    @State private var expandedDragCanCollapse = false
    @State private var suppressMiniPlayerTap = false

    init(thumbnail: UIImage?, @ViewBuilder content: () -> Content) {
        self.thumbnail = thumbnail
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let transition = transitionProgress(in: proxy.size)
            let systemInsets = PlayerLayoutMetrics.safeAreaInsets
            let expandedTopInset = verticalSizeClass == .compact
                || !player.playerPresentationGestureEnabled
                ? 0
                : systemInsets.top
            let miniBottomPadding = PlayerLayoutMetrics.bottomTabBarClearance

            ZStack(alignment: .bottom) {
                content
                    .allowsHitTesting(!player.fullScreenPresented)

                if player.miniPlayerVisible {
                    Color.black
                        .opacity(max(0, 1 - transition * 1.4))
                        .allowsHitTesting(false)
                        .zIndex(1)
                        .transition(.opacity)

                    FullScreenPlayer()
                        .frame(
                            width: proxy.size.width,
                            height: max(0, proxy.size.height - expandedTopInset)
                        )
                        .background(Color.black)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18 * transition,
                                style: .continuous
                            )
                        )
                        .offset(y: expandedPlayerOffset(transition: transition, in: proxy.size))
                        .zIndex(2)
                        // UIKit-backed video surfaces can visually outrun SwiftUI move
                        // transitions. Position is animated by the container offset instead.
                        .transition(.opacity)
                        // The UIKit-backed player stays mounted for a seamless mini/expanded
                        // transition. Once settled in mini mode it is fully off-screen, but must
                        // also leave hit testing explicitly so it cannot intercept Library rows
                        // through its original hosting-controller bounds.
                        .simultaneousGesture(expandedPresentationGesture(in: proxy.size))
                        // Keep this outermost. Gesture modifiers install their own hit-test
                        // participation, so disabling the content before attaching the drag still
                        // allowed the off-screen recognizer to cancel List and Form row taps.
                        .allowsHitTesting(player.fullScreenPresented)

                    SwiftUIMiniPlayer(
                        thumbnail: thumbnail,
                        onExpand: expandPlayerFromTap,
                        onDismiss: dismissMiniPlayer
                    )
                        .padding(.horizontal, 20)
                        .padding(.bottom, miniBottomPadding)
                        .offset(
                            y: max(0, miniDismissTranslation)
                                + min(0, presentationTranslation)
                                + miniHandoffOffset(for: transition)
                        )
                        .opacity(miniOpacity(for: transition) * miniDismissOpacity)
                        .zIndex(3)
                        .simultaneousGesture(miniPlayerGesture(in: proxy.size))
                        .allowsHitTesting(!player.fullScreenPresented)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: player.fullScreenPresented)
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
    }

    private func transitionProgress(in size: CGSize) -> CGFloat {
        if player.fullScreenPresented {
            let fullTravel = size.height + 28
            return min(1, max(0, presentationTranslation / fullTravel))
        }
        let distance = max(280, min(420, size.height * 0.46))
        return min(1, max(0, 1 + presentationTranslation / distance))
    }

    private func miniOpacity(for transition: CGFloat) -> CGFloat {
        // Fade over most of the handoff instead of squeezing the entire appearance into the last
        // few frames. Smoothstep keeps both ends soft without adding a second animation owner.
        let progress = min(1, max(0, (transition - 0.18) / 0.82))
        return progress * progress * (3 - 2 * progress)
    }

    /// A small upward lift visually connects a miniplayer tap to the expanded sheet travelling
    /// upward. Because this derives from the same transition value, interactive swipes and the
    /// reverse collapse remain perfectly synchronized with the fade.
    private func miniHandoffOffset(for transition: CGFloat) -> CGFloat {
        -12 * (1 - miniOpacity(for: transition))
    }

    /// During a downward drag the sheet moves one point for every point travelled by the finger.
    /// Settled and mini-to-expanded transitions still animate across the complete viewport.
    private func expandedPlayerOffset(transition: CGFloat, in size: CGSize) -> CGFloat {
        if player.fullScreenPresented, presentationTranslation > 0 {
            return presentationTranslation
        }
        return transition * (size.height + 28)
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
                    let startedOnVideo = value.startLocation.y
                        <= expandedTopInset + player.expandedPlayerSurfaceHeight
                    expandedDragCanCollapse = startedOnVideo || player.playerPanelAtTop
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
                let shouldCollapse = presentationTranslation > 110
                    || value.predictedEndTranslation.height > 230
                withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88)) {
                    presentationTranslation = 0
                    if shouldCollapse {
                        player.chapterListPresented = false
                        player.fullScreenPresented = false
                    }
                }
            }
    }

    private func miniPlayerGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard !player.fullScreenPresented else { return }
                suppressMiniPlayerTap = true
                establishAxis(for: value.translation)
                guard dragIsVertical == true else { return }
                if value.translation.height < 0 {
                    presentationTranslation = value.translation.height
                    miniDismissTranslation = 0
                } else {
                    presentationTranslation = 0
                    miniDismissTranslation = value.translation.height
                }
            }
            .onEnded { value in
                defer {
                    dragIsVertical = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(180))
                        suppressMiniPlayerTap = false
                    }
                }
                guard !player.fullScreenPresented, dragIsVertical == true else {
                    presentationTranslation = 0
                    miniDismissTranslation = 0
                    return
                }

                let predicted = value.predictedEndTranslation.height
                if presentationTranslation < -90 || predicted < -190 {
                    expandPlayer()
                } else if miniDismissTranslation > 70 || predicted > 170 {
                    let occlusionTravel = miniPlayerOcclusionTravel
                    if miniDismissTranslation >= occlusionTravel {
                        finishMiniPlayerDismissal()
                        return
                    }
                    withAnimation(
                        .smooth(duration: 0.16),
                        completionCriteria: .logicallyComplete
                    ) {
                        miniDismissTranslation = occlusionTravel
                    } completion: {
                        finishMiniPlayerDismissal()
                    }
                } else {
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82)) {
                        presentationTranslation = 0
                        miniDismissTranslation = 0
                    }
                }
            }
    }

    private func establishAxis(for translation: CGSize) {
        guard dragIsVertical == nil,
              max(abs(translation.width), abs(translation.height)) >= 8 else { return }
        dragIsVertical = abs(translation.height) > abs(translation.width) * 1.1
    }

    private func expandPlayer() {
        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.88)) {
            presentationTranslation = 0
            miniDismissTranslation = 0
            player.fullScreenPresented = true
        }
        player.requestInlinePlaybackRestoration()
    }

    private func expandPlayerFromTap() {
        guard !suppressMiniPlayerTap else { return }
        expandPlayer()
    }

    /// The miniplayer sits immediately above the tab bar. Moving it by its own rendered height
    /// is enough for the system bar to occlude it; sending it farther down makes dismissal feel
    /// detached from the interface and unnecessarily lengthens the close-button animation.
    private var miniPlayerOcclusionTravel: CGFloat { 78 }

    /// Keep small exploratory drags visually solid, then fade continuously as the bar enters the
    /// tab bar. It is fully transparent before its state is removed, avoiding a visible pause at
    /// the animation completion boundary.
    private var miniDismissOpacity: CGFloat {
        let fadeStart: CGFloat = 24
        let fadeDistance = miniPlayerOcclusionTravel - fadeStart
        let progress = (miniDismissTranslation - fadeStart) / fadeDistance
        return 1 - min(1, max(0, progress))
    }

    private func dismissMiniPlayer() {
        suppressMiniPlayerTap = true
        guard !reduceMotion else {
            finishMiniPlayerDismissal()
            return
        }
        withAnimation(
            .smooth(duration: 0.18),
            completionCriteria: .logicallyComplete
        ) {
            miniDismissTranslation = miniPlayerOcclusionTravel
        } completion: {
            finishMiniPlayerDismissal()
        }
    }

    private func finishMiniPlayerDismissal() {
        player.dismiss()
        presentationTranslation = 0
        miniDismissTranslation = 0
        suppressMiniPlayerTap = false
    }
}
