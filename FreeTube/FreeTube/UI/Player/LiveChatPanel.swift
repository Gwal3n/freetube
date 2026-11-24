import SwiftUI

/// Non-modal live chat browser. Portrait: sheet below the video with chapter-style drag dismiss.
/// Landscape: trailing column beside the video. The view model is owned by the player so messages
/// survive sheet dismiss.
@available(iOS 17.0, *)
struct LiveChatPanel: View {
    private static let dismissalThreshold: CGFloat = 42
    /// Keep following new messages while the user is roughly at the latest row.
    private static let pinToBottomSlack: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: LiveChatViewModel
    let isLandscape: Bool
    @Binding var expansionProgress: CGFloat
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
    @State private var isNearBottom = true
    @Environment(\.scenePhase) private var scenePhase

    private var bottomContentInset: CGFloat {
        // Clear the home indicator and the sheet's bottom corner radius.
        max(PlayerLayoutMetrics.safeAreaInsets.bottom, 8) + 20
    }

    var body: some View {
        VStack(spacing: 0) {
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
        // Move the complete sheet after background/clipping so the material travels with the drag
        // instead of leaving a parked rectangle over the feed (same as chapters).
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
            // Pause the poller while the sheet is gone; keep messages and continuation.
            model.stopPolling()
        }
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
                        isNearBottom: remaining < Self.pinToBottomSlack
                    )
                } action: { _, sample in
                    listScrollOffset = sample.topOffset
                    listOverscroll = sample.overscroll
                    isNearBottom = sample.isNearBottom
                    // After a cancelled pull, retain compensation until the ScrollView finishes
                    // its own snap-back; dropping it at touch-up would create a one-frame gap.
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
                            LiveChatRow(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, bottomContentInset)
                // Once the gesture hands off, the complete panel already follows the finger. Cancel
                // the ScrollView's simultaneous visual rubber-band so the rows retain a constant
                // distance from the header instead of appearing to travel twice as fast.
                .offset(y: isDraggingListSheet ? -listOverscroll : 0)
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.always, axes: .vertical)
            .onAppear {
                guard let id = model.messages.last?.id else { return }
                proxy.scrollTo(id, anchor: .bottom)
                isNearBottom = true
            }
            .onChange(of: model.messages.last?.id) { _, id in
                guard let id, !isDraggingListSheet, isNearBottom else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    /// The list owns the gesture while it has content above it. As soon as it reaches the top,
    /// continued downward travel is measured from that exact handoff point and moves the sheet.
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

    /// The header is outside the ScrollView, so this recognizer never competes with list scrolling.
    private var headerDragGesture: some Gesture {
        // Measure against the screen rather than the moving panel. A local-space gesture changes
        // its own coordinate system as `.offset` moves the sheet, producing visible oscillation.
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
    var isNearBottom: Bool
}
