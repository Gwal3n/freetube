import SwiftUI

/// Presents the expanded player as an overlay card over the tab shell.
///
/// The mini player is the tab view's bottom accessory — a different view tree — so this cannot
/// morph the live video into that capsule the way Music morphs album art. What it can do is the
/// other half of that language: a card that sits below the status bar, follows the finger on the
/// way up and down, and uncovers the accessory as it recedes.
///
/// `presentationProgress` (0 = parked, 1 = open) is the single visual. The accessory writes it
/// during an upward drag; this container writes it during a downward drag; springs only run when
/// the finger lifts. Implicit animations on `fullScreenPresented` are deliberately absent — they
/// were what made the old slide feel like a modal popping in.
///
/// `FullScreenPlayer` stays mounted while a video is loaded even when the card is parked. It owns
/// the `AVPlayerViewController`, and tearing that down on every collapse flashes the video.
struct SwiftUIPlayerContainer<Content: View>: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let content: Content

    @State private var dragIsVertical: Bool?
    @State private var dragStartedDown = false
    @State private var dragCanCollapse = false
    @State private var horizontalPageConsumed = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = statusBarSeparation
            let travel = max(0, proxy.size.height - topInset)

            ZStack(alignment: .top) {
                content
                    .overlay {
                        Color.black
                            .opacity(0.32 * min(1, player.presentationProgress))
                            .ignoresSafeArea()
                    }
                    .allowsHitTesting(player.presentationProgress < 0.98)

                if player.miniPlayerVisible {
                    FullScreenPlayer()
                        .frame(width: proxy.size.width, height: travel)
                        .background(Color.black)
                        .padding(.top, topInset)
                        .clipped()
                        .offset(y: cardOffset(travel: travel))
                        .simultaneousGesture(cardGesture(travel: travel))
                        .allowsHitTesting(player.presentationProgress > 0.08)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onChange(of: travel, initial: true) { _, newTravel in
                player.presentationTravel = newTravel
            }
        }
        .ignoresSafeArea()
        .onChange(of: player.playerExpansionRequest) { _, _ in
            expand()
        }
        .onChange(of: player.fullScreenPresented) { _, presented in
            guard !player.presentationIsInteractive else { return }
            settle(expanded: presented)
        }
        .onChange(of: player.presentationIsInteractive) { _, interactive in
            guard !interactive else { return }
            settle(expanded: player.fullScreenPresented)
        }
        .onChange(of: player.miniPlayerVisible) { _, visible in
            if !visible {
                player.presentationProgress = 0
            }
        }
    }

    // MARK: - Geometry

    /// Portrait keeps the system status bar on the tab content behind the card. The card itself
    /// never draws into that strip. Landscape and in-place portrait fullscreen go edge to edge.
    private var statusBarSeparation: CGFloat {
        guard verticalSizeClass != .compact, player.playerPresentationGestureEnabled else { return 0 }
        return PlayerLayoutMetrics.safeAreaInsets.top
    }

    private func cardOffset(travel: CGFloat) -> CGFloat {
        let progress = player.presentationProgress
        if progress <= 1 {
            return (1 - progress) * travel
        }
        // Past fully-open the card rubber-bands a little instead of sliding under the status bar.
        return -((progress - 1) / 0.12) * 18
    }

    private var presentationSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.92)
    }

    // MARK: - Gestures

    private func cardGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard player.fullScreenPresented || player.presentationIsInteractive,
                      verticalSizeClass != .compact,
                      player.playerPresentationGestureEnabled,
                      !player.chapterListPresented else { return }
                let axisWasUndetermined = dragIsVertical == nil
                establishAxis(for: value.translation)
                if dragIsVertical == false {
                    return
                }
                guard dragIsVertical == true else { return }
                if axisWasUndetermined {
                    dragStartedDown = value.translation.height > 0
                    let startedOnVideo = value.startLocation.y
                        <= player.expandedPlayerSurfaceHeight + statusBarSeparation
                    dragCanCollapse = startedOnVideo || player.playerPanelAtTop
                }
                guard dragCanCollapse || !dragStartedDown else { return }
                if !player.presentationIsInteractive {
                    player.beginInteractivePresentation()
                }
                let raw = 1 - (value.translation.height / max(travel, 1))
                player.updatePresentationProgress(raw)
            }
            .onEnded { value in
                defer {
                    dragIsVertical = nil
                    dragStartedDown = false
                    dragCanCollapse = false
                    horizontalPageConsumed = false
                }
                if dragIsVertical == false {
                    pageIfNeeded(value)
                    return
                }
                guard player.presentationIsInteractive else { return }
                player.endInteractivePresentation(velocity: value.velocity.height)
            }
    }

    /// Horizontal paging lives on the details card, not the video. The video surface already
    /// owns horizontal-drag seeking; stealing that would make scrubbing fight next/previous.
    private func pageIfNeeded(_ value: DragGesture.Value) {
        guard player.presentationProgress > 0.9,
              !horizontalPageConsumed,
              abs(value.translation.width) > abs(value.translation.height),
              value.startLocation.y > player.expandedPlayerSurfaceHeight + statusBarSeparation
        else { return }
        let distance = value.translation.width
        let flicked = abs(value.velocity.width) > 650
        guard abs(distance) > 80 || flicked else { return }
        horizontalPageConsumed = true
        if distance < 0 {
            player.playNext()
        } else {
            player.playPrevious()
        }
    }

    private func establishAxis(for translation: CGSize) {
        guard dragIsVertical == nil,
              max(abs(translation.width), abs(translation.height)) >= 8 else { return }
        dragIsVertical = abs(translation.height) > abs(translation.width) * 1.1
    }

    private func expand() {
        guard player.miniPlayerVisible else { return }
        player.presentationIsInteractive = false
        player.fullScreenPresented = true
        settle(expanded: true)
        player.requestInlinePlaybackRestoration()
    }

    private func settle(expanded: Bool) {
        let target: CGFloat = expanded ? 1 : 0
        guard abs(player.presentationProgress - target) > 0.001 else { return }
        if reduceMotion {
            player.presentationProgress = target
            return
        }
        withAnimation(presentationSpring) {
            player.presentationProgress = target
        }
    }
}
