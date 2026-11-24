import SwiftUI

/// Non-modal live chat browser. Portrait: sheet below the video with chapter-style drag dismiss.
/// Landscape: trailing column beside the video.
@available(iOS 17.0, *)
struct LiveChatPanel: View {
    private static let dismissalThreshold: CGFloat = 42

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let videoID: String
    let isLandscape: Bool
    @Binding var expansionProgress: CGFloat
    let expansionTravel: CGFloat
    let onDismiss: () -> Void

    @State private var model: LiveChatViewModel
    @State private var dismissTranslation: CGFloat = 0
    @State private var listScrollOffset: CGFloat = 0
    @State private var listOverscroll: CGFloat = 0
    @State private var listDismissOrigin: CGFloat = 0
    @State private var listDragStartExpansion: CGFloat = 0
    @State private var isDraggingListSheet = false
    @State private var headerDragStartExpansion: CGFloat?
    @Environment(\.scenePhase) private var scenePhase

    init(
        videoID: String,
        isLandscape: Bool,
        expansionProgress: Binding<CGFloat>,
        expansionTravel: CGFloat,
        onDismiss: @escaping () -> Void
    ) {
        self.videoID = videoID
        self.isLandscape = isLandscape
        self._expansionProgress = expansionProgress
        self.expansionTravel = expansionTravel
        self.onDismiss = onDismiss
        _model = State(wrappedValue: LiveChatViewModel(videoID: videoID))
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
        .offset(y: isLandscape ? 0 : max(0, dismissTranslation))
        .errorToast(Bindable(model).errorState)
        .task(id: videoID) {
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
            chatList
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, rawOffset in
                    listScrollOffset = max(0, rawOffset)
                    let overscroll = max(0, -rawOffset)
                    listOverscroll = overscroll
                    if isDraggingListSheet, listDismissOrigin == 0, overscroll <= 0.5 {
                        isDraggingListSheet = false
                    }
                }
                .simultaneousGesture(listHandoffDismissGesture)
        } else {
            chatList
        }
    }

    @ViewBuilder
    private var chatList: some View {
        if model.chatUnavailable {
            ContentUnavailableView(
                "Live chat unavailable",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Chat isn’t available for this stream.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isLoading && model.messages.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.messages.isEmpty {
            ContentUnavailableView(
                model.chatEnded ? "Live chat has ended" : "Waiting for messages",
                systemImage: "text.bubble",
                description: Text(model.chatEnded
                    ? "This stream’s chat is no longer updating."
                    : "New messages will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.messages) { message in
                            LiveChatRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .offset(y: isDraggingListSheet ? -listOverscroll : 0)
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.always, axes: .vertical)
                .onChange(of: model.messages.last?.id) { _, id in
                    guard let id else { return }
                    // Stay pinned to the latest message while near the bottom.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

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
                    isDraggingListSheet = true
                }
                let travel = max(0, value.translation.height - listDismissOrigin)
                if listDragStartExpansion > 0 {
                    expansionProgress = max(0, listDragStartExpansion - travel / max(1, expansionTravel))
                } else {
                    dismissTranslation = travel
                }
            }
            .onEnded { value in
                guard !isLandscape else { return }
                if isDraggingListSheet {
                    let finalPosition = max(0, value.translation.height - listDismissOrigin)
                    let projectedPosition = max(
                        0,
                        value.predictedEndTranslation.height - listDismissOrigin
                    )
                    if listDragStartExpansion > 0 {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                            let projected = listDragStartExpansion - projectedPosition / max(1, expansionTravel)
                            expansionProgress = projected < 0.5 ? 0 : 1
                        }
                    } else if finalPosition >= Self.dismissalThreshold,
                              projectedPosition >= Self.dismissalThreshold {
                        onDismiss()
                    } else {
                        withAnimation(.snappy(duration: 0.22)) {
                            dismissTranslation = 0
                        }
                    }
                }
                listDismissOrigin = 0
                if listOverscroll <= 0.5 {
                    isDraggingListSheet = false
                }
            }
    }

    private var headerDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !isLandscape else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                if headerDragStartExpansion == nil { headerDragStartExpansion = expansionProgress }
                let start = headerDragStartExpansion ?? 0
                expansionProgress = min(1, max(0, start - value.translation.height / max(1, expansionTravel)))
                dismissTranslation = start == 0 ? max(0, value.translation.height) : 0
            }
            .onEnded { value in
                guard !isLandscape else { return }
                guard let start = headerDragStartExpansion else { return }
                headerDragStartExpansion = nil
                let finalPosition = max(0, value.translation.height)
                let projectedPosition = max(0, value.predictedEndTranslation.height)
                if start == 0, finalPosition >= Self.dismissalThreshold,
                   projectedPosition >= Self.dismissalThreshold {
                    onDismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        let projected = start - value.predictedEndTranslation.height / max(1, expansionTravel)
                        expansionProgress = projected > 0.5 ? 1 : 0
                        dismissTranslation = 0
                    }
                }
            }
    }
}
