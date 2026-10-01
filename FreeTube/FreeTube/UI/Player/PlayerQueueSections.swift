import SwiftUI

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
    /// Anchored when a playlist opens, rather than recentered on every playback change. Keeping
    /// the same rows mounted prevents the playlist panel from jumping as Next advances.
    @State private var playlistWindowAnchor: Int?
    @State private var playlistItemsBefore = 20
    @State private var playlistItemsAfter = 20

    @AppStorage("com.leshko.freetube.deArrowTitles") private var replacesTitles = false
    @AppStorage("com.leshko.freetube.deArrowThumbnails") private var replacesThumbnails = false

    // Reserve the trailing action column before branding arrives, so loading it never moves
    // neighboring rows or makes the fixed-height queue List clip its controls.
    private var queueRowHeight: CGFloat { replacesTitles || replacesThumbnails ? 76 : 56 }
    private var queueRowFootprint: CGFloat { queueRowHeight + 8 }

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
            .onChange(of: player.activePlaylist?.id, initial: true) { _, playlistID in
                playlistWindowAnchor = playlistID == nil ? nil : player.queue.currentIndex
                playlistItemsBefore = 20
                playlistItemsAfter = 20
            }
            .onChange(of: player.queue.currentIndex) { _, newIndex in
                guard player.activePlaylist != nil,
                      newIndex < playlistWindowLowerBound || newIndex >= playlistWindowUpperBound else { return }
                playlistWindowAnchor = newIndex
            }
        }
    }

    // MARK: - Manual queue

    @ViewBuilder
    private var manualQueuePanel: some View {
        if !player.manualQueue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
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

                    Button {
                        player.clearManualQueueWithUndo()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                            .contentShape(Rectangle())
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
                                onPlay: { player.playManualQueueItem(video) },
                                onRemove: { player.removeFromManualQueueWithUndo(videoID: video.id) },
                                showsRemoveButton: true
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .frame(height: queueRowHeight)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                        .onMove { offsets, destination in
                            player.moveManualQueue(fromOffsets: offsets, toOffset: destination)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .environment(\.editMode, .constant(.active))
                    .frame(height: manualQueueListHeight)
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Sizing

    private var manualQueueListHeight: CGFloat {
        CGFloat(max(1, player.manualQueue.count)) * queueRowFootprint + 32
    }

    private var queueListHeight: CGFloat {
        let loadMoreRows = canRevealMoreUpNext ? 1 : 0
        let count = max(1, displayedUpNextVideos.count + loadMoreRows)
        return CGFloat(count) * queueRowFootprint + 32
    }

    private var playlistListHeight: CGFloat {
        let controls = (playlistWindowLowerBound > 0 ? 1 : 0)
            + (playlistWindowUpperBound < player.queue.items.count || player.canLoadMorePlaylistItems ? 1 : 0)
        return CGFloat(max(1, displayedPlaylistIndices.count + controls)) * queueRowFootprint + 32
    }

    private var playlistWindowLowerBound: Int {
        let anchor = playlistWindowAnchor ?? player.queue.currentIndex
        return min(player.queue.items.count, max(0, anchor - playlistItemsBefore))
    }

    private var playlistWindowUpperBound: Int {
        max(
            playlistWindowLowerBound,
            min(player.queue.items.count, (playlistWindowAnchor ?? player.queue.currentIndex) + playlistItemsAfter + 1)
        )
    }

    private var displayedPlaylistIndices: Range<Int> {
        playlistWindowLowerBound..<playlistWindowUpperBound
    }

    private var allUpNextVideos: [Video] {
        player.activePlaylist == nil
            ? player.queue.items.filter { $0.id != player.currentVideo?.id }
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
            // List may build a row after a tap has replaced the playlist queue with a single
            // feed video. Capture the videos and indices together so a deferred row never
            // indexes into the *new* queue using an index from the old playlist.
            let playlistItems = player.queue.items
            let lowerBound = playlistWindowLowerBound
            let upperBound = playlistWindowUpperBound
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
                                    .frame(height: queueRowHeight)
                            }
                            .buttonStyle(ResponsiveButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        ForEach(lowerBound..<upperBound, id: \.self) { index in
                            queueRow(playlistItems[index], preservesPlaylistContext: true)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .frame(height: queueRowHeight)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                        if playlistWindowUpperBound < player.queue.items.count {
                            Button {
                                playlistItemsAfter += 20
                            } label: {
                                Label("Load 20 next", systemImage: "chevron.down")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: queueRowHeight)
                            }
                            .buttonStyle(ResponsiveButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else if player.canLoadMorePlaylistItems {
                            loadMoreQueueButton(isLoading: player.isLoadingMorePlaylistVideos) {
                                let previousCount = player.queue.items.count
                                await player.loadMorePlaylistItems()
                                if player.queue.items.count > previousCount {
                                    playlistItemsAfter += 20
                                }
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
                            .frame(height: queueRowHeight)
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
                            .frame(height: queueRowHeight)
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
            // Playlist switches should not close the lower panel and shift the entire details
            // view while the video changes. A standalone selection still starts with a clean Up Next.
            if player.activePlaylist == nil {
                isQueueExpanded = false
                upNextVisibleLimit = upNextInitialCount
            }
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
                    isExpanded: isExpanded.wrappedValue,
                    showsDisclosureIndicator: false
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
            Button {
                withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel(isExpanded.wrappedValue ? "Collapse playlist" : "Expand playlist")
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
            .frame(height: queueRowHeight)
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
        onPlay: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil,
        showsRemoveButton: Bool = false
    ) -> some View {
        let removalAction: (() -> Void)? = if let onRemove {
            onRemove
        } else if !preservesPlaylistContext {
            { player.removeFromUpNext(videoID: video.id) }
        } else {
            nil
        }

        return DeArrowVideoContent(video: video) { branding in
            HStack(spacing: 0) {
                Group {
                    Button {
                        if let onPlay {
                            onPlay()
                        } else {
                            player.load(video, skipRecommendations: preservesPlaylistContext)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VideoThumbnail(
                                video: video,
                                size: CGSize(width: 80, height: 45),
                                cornerRadius: 4,
                                replacementData: branding.thumbnailData(for: video),
                                replacementCacheKey: branding.thumbnailCacheKey(for: video),
                                compactBadge: true
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(branding.title(for: video))
                                    .contentTransition(.opacity)
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
                        .frame(maxWidth: .infinity, minHeight: queueRowHeight, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                }

                if showsRemoveButton, let removalAction {
                    Button(action: removalAction) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .accessibilityLabel("Remove from queue")
                }

                VStack(spacing: 0) {
                    DeArrowToggleButton(video: video, model: branding)
                    VideoMoreActionsMenu(
                        video: video,
                        offersPlayNext: !preservesPlaylistContext,
                        onRemoveFromUpNext: showsRemoveButton ? nil : removalAction
                    )
                }
            }
            .background {
                if preservesPlaylistContext, video.id == player.currentVideo?.id {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                }
            }
            .animation(reduceMotion ? nil : InterfaceMotion.quick, value: player.currentVideo?.id)
        }
    }

    private func queueRowMetadata(for video: Video) -> String {
        [video.channelName, video.viewCountString]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

}
