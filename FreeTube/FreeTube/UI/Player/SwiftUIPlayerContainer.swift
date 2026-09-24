import SwiftUI

/// Presents the expanded player over the tab shell.
///
/// This used to own both halves of the presentation and cross-fade between them: a floating mini
/// bar positioned by measuring the live `UITabBar`, an expanded sheet, and a pile of interpolation
/// — `transitionProgress`, `miniOpacity`, `miniHandoffOffset`, `miniDismissTranslation` — to make
/// one appear to become the other. The mini half is now the tab view's bottom accessory, so the
/// system positions it, shapes it, and slides it into the tab bar as that bar minimises.
///
/// What remains is the part the system does not offer: a full-bleed video sheet that follows the
/// finger down and is interruptible mid-flight. It sits *above* the accessory rather than swapping
/// with it, which is also why the cross-fade is gone — dragging the sheet down simply uncovers the
/// accessory that was there the whole time, the same way a sheet reveals what is underneath it.
///
/// `FullScreenPlayer` stays mounted while a video is loaded even when the sheet is closed. That is
/// deliberate: it owns the `AVPlayerViewController`, and tearing that down on every collapse would
/// flash the video surface on the way back up.
struct SwiftUIPlayerContainer<Content: View>: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let content: Content

    /// Live downward drag on the expanded sheet. Zero whenever the sheet is settled, open or shut.
    @State private var dragTranslation: CGFloat = 0
    @State private var dragIsVertical: Bool?
    @State private var dragStartedDown = false
    @State private var dragCanCollapse = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = expandedTopInset(safeAreaTop: proxy.safeAreaInsets.top)

            ZStack(alignment: .bottom) {
                content
                    .allowsHitTesting(!player.fullScreenPresented)

                if player.miniPlayerVisible {
                    FullScreenPlayer()
                        .frame(
                            width: proxy.size.width,
                            height: max(0, proxy.size.height - topInset)
                        )
                        .background(Color.black)
                        .clipShape(
                            RoundedRectangle(cornerRadius: sheetCornerRadius, style: .continuous)
                        )
                        .offset(y: sheetOffset(in: proxy.size))
                        .simultaneousGesture(collapseGesture(in: proxy.size))
                        // Outermost, and not optional. Gesture modifiers install their own
                        // hit-test participation, so disabling the content before attaching the
                        // drag still let the closed sheet's recognizer cancel taps on rows behind
                        // it.
                        .allowsHitTesting(player.fullScreenPresented)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(
                reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
                value: player.fullScreenPresented
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
                value: player.miniPlayerVisible
            )
        }
        .ignoresSafeArea()
        .onChange(of: player.playerExpansionRequest) { _, _ in
            expand()
        }
    }

    // MARK: - Geometry

    /// Portrait leaves the status area uncovered so the sheet reads as a sheet. Landscape and the
    /// no-gesture presentation both go edge to edge.
    private func expandedTopInset(safeAreaTop: CGFloat) -> CGFloat {
        guard verticalSizeClass != .compact, player.playerPresentationGestureEnabled else { return 0 }
        return safeAreaTop
    }

    private func sheetOffset(in size: CGSize) -> CGFloat {
        guard player.fullScreenPresented else { return size.height + 28 }
        return dragTranslation
    }

    /// Square while it is filling the screen, rounded as soon as it starts to travel, so the
    /// corners appear to lift off the display edge rather than being permanently inset.
    private var sheetCornerRadius: CGFloat {
        guard player.fullScreenPresented else { return 18 }
        return min(18, dragTranslation / 6)
    }

    // MARK: - Collapse gesture

    private func collapseGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard player.fullScreenPresented,
                      verticalSizeClass != .compact,
                      player.playerPresentationGestureEnabled,
                      !player.chapterListPresented else { return }
                let axisWasUndetermined = dragIsVertical == nil
                establishAxis(for: value.translation)
                guard dragIsVertical == true else { return }
                if axisWasUndetermined {
                    dragStartedDown = value.translation.height > 0
                    // A drag beginning on the video always collapses. One beginning in the feed
                    // below may only collapse if that feed is already scrolled to its top,
                    // otherwise it is an ordinary scroll.
                    let startedOnVideo = value.startLocation.y
                        <= player.expandedPlayerSurfaceHeight
                    dragCanCollapse = startedOnVideo || player.playerPanelAtTop
                }
                guard dragStartedDown, dragCanCollapse else { return }
                player.playerPresentationGestureActive = true
                // Initial resistance preserves the top-edge rubber band before the sheet commits
                // to following the finger.
                dragTranslation = max(0, value.translation.height - 12)
            }
            .onEnded { value in
                defer {
                    dragIsVertical = nil
                    dragStartedDown = false
                    dragCanCollapse = false
                    player.playerPresentationGestureActive = false
                }
                guard player.fullScreenPresented,
                      dragIsVertical == true,
                      dragStartedDown,
                      dragCanCollapse else {
                    dragTranslation = 0
                    return
                }
                let shouldCollapse = dragTranslation > 110
                    || value.predictedEndTranslation.height > 230
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    dragTranslation = 0
                    if shouldCollapse {
                        player.chapterListPresented = false
                        player.fullScreenPresented = false
                    }
                }
            }
    }

    private func establishAxis(for translation: CGSize) {
        guard dragIsVertical == nil,
              max(abs(translation.width), abs(translation.height)) >= 8 else { return }
        dragIsVertical = abs(translation.height) > abs(translation.width) * 1.1
    }

    private func expand() {
        guard player.miniPlayerVisible, !player.fullScreenPresented else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            dragTranslation = 0
            player.fullScreenPresented = true
        }
        player.requestInlinePlaybackRestoration()
    }
}
