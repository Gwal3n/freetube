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
    @State private var suppressMiniPlayerTap = false
    @State private var playerActionsSuppressed = false
    @State private var actionSuppressionReleaseTask: Task<Void, Never>?

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
                        // Keep the container's simultaneous drag (which preserves panel scrolling),
                        // but prevent controls beneath an accepted vertical drag from firing too.
                        .environment(\.isEnabled, !playerActionsSuppressed)
                        .simultaneousGesture(expandedPresentationGesture(in: proxy.size))

                    SwiftUIMiniPlayer(
                        thumbnail: thumbnail,
                        onExpand: expandPlayerFromTap,
                        onDismiss: { dismissMiniPlayer(in: proxy.size) }
                    )
                        .padding(.horizontal, 20)
                        .padding(.bottom, miniBottomPadding)
                        .offset(
                            y: max(0, miniDismissTranslation)
                                + min(0, presentationTranslation)
                        )
                        .opacity(miniOpacity(for: transition))
                        .allowsHitTesting(!player.fullScreenPresented)
                        .zIndex(3)
                        .environment(\.isEnabled, !playerActionsSuppressed)
                        .simultaneousGesture(miniPlayerGesture(in: proxy.size))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: player.fullScreenPresented)
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: player.miniPlayerVisible)
        }
        // Keep the tab shell's geometry identical in expanded, mini, and dismissed states. Only
        // FullScreenPlayer itself is inset below the portrait status area.
        .ignoresSafeArea()
        .onDisappear {
            actionSuppressionReleaseTask?.cancel()
            playerActionsSuppressed = false
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
        min(1, max(0, (transition - 0.68) / 0.32))
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
                      !player.chapterListPresented,
                      player.playerPanelAtTop,
                      !player.playerPanelGestureStartedAwayFromTop else { return }
                let directionWasUndetermined = dragIsVertical == nil
                establishAxis(for: value.translation)
                guard dragIsVertical == true else { return }
                if directionWasUndetermined {
                    expandedDragStartedDown = value.translation.height > 0
                }
                guard expandedDragStartedDown else { return }
                suppressPlayerActionsForPresentationDrag()
                player.playerPresentationGestureActive = true
                // A small amount of initial resistance preserves the pleasant top-edge rubber
                // band before the whole player begins following the finger.
                presentationTranslation = max(0, value.translation.height - 12)
            }
            .onEnded { value in
                defer {
                    dragIsVertical = nil
                    expandedDragStartedDown = false
                    player.playerPresentationGestureActive = false
                    releasePlayerActionsAfterPresentationDrag()
                }
                guard player.fullScreenPresented,
                      dragIsVertical == true,
                      expandedDragStartedDown else {
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
                suppressPlayerActionsForPresentationDrag()
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
                    releasePlayerActionsAfterPresentationDrag()
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
                    withAnimation(
                        .interactiveSpring(response: 0.34, dampingFraction: 0.9),
                        completionCriteria: .logicallyComplete
                    ) {
                        miniDismissTranslation = size.height * 0.25
                    } completion: {
                        player.dismiss()
                        presentationTranslation = 0
                        miniDismissTranslation = 0
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

    /// A simultaneous presentation drag must remain compatible with the panel ScrollView, but it
    /// must not also complete a button press that began under the finger. Keep controls disabled
    /// through the end of the UIKit touch-delivery cycle, then restore them promptly.
    private func suppressPlayerActionsForPresentationDrag() {
        actionSuppressionReleaseTask?.cancel()
        playerActionsSuppressed = true
    }

    private func releasePlayerActionsAfterPresentationDrag() {
        guard playerActionsSuppressed else { return }
        actionSuppressionReleaseTask?.cancel()
        actionSuppressionReleaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            playerActionsSuppressed = false
        }
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

    private func dismissMiniPlayer(in size: CGSize) {
        suppressMiniPlayerTap = true
        guard !reduceMotion else {
            player.dismiss()
            suppressMiniPlayerTap = false
            return
        }
        withAnimation(
            .interactiveSpring(response: 0.3, dampingFraction: 0.92),
            completionCriteria: .logicallyComplete
        ) {
            miniDismissTranslation = max(90, size.height * 0.14)
        } completion: {
            player.dismiss()
            miniDismissTranslation = 0
            suppressMiniPlayerTap = false
        }
    }
}
