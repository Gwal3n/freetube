import SwiftUI

/// Non-modal live chat browser. Portrait: sheet below the video with continuous drag dismiss.
/// Landscape: trailing column beside the video. The view model is owned by the player so messages
/// survive sheet dismiss.
@available(iOS 17.0, *)
struct LiveChatPanel: View {
    /// Past the player-bottom edge by this much commits a full dismiss (no collapsed detent).
    private static let dismissalThreshold: CGFloat = 28
    private static let pinToBottomSlack: CGFloat = 120
    private static let bottomAnchorID = "liveChatBottomAnchor"

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: LiveChatViewModel
    let isLandscape: Bool
    @Binding var expansionProgress: CGFloat
    /// Video-surface height — distance from expanded top to the player-bottom edge.
    let expansionTravel: CGFloat
    /// Full player-column height. Used so dismiss travel clears the sheet even when the feed
    /// strip is taller than the video.
    let containerHeight: CGFloat
    let onDismiss: () -> Void

    @State private var dismissTranslation: CGFloat = 0
    @State private var listScrollOffset: CGFloat = 0
    @State private var listOverscroll: CGFloat = 0
    @State private var listDismissOrigin: CGFloat = 0
    @State private var listDragStartExpansion: CGFloat = 0
    @State private var listDragStartDismiss: CGFloat = 0
    @State private var isDraggingListSheet = false
    @State private var headerDragStartExpansion: CGFloat?
    @State private var headerDragStartDismiss: CGFloat = 0
    /// Sticky follow: cleared only when the user scrolls upward away from live.
    @State private var isPinnedToBottom = true
    @State private var isProgrammaticScroll = false
    @State private var followScrollTask: Task<Void, Never>?
    @State private var isDismissing = false
    @Environment(\.scenePhase) private var scenePhase

