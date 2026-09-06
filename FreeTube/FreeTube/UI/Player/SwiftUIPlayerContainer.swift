import SwiftUI
import UIKit

/// Owns the app-wide player presentation without delegating layout or gestures to UIKit.
/// Playback remains in `PlayerStateManager`; this view only moves between expanded, mini, and
/// dismissed presentations of that shared state.
@available(iOS 17.0, *)
struct SwiftUIPlayerContainer<Content: View>: View {
    @Environment(PlayerStateManager.self) private var player

    let thumbnail: UIImage?
    let content: Content

    @State private var presentationTranslation: CGFloat = 0
    @State private var miniDismissTranslation: CGFloat = 0
    @State private var dragIsVertical: Bool?
    @State private var expandedDragStartedDown = false

    init(thumbnail: UIImage?, @ViewBuilder content: () -> Content) {
        self.thumbnail = thumbnail
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let transition = transitionProgress(in: proxy.size)

            ZStack(alignment: .bottom) {
                tabContent(transition: transition, size: proxy.size)

                if player.miniPlayerVisible {
                    Color.black
                        .opacity(max(0, 1 - transition * 1.4))
                        .allowsHitTesting(false)
                        .zIndex(1)

                    FullScreenPlayer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Extend only through the home-indicator region. The top remains in the
                        // safe area, so the status bar and Dynamic Island never cover controls.
                        .ignoresSafeArea(.container, edges: .bottom)
                        .background(Color.black)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18 * transition,
                                style: .continuous
                            )
                        )
                        .scaleEffect(1 - (0.018 * transition), anchor: .top)
                        .offset(y: expandedPlayerOffset(transition: transition, in: proxy.size))
                        .shadow(
                            color: .black.opacity(0.22 * transition),
                            radius: 18,
                            y: 8
                        )
                        .zIndex(2)
                        .simultaneousGesture(expandedPresentationGesture(in: proxy.size))

                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.smooth(duration: 0.28), value: player.fullScreenPresented)
        }
    }

    @ViewBuilder
    private func tabContent(transition: CGFloat, size: CGSize) -> some View {
        if #available(iOS 26.0, *) {
            content
                .allowsHitTesting(!player.fullScreenPresented)
                .tabViewBottomAccessory(isEnabled: player.miniPlayerVisible) {
                    miniPlayer(transition: transition, size: size)
                        .padding(.horizontal, 10)
                }
        } else {
            content
                .allowsHitTesting(!player.fullScreenPresented)
                .overlay(alignment: .bottom) {
                    if player.miniPlayerVisible {
                        miniPlayer(transition: transition, size: size)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 50)
                    }
                }
        }
    }

    @ViewBuilder
    private func miniPlayer(transition: CGFloat, size: CGSize) -> some View {
        SwiftUIMiniPlayer(thumbnail: thumbnail, onExpand: expandPlayer)
            .offset(
                y: max(0, miniDismissTranslation)
                    + min(0, presentationTranslation)
            )
            .opacity(miniOpacity(for: transition))
            .scaleEffect(0.98 + (0.02 * miniOpacity(for: transition)))
            .allowsHitTesting(player.miniPlayerVisible && !player.fullScreenPresented)
            .simultaneousGesture(miniPlayerGesture(in: size))
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
                defer { dragIsVertical = nil }
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

    private func expandPlayer() {
        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.88)) {
            presentationTranslation = 0
            miniDismissTranslation = 0
            player.fullScreenPresented = true
        }
        player.requestInlinePlaybackRestoration()
    }
}
