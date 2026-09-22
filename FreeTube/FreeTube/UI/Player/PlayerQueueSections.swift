import SwiftUI
import Kingfisher

/// Playlist context and recommendation queue shown below the expanded player's metadata.
///
/// This view owns only disclosure/windowing state. Playback and queue mutations remain in the
/// shared `PlayerStateManager`, while navigation out of the player remains with its parent.
@available(iOS 17.0, *)
struct PlayerQueueSections: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let showsUpNext: Bool
    let upNextInitialCount: Int
    let onOpenPlaylist: (String) -> Void

    @State private var isQueueExpanded = false
    @State private var isManualQueueExpanded = true
    @State private var upNextVisibleLimit = 5
    @State private var isPlaylistExpanded = true
    @State private var playlistItemsBefore = 20
    @State private var playlistItemsAfter = 20
    @State private var draggedManualQueueVideoID: String?
    @State private var manualQueueDragOriginIDs: [String] = []
    @State private var lastManualQueueDragTargetID: String?

    private static let queueRowHeight: CGFloat = 56
    private static let queueRowFootprint: CGFloat = queueRowHeight + 8

    @ViewBuilder
    var body: some View {
        if player.activePlaylist != nil || !player.manualQueue.isEmpty || showsUpNext {
            VStack(alignment: .leading, spacing: 8) {
                playlistPanel
                manualQueuePanel
                if showsUpNext {
                    queuePanel
                }
            }
        }
    }

    // MARK: - Manual queue

    @ViewBuilder
    private var manualQueuePanel: some View {
        if !player.manualQueue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                            isManualQueueExpanded.toggle()
                        }
                    } label: {
                        PlayerSectionHeading(
                            title: "Queue",
                            detail: "\(player.manualQueue.count)",
                            isExpanded: isManualQueueExpanded,
                            showsDisclosureIndicator: false
                        )
                    }
                    .buttonStyle(ResponsiveButtonStyle())

                    Button(role: .destructive) {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                            player.clearManualQueue()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .accessibilityLabel("Clear queue")

                    Button {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                            isManualQueueExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isManualQueueExpanded ? 90 : 0))
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .accessibilityLabel(isManualQueueExpanded ? "Collapse queue" : "Expand queue")
                }
                .padding(.horizontal)

                if isManualQueueExpanded {
                    List {
                        ForEach(player.manualQueue) { video in
                            queueRow(
                                video,
                                preservesPlaylistContext: false,
                                showsReorderHandle: true,
                                onPlay: {
                                    player.removeFromManualQueue(videoID: video.id)
                                    player.load(video)
                                },
                                onRemove: { player.removeFromManualQueue(videoID: video.id) }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    player.removeFromManualQueue(videoID: video.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .frame(height: Self.queueRowHeight)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: manualQueueListHeight)
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Sizing

    private var manualQueueListHeight: CGFloat {
        CGFloat(max(1, player.manualQueue.count)) * Self.queueRowFootprint + 32
    }

    private var queueListHeight: CGFloat {
        let loadMoreRows = canRevealMoreUpNext ? 1 : 0
        let count = max(1, displayedUpNextVideos.count + loadMoreRows)
        return CGFloat(count) * Self.queueRowFootprint + 32
    }

    private var playlistListHeight: CGFloat {
        let controls = (playlistWindowLowerBound > 0 ? 1 : 0)
            + (playlistWindowUpperBound < player.queue.items.count || player.canLoadMorePlaylistItems ? 1 : 0)
        return CGFloat(max(1, displayedPlaylistIndices.count + controls)) * Self.queueRowFootprint + 32
    }

    private var playlistWindowLowerBound: Int {
        max(0, player.queue.currentIndex - playlistItemsBefore)
    }

    private var playlistWindowUpperBound: Int {
        min(player.queue.items.count, player.queue.currentIndex + playlistItemsAfter + 1)
    }

    private var displayedPlaylistIndices: Range<Int> {
        playlistWindowLowerBound..<playlistWindowUpperBound
    }

    private var displayedQueueIndices: [Int] {
        player.queue.items.indices.filter { player.queue.items[$0].id != player.currentVideo?.id }
    }

    private var allUpNextVideos: [Video] {
        player.activePlaylist == nil
            ? displayedQueueIndices.map { player.queue.items[$0] }
            : player.playlistRecommendations
    }

    private var displayedUpNextVideos: [Video] {
        Array(allUpNextVideos.prefix(max(1, upNextVisibleLimit)))
    }

    private var canRevealMoreUpNext: Bool {
        upNextVisibleLimit < allUpNextVideos.count || player.canLoadMoreRecommendations
    }

    // MARK: - Playlist

    @ViewBuilder
    private var playlistPanel: some View {
        if let playlist = player.activePlaylist {
            VStack(alignment: .leading, spacing: 8) {
                collapsiblePanelHeader(
                    title: "Playlist",
                    detail: playlist.title,
                    isExpanded: $isPlaylistExpanded,
                    onOpen: { onOpenPlaylist(playlist.id) }
                )
                if isPlaylistExpanded {
                    List {
                        if playlistWindowLowerBound > 0 {
                            Button {
                                playlistItemsBefore += 20
                            } label: {
                                Label("Load 20 previous", systemImage: "chevron.up")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: Self.queueRowHeight)
                            }
                            .buttonStyle(ResponsiveButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        ForEach(displayedPlaylistIndices, id: \.self) { index in
                            queueRow(player.queue.items[index], preservesPlaylistContext: true)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .frame(height: Self.queueRowHeight)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                        if playlistWindowUpperBound < player.queue.items.count {
                            Button {
                                playlistItemsAfter += 20
                            } label: {
                                Label("Load 20 next", systemImage: "chevron.down")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: Self.queueRowHeight)
                            }
                            .buttonStyle(ResponsiveButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else if player.canLoadMorePlaylistItems {
                            loadMoreQueueButton(isLoading: player.isLoadingMorePlaylistVideos) {
                                await player.loadMorePlaylistItems()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: playlistListHeight)
                }
            }
        }
    }

    // MARK: - Up Next

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                    isQueueExpanded.toggle()
                }
            } label: {
                PlayerSectionHeading(title: "Up next", isExpanded: isQueueExpanded)
            }
            .buttonStyle(ResponsiveButtonStyle())
            .padding(.horizontal)

            ZStack(alignment: .top) {
                List {
                    ForEach(displayedUpNextVideos) { video in
                        queueRow(video, preservesPlaylistContext: false)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    player.enqueue(video)
                                } label: {
                                    Label("Add to queue", systemImage: "text.badge.plus")
                                }
                                .tint(.indigo)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    player.removeFromUpNext(videoID: video.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .frame(height: Self.queueRowHeight)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    if canRevealMoreUpNext {
                        Button {
                            Task { await revealMoreUpNext() }
                        } label: {
                            HStack {
                                Spacer()
                                if player.isLoadingMoreRecommendations {
                                    ProgressView()
                                } else {
                                    Label("Load more", systemImage: "chevron.down")
                                        .font(.subheadline.weight(.medium))
                                }
                                Spacer()
                            }
                            .frame(height: Self.queueRowHeight)
                        }
                        .buttonStyle(ResponsiveButtonStyle())
                        .disabled(player.isLoadingMoreRecommendations)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: queueListHeight)
            }
            .frame(height: isQueueExpanded ? queueListHeight : 0, alignment: .top)
            .clipped()
            .opacity(isQueueExpanded ? 1 : 0)
            .allowsHitTesting(isQueueExpanded)
        }
        .onChange(of: player.currentVideo?.id) {
            isQueueExpanded = false
            upNextVisibleLimit = upNextInitialCount
        }
        .onChange(of: upNextInitialCount) { _, newValue in
            upNextVisibleLimit = newValue
        }
        .onAppear { upNextVisibleLimit = upNextInitialCount }
    }

    private func revealMoreUpNext() async {
        let increment = 5
        if upNextVisibleLimit < allUpNextVideos.count {
            upNextVisibleLimit = min(upNextVisibleLimit + increment, allUpNextVideos.count)
            return
        }
        await player.loadMoreRecommendations()
        upNextVisibleLimit = min(upNextVisibleLimit + increment, allUpNextVideos.count)
    }

    // MARK: - Shared row presentation

    private func collapsiblePanelHeader(
        title: String,
        detail: String? = nil,
        isExpanded: Binding<Bool>,
        onOpen: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                PlayerSectionHeading(
                    title: title,
                    detail: detail,
                    isExpanded: isExpanded.wrappedValue
                )
            }
            .buttonStyle(ResponsiveButtonStyle())
            if let onOpen {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel("Open playlist")
            }
        }
        .padding(.horizontal)
    }

    private func loadMoreQueueButton(
        isLoading: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Label("Load more", systemImage: "chevron.down")
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
            }
            .frame(height: Self.queueRowHeight)
        }
        .buttonStyle(ResponsiveButtonStyle())
        .disabled(isLoading)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    private func queueRow(
        _ video: Video,
        preservesPlaylistContext: Bool,
        showsReorderHandle: Bool = false,
        onPlay: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) -> some View {
        let removalAction: (() -> Void)? = if let onRemove {
            onRemove
        } else if !preservesPlaylistContext {
            { player.removeFromUpNext(videoID: video.id) }
        } else {
            nil
        }

        return HStack(spacing: 0) {
            Button {
                if let onPlay {
                    onPlay()
                } else {
                    player.load(video, skipRecommendations: preservesPlaylistContext)
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        KFImage(video.thumbnailURL)
                            .thumbnail(size: CGSize(width: 80, height: 45)) {
                                MediaStyle.placeholderFill
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 45)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        if !video.durationString.isEmpty {
                            Text(video.durationString)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    video.isLive ? Color.red : Color.black.opacity(0.78),
                                    in: RoundedRectangle(cornerRadius: 3)
                                )
                                .padding(3)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title)
                            .font(.subheadline)
                            .foregroundStyle(
                                preservesPlaylistContext && video.id == player.currentVideo?.id
                                    ? Color.accentColor
                                    : Color.primary
                            )
                            .lineLimit(2)
                        Text(queueRowMetadata(for: video))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if video.id == player.currentVideo?.id, !preservesPlaylistContext {
                        NowPlayingIndicator(videoID: video.id)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Self.queueRowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())

            if showsReorderHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: Self.queueRowHeight)
                    .contentShape(Rectangle())
                    .gesture(manualQueueReorderGesture(for: video.id))
                    .accessibilityLabel("Reorder \(video.title)")
                    .accessibilityHint("Drag to change its position in the queue")
            }

            VideoMoreActionsMenu(
                video: video,
                offersPlayNext: !preservesPlaylistContext,
                onRemoveFromUpNext: removalAction
            )
        }
        .background {
            if preservesPlaylistContext, video.id == player.currentVideo?.id {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            }
        }
    }

    private func queueRowMetadata(for video: Video) -> String {
        [video.channelName, video.viewCountString]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func manualQueueReorderGesture(for videoID: String) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if draggedManualQueueVideoID == nil {
                    draggedManualQueueVideoID = videoID
                    manualQueueDragOriginIDs = player.manualQueue.map(\.id)
                    lastManualQueueDragTargetID = videoID
                }
                guard draggedManualQueueVideoID == videoID,
                      let sourceIndex = manualQueueDragOriginIDs.firstIndex(of: videoID),
                      !manualQueueDragOriginIDs.isEmpty else { return }

                let rowDelta = Int(
                    (value.translation.height / Self.queueRowFootprint).rounded()
                )
                let targetIndex = min(
                    max(0, sourceIndex + rowDelta),
                    manualQueueDragOriginIDs.count - 1
                )
                let targetID = manualQueueDragOriginIDs[targetIndex]
                guard targetID != videoID,
                      targetID != lastManualQueueDragTargetID else { return }

                lastManualQueueDragTargetID = targetID
                withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                    player.moveManualQueue(
                        videoID: videoID,
                        relativeTo: targetID,
                        placeAfterTarget: targetIndex > sourceIndex
                    )
                }
            }
            .onEnded { _ in
                draggedManualQueueVideoID = nil
                manualQueueDragOriginIDs = []
                lastManualQueueDragTargetID = nil
            }
    }
}
