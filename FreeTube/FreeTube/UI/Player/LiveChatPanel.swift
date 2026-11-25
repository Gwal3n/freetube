import SwiftUI

/// Non-modal live chat browser. Portrait: sheet below the video with continuous drag dismiss.
/// Landscape: trailing column beside the video. The view model is owned by the player so messages
/// survive sheet dismiss.
@available(iOS 17.0, *)
struct LiveChatPanel: View {
    /// Same threshold as chapters — past the player-bottom edge by this much dismisses.
    private static let dismissalThreshold: CGFloat = 42
    /// Distance from the live edge that counts as "still following".
    private static let pinToBottomSlack: CGFloat = 80
    /// Must be snugly at the bottom before follow re-engages after reading history.
    private static let pinReengageDistance: CGFloat = 28
    private static let bottomAnchorID = "liveChatBottomAnchor"

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: LiveChatViewModel
    let isLandscape: Bool
    @Binding var expansionProgress: CGFloat
    /// Video-surface height — distance from expanded top to the player-bottom edge.
    let expansionTravel: CGFloat
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
    /// Sticky follow: cleared when the user scrolls away from the live edge.
    @State private var isPinnedToBottom = true
    @State private var isProgrammaticScroll = false
    @State private var followScrollTask: Task<Void, Never>?
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
        // Flatten UIKit-backed ProgressView into this layer so entrance/expand motion moves the
        // spinner with the sheet instead of leaving it parked on screen.
        .compositingGroup()
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
                Button(action: onDismiss) {
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
        if model.chatUnavailable {
            emptyState(
                title: "Live chat unavailable",
                systemImage: "bubble.left.and.bubble.right",
                description: "Chat isn’t available for this stream."
            )
        } else if model.isLoading && model.messages.isEmpty {
            // Sit under the header like other sheet content — a vertically-centered spinner in
            // a growing frame looks glued to the screen while the grabber rises around it.
            VStack(spacing: 0) {
                ProgressView()
                    .controlSize(.regular)
                    .padding(.top, 36)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading live chat")
            .simultaneousGesture(listHandoffDismissGesture)
        } else if model.messages.isEmpty {
            emptyState(
                title: model.chatEnded ? "Live chat has ended" : "Waiting for messages",
                systemImage: "text.bubble",
                description: model.chatEnded ? "This stream’s chat is no longer updating." : nil
            )
        } else if #available(iOS 18.0, *) {
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
                } action: { _, sample in
                    listScrollOffset = sample.topOffset
                    listOverscroll = sample.overscroll
                    if !isProgrammaticScroll {
                        updatePinState(distanceFromBottom: sample.distanceFromBottom)
                    }
                    if isDraggingListSheet, listDismissOrigin == 0, sample.overscroll <= 0.5 {
                        isDraggingListSheet = false
                    }
                }
                .simultaneousGesture(listHandoffDismissGesture)
        } else {
            // iOS 17 has no scroll-geometry signal, so list dismiss would steal every downward
            // drag — match chapters and keep dismiss/expand on the grabber only.
            chatRows
        }
    }

    private var chatRows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 4) {
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
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    // Dedicated bottom buffer outside LazyVStack. Auto-scroll targets this id so
                    // follow keeps the same gap under the latest row that manual scrolling shows.
                    Color.clear
                        .frame(height: bottomContentInset)
                        .id(Self.bottomAnchorID)
                        .accessibilityHidden(true)
                }
                // Cancel the ScrollView rubber-band once the sheet owns the drag so rows don't
                // travel twice as fast as the header.
                .offset(y: isDraggingListSheet ? -listOverscroll : 0)
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.always, axes: .vertical)
            // Always apply the same modifier chain — toggling modifiers remounts the scroll view
            // and jumps the offset to the top.
            .modifier(LiveChatBottomScrollAnchor(isPinned: isPinnedToBottom))
            .onAppear {
                isPinnedToBottom = true
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: model.messageRevision) { _, _ in
                guard isPinnedToBottom, !isDraggingListSheet else { return }
                if #unavailable(iOS 18.0) {
                    scheduleFollowScroll(proxy: proxy)
                }
            }
            .onChange(of: expansionProgress) { _, newValue in
                guard newValue > 0.95 || newValue < 0.05 else { return }
                guard isPinnedToBottom else { return }
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func emptyState(title: String, systemImage: String, description: String? = nil) -> some View {
        Group {
            if let description {
                ContentUnavailableView(
                    title,
                    systemImage: systemImage,
                    description: Text(description)
                )
            } else {
                ContentUnavailableView(title, systemImage: systemImage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Empty body is always "at the top" — pull down dismisses like chapters overscroll.
        .simultaneousGesture(listHandoffDismissGesture)
    }

    private func updatePinState(distanceFromBottom: CGFloat) {
        if distanceFromBottom > Self.pinToBottomSlack {
            isPinnedToBottom = false
        } else if distanceFromBottom < Self.pinReengageDistance {
            isPinnedToBottom = true
        }
    }

    private func scheduleFollowScroll(proxy: ScrollViewProxy) {
        guard isPinnedToBottom, !isDraggingListSheet else { return }
        followScrollTask?.cancel()
        followScrollTask = Task { @MainActor in
            // Coalesce several paced reveals into one unanimated settle.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, isPinnedToBottom, !isDraggingListSheet else { return }
            scrollToBottom(proxy: proxy)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        isProgrammaticScroll = true
        isPinnedToBottom = true
        // Unanimated — animated scrollTo against a growing list is what felt jumpy.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(24))
            isProgrammaticScroll = false
        }
    }

    /// Same handoff as chapters: list owns the gesture until the top, then continued downward
    /// travel moves the sheet through expand / collapse / dismiss.
    private var listHandoffDismissGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !isLandscape else { return }
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
                let travel = value.translation.height - listDismissOrigin
                let position = PlayerSheetDragMath.position(
                    startExpansion: listDragStartExpansion,
                    startDismiss: listDragStartDismiss,
                    translationHeight: travel,
                    expansionTravel: expansionTravel
                )
                expansionProgress = position.expansion
                dismissTranslation = position.dismiss
            }
            .onEnded { value in
                guard !isLandscape else { return }
                if isDraggingListSheet {
                    let projectedTravel = value.predictedEndTranslation.height - listDismissOrigin
                    settleSheet(
                        startExpansion: listDragStartExpansion,
                        startDismiss: listDragStartDismiss,
                        predictedTranslation: projectedTravel
                    )
                }
                listDismissOrigin = 0
                if listOverscroll <= 0.5 {
                    isDraggingListSheet = false
                }
            }
    }

    /// Same as chapters: grabber/title drag never competes with list scrolling.
    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !isLandscape else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                if headerDragStartExpansion == nil {
                    headerDragStartExpansion = expansionProgress
                    headerDragStartDismiss = dismissTranslation
                }
                let start = headerDragStartExpansion ?? 0
                let position = PlayerSheetDragMath.position(
                    startExpansion: start,
                    startDismiss: headerDragStartDismiss,
                    translationHeight: value.translation.height,
                    expansionTravel: expansionTravel
                )
                expansionProgress = position.expansion
                dismissTranslation = position.dismiss
            }
            .onEnded { value in
                guard !isLandscape else { return }
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

    private func settleSheet(
        startExpansion: CGFloat,
        startDismiss: CGFloat,
        predictedTranslation: CGFloat
    ) {
        let settlement = PlayerSheetDragMath.settlement(
            startExpansion: startExpansion,
            startDismiss: startDismiss,
            predictedTranslationHeight: predictedTranslation,
            expansionTravel: expansionTravel,
            dismissThreshold: Self.dismissalThreshold
        )
        switch settlement {
        case .dismiss:
            // Same as chapters: clear local offset and flip presentation so the overlay's
            // `.move(edge: .bottom)` transition finishes the leave — do not animate expansion
            // to 0 first, which parks the sheet at the player-bottom detent halfway down.
            dismissTranslation = 0
            onDismiss()
        case .expanded:
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                expansionProgress = 1
                dismissTranslation = 0
            }
        case .collapsed:
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                expansionProgress = 0
                dismissTranslation = 0
            }
        }
    }
}

@available(iOS 18.0, *)
private struct ScrollPinSample: Equatable {
    var topOffset: CGFloat
    var overscroll: CGFloat
    var distanceFromBottom: CGFloat
}

/// Keeps follow glued to the live edge without remounting the ScrollView when pin toggles.
/// Branching to a bare `content` when unpinned reset the offset to the top.
@available(iOS 17.0, *)
private struct LiveChatBottomScrollAnchor: ViewModifier {
    let isPinned: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            // Same modifier always: bottom while following, top while reading history so new
            // rows append below without yanking the viewport.
            content.defaultScrollAnchor(isPinned ? .bottom : .top, for: .sizeChanges)
        } else {
            content
        }
    }
}