    /// Modest pad above the home indicator — large insets plus scrollTo were parking the
    /// latest rows under the bottom edge of the sheet.
    private var bottomContentInset: CGFloat {
        max(PlayerLayoutMetrics.safeAreaInsets.bottom, 8) + 8
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            chatScrollView
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: isLandscape ? 0 : 16 * (1 - expansionProgress), style: .continuous))
        .overlay(alignment: isLandscape ? .leading : .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: isLandscape ? 0.5 : nil, height: isLandscape ? nil : 0.5)
        }
        .shadow(color: .black.opacity(0.28), radius: 14)
        .offset(y: isLandscape ? 0 : max(0, dismissTranslation))
        .errorToast(Bindable(model).errorState)
        .task(id: model.videoID) {
            model.startPolling()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.startPolling()
            } else {
                model.stopPolling()
            }
        }
        .onDisappear {
            followScrollTask?.cancel()
            followScrollTask = nil
            model.stopPolling()
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            if !isLandscape {
                Capsule()
                    .fill(.secondary.opacity(0.55))
                    .frame(width: 36, height: 5)
                    .padding(.top, 7)
                    .padding(.bottom, 1)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live chat")
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismissAnimated()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(.interaction, Rectangle().inset(by: -7))
                .accessibilityLabel("Close live chat")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(headerDragGesture)
    }

    private var statusSubtitle: String {
        if model.chatUnavailable {
            String(localized: "Unavailable")
        } else if model.chatEnded {
            String(localized: "Ended")
        } else if model.isPolling {
            String(localized: "Live")
        } else if model.isLoading {
            String(localized: "Loading…")
        } else {
            String(localized: "Read only")
        }
    }

    @ViewBuilder
    private var chatScrollView: some View {
        if #available(iOS 18.0, *) {
            chatRows
                .onScrollGeometryChange(for: ScrollPinSample.self) { geometry in
                    let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
                    let remaining = geometry.contentSize.height
                        - scrolled
                        - geometry.containerSize.height
                    return ScrollPinSample(
                        topOffset: max(0, scrolled),
                        overscroll: max(0, -scrolled),
                        distanceFromBottom: remaining
                    )
                } action: { old, sample in
                    listScrollOffset = sample.topOffset
                    listOverscroll = sample.overscroll
                    if !isProgrammaticScroll {
                        if sample.distanceFromBottom < Self.pinToBottomSlack {
                            isPinnedToBottom = true
                        } else if sample.topOffset + 1.5 < old.topOffset {
                            // Only an upward user scroll clears the pin — not content growth below.
                            isPinnedToBottom = false
                        }
                    }
                    if isDraggingListSheet, listDismissOrigin == 0, sample.overscroll <= 0.5 {
                        isDraggingListSheet = false
                    }
                }
                .simultaneousGesture(listHandoffDismissGesture)
        } else {
            chatRows
        }
    }

    private var chatRows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if model.chatUnavailable {
                            ContentUnavailableView(
                                "Live chat unavailable",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("Chat isn’t available for this stream.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                        } else if model.isLoading && model.messages.isEmpty {
                            ProgressView()
                                .controlSize(.regular)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 36)
                                .padding(.bottom, 24)
                                .accessibilityLabel("Loading live chat")
                        } else if model.messages.isEmpty {
                            ContentUnavailableView(
                                model.chatEnded ? "Live chat has ended" : "Waiting for messages",
                                systemImage: "text.bubble",
                                description: Text(model.chatEnded
                                    ? "This stream’s chat is no longer updating."
                                    : "New messages will appear here.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                        } else {
                            ForEach(model.messages) { message in
                                LiveChatRow(message: message) { channelID in
                                    player.presentChannelPreview(
                                        id: channelID,
                                        name: message.authorName
                                    )
                                }
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, bottomContentInset)

                    // Outside LazyVStack so the anchor is always realized for scrollTo.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                        .accessibilityHidden(true)
                }
                // Cancel the ScrollView rubber-band once the sheet owns the drag so rows don't
                // travel twice as fast as the header.
                .offset(y: isDraggingListSheet ? -listOverscroll : 0)
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.always, axes: .vertical)
            .onAppear {
                isPinnedToBottom = true
                scheduleFollowScroll(proxy: proxy, force: true)
            }
            .onChange(of: model.messageRevision) { _, _ in
                scheduleFollowScroll(proxy: proxy, force: false)
            }
            .onChange(of: expansionProgress) { _, newValue in
                // Re-pin after expand/collapse so layout height changes don't leave rows
                // scrolled past the new viewport.
                guard newValue > 0.95 || newValue < 0.05 else { return }
                scheduleFollowScroll(proxy: proxy, force: true)
            }
        }
    }

    private func scheduleFollowScroll(proxy: ScrollViewProxy, force: Bool) {
        guard force || isPinnedToBottom else { return }
        guard !isDraggingListSheet, !isDismissing else { return }
        followScrollTask?.cancel()
        followScrollTask = Task { @MainActor in
            // Let LazyVStack commit inserted rows, then scroll; a second pass catches late layout.
            await Task.yield()
            guard !Task.isCancelled, !isDraggingListSheet else { return }
            guard force || isPinnedToBottom else { return }
            scrollToBottom(proxy: proxy, animated: !force && !reduceMotion)
            try? await Task.sleep(for: .milliseconds(48))
            guard !Task.isCancelled, force || isPinnedToBottom, !isDraggingListSheet else { return }
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        isProgrammaticScroll = true
        isPinnedToBottom = true
        let scroll = {
            // Prefer the last real row so we don't overshoot into empty bottom padding.
            if let lastID = model.messages.last?.id {
                proxy.scrollTo(lastID, anchor: .bottom)
            } else {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
        if animated, !reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                scroll()
            }
        } else {
            scroll()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(animated ? 240 : 24))
            isProgrammaticScroll = false
        }
    }

    private func dismissAnimated() {
        guard !isDismissing else { return }
        isDismissing = true
        // Drive the sheet fully off-screen from its current top, then drop presentation.
        let currentTop = PlayerSheetDragMath.Position.top(
            expansion: expansionProgress,
            dismiss: dismissTranslation,
            travel: expansionTravel
        )
        let offscreen = dismissTranslation + max(containerHeight - currentTop, expansionTravel) + 40
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.30)) {
            dismissTranslation = offscreen
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 10 : 310))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onDismiss()
            }
        }
    }

    private func dismissFromDrag() {
        guard !isDismissing else { return }
        isDismissing = true
        let currentTop = PlayerSheetDragMath.Position.top(
            expansion: expansionProgress,
            dismiss: dismissTranslation,
            travel: expansionTravel
        )
        // Clear the remaining visible span — feed can be taller than the video travel distance.
        let offscreen = dismissTranslation + max(containerHeight - currentTop, 1) + 40
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.30)) {
            dismissTranslation = offscreen
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 10 : 310))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onDismiss()
            }
        }
    }

    private var listHandoffDismissGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !isLandscape, !isDismissing else { return }
                let downward = value.translation.height > 0
                    && abs(value.translation.height) > abs(value.translation.width)
                guard downward else { return }

                if !isDraggingListSheet {
                    guard listScrollOffset <= 1 else { return }
                    listDismissOrigin = value.translation.height
                    listDragStartExpansion = expansionProgress
                    listDragStartDismiss = dismissTranslation
                    isDraggingListSheet = true
                }
                applyDrag(
                    startExpansion: listDragStartExpansion,
                    startDismiss: listDragStartDismiss,
                    translationHeight: value.translation.height - listDismissOrigin
                )
            }
            .onEnded { value in
                guard !isLandscape, !isDismissing else { return }
                if isDraggingListSheet {
                    settleSheet(
                        startExpansion: listDragStartExpansion,
                        startDismiss: listDragStartDismiss,
                        predictedTranslation: value.predictedEndTranslation.height - listDismissOrigin
                    )
                }
                listDismissOrigin = 0
                if listOverscroll <= 0.5 {
                    isDraggingListSheet = false
                }
            }
    }

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard !isLandscape, !isDismissing else { return }
                guard abs(value.translation.height) > abs(value.translation.width) * 0.6 else { return }
                if headerDragStartExpansion == nil {
                    headerDragStartExpansion = expansionProgress
                    headerDragStartDismiss = dismissTranslation
                }
                applyDrag(
                    startExpansion: headerDragStartExpansion ?? expansionProgress,
                    startDismiss: headerDragStartDismiss,
                    translationHeight: value.translation.height
                )
            }
            .onEnded { value in
                guard !isLandscape, !isDismissing else { return }
                guard let start = headerDragStartExpansion else { return }
                let startDismiss = headerDragStartDismiss
                headerDragStartExpansion = nil
                headerDragStartDismiss = 0
                settleSheet(
                    startExpansion: start,
                    startDismiss: startDismiss,
                    predictedTranslation: value.predictedEndTranslation.height
                )
            }
    }

    /// Finger-following updates without animation so the grabber stays 1:1 with the touch.
    private func applyDrag(
        startExpansion: CGFloat,
        startDismiss: CGFloat,
        translationHeight: CGFloat
    ) {
        let position = PlayerSheetDragMath.position(
            startExpansion: startExpansion,
            startDismiss: startDismiss,
            translationHeight: translationHeight,
            expansionTravel: expansionTravel
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            expansionProgress = position.expansion
            dismissTranslation = position.dismiss
        }
    }

    private func settleSheet(
        startExpansion: CGFloat,
        startDismiss: CGFloat,
        predictedTranslation: CGFloat
    ) {
        let travel = max(1, expansionTravel)
        let startTop = PlayerSheetDragMath.Position.top(
            expansion: startExpansion,
            dismiss: startDismiss,
            travel: travel
        )
        let projectedTop = max(0, startTop + predictedTranslation)
        // No collapsed detent — past the player-bottom edge dismisses fully; otherwise expand.
        if projectedTop >= travel + Self.dismissalThreshold {
            dismissFromDrag()
            return
        }
        withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
            expansionProgress = 1
            dismissTranslation = 0
        }
    }
}

@available(iOS 18.0, *)
private struct ScrollPinSample: Equatable {
    var topOffset: CGFloat
    var overscroll: CGFloat
    var distanceFromBottom: CGFloat
}
