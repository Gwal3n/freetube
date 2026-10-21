import SwiftUI

/// Manual queue and recommendations shown below the expanded player's metadata.
///
/// This view owns only disclosure/windowing state. Playback and queue mutations remain in the
/// shared `PlayerStateManager`, while navigation out of the player remains with its parent.
@available(iOS 17.0, *)
struct PlayerQueueSections: View {
    enum Kind: Equatable {
        case manualQueue
        case upNext
    }

    @Environment(PlayerStateManager.self) private var player
    @State private var blocklist = VideoBlocklist.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("upNextRowSize") private var upNextRowSizeRaw = UpNextRowSize.compact.rawValue

    let kind: Kind
    let upNextInitialCount: Int
    let contentWidth: CGFloat

    @State private var isQueueExpanded = false
    @State private var isManualQueueExpanded = true
    @State private var upNextVisibleLimit = 5
    @State private var queueToSave: [Video] = []
    @State private var showingSaveQueue = false

    // The DeArrow switch overlays the thumbnail, so it never changes row height as branding loads.
    private let queueRowHeight: CGFloat = 56
    private var queueRowFootprint: CGFloat { queueRowHeight + 8 }
    private var upNextSize: UpNextRowSize { UpNextRowSize(rawValue: upNextRowSizeRaw) ?? .compact }

    private var upNextRowHeight: CGFloat {
        switch upNextSize {
        case .compact: queueRowHeight
        case .small: dynamicTypeSize.isAccessibilitySize ? 120 : 89
        case .large: max(0, contentWidth - 32) * 9 / 16 + (dynamicTypeSize.isAccessibilitySize ? 128 : 68)
        }
    }

    private var rowThumbnailSize: CGSize {
        if kind == .upNext && upNextSize == .small {
            return dynamicTypeSize.isAccessibilitySize
                ? CGSize(width: 104, height: 58.5)
                : CGSize(width: 144, height: 81)
        }
        return CGSize(width: 80, height: 45)
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch kind {
            case .manualQueue: manualQueuePanel
            case .upNext: queuePanel
            }
        }
        .sheet(isPresented: $showingSaveQueue) {
            AddToPlaylistSheet(queueVideos: queueToSave)
        }
    }

    // MARK: - Manual queue

    @ViewBuilder
    private var manualQueuePanel: some View {
        if !visibleManualQueue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                            isManualQueueExpanded.toggle()
                        }
                    } label: {
                        PlayerSectionHeading(
                            title: "Queue",
                            detail: "\(visibleManualQueue.count)",
                            isExpanded: isManualQueueExpanded,
                            showsDisclosureIndicator: false
                        )
                    }
                    .buttonStyle(ResponsiveButtonStyle())

                    Menu {
                        Button {
                            var seen = Set<String>()
                            queueToSave = ([player.currentVideo].compactMap { $0 } + player.manualQueue)
                                .filter { !blocklist.blocks($0) && seen.insert($0.id).inserted }
                            showingSaveQueue = true
                        } label: {
                            Label("Save queue to playlist", systemImage: "text.badge.plus")
                        }
                        Button(role: .destructive) {
                            player.clearManualQueueWithUndo()
                        } label: {
                            Label("Clear queue", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                            .contentShape(Rectangle())
                    }
                    .tint(.primary)
                    .accessibilityLabel("Queue actions")

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
                        ForEach(visibleManualQueue) { video in
                            queueRow(
                                video,
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
        CGFloat(max(1, visibleManualQueue.count)) * queueRowFootprint + 32
    }

    private var queueListHeight: CGFloat {
        let loadMoreRows = canRevealMoreUpNext ? 1 : 0
        return CGFloat(displayedUpNextVideos.count) * (upNextRowHeight + 8)
            + CGFloat(loadMoreRows) * queueRowFootprint + 32
    }

    private var allUpNextVideos: [Video] {
        let items = player.activePlaylist == nil
            ? player.queue.items.filter { $0.id != player.currentVideo?.id }
            : player.playlistRecommendations
        return items.filter { !blocklist.blocks($0) }
    }

    private var visibleManualQueue: [Video] {
        player.manualQueue.filter { !blocklist.blocks($0) }
    }

    private var displayedUpNextVideos: [Video] {
        Array(allUpNextVideos.prefix(max(1, upNextVisibleLimit)))
    }

    private var canRevealMoreUpNext: Bool {
        upNextVisibleLimit < allUpNextVideos.count || player.canLoadMoreRecommendations
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

            if isQueueExpanded {
                List {
                    ForEach(displayedUpNextVideos) { video in
                        queueRow(video)
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
                            .frame(height: upNextRowHeight)
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
                .transition(.opacity)
            }
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

    private func queueRow(
        _ video: Video,
        onPlay: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil,
        showsRemoveButton: Bool = false
    ) -> some View {
        let removalAction: () -> Void = onRemove ?? { player.removeFromUpNext(videoID: video.id) }

        return DeArrowVideoContent(video: video) { branding in
            Group {
                if kind == .upNext && upNextSize == .large {
                    largeUpNextRow(video, branding: branding, onRemove: removalAction)
                } else {
                    horizontalQueueRow(
                        video,
                        branding: branding,
                        onPlay: onPlay,
                        onRemove: removalAction,
                        showsRemoveButton: showsRemoveButton
                    )
                }
            }
            .videoContextMenu(
                video: video,
                previewBranding: branding,
                offersPlayNext: true,
                onRemoveFromUpNext: showsRemoveButton ? nil : removalAction
            )
        }
    }

    private func horizontalQueueRow(
        _ video: Video,
        branding: DeArrowVideoViewModel,
        onPlay: (() -> Void)?,
        onRemove: @escaping () -> Void,
        showsRemoveButton: Bool
    ) -> some View {
        let thumbnailSize = rowThumbnailSize
        let rowHeight = kind == .upNext ? upNextRowHeight : queueRowHeight
        return HStack(spacing: 0) {
            Button {
                if let onPlay { onPlay() } else { player.load(video) }
            } label: {
                HStack(spacing: 12) {
                    VideoThumbnail(
                        video: video,
                        size: thumbnailSize,
                        cornerRadius: 4,
                        replacementData: branding.thumbnailData(for: video),
                        replacementCacheKey: branding.thumbnailCacheKey(for: video),
                        compactBadge: thumbnailSize.width == 80
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(branding.title(for: video))
                            .contentTransition(.opacity)
                            .appFont(.subheadline)
                            .lineLimit(2)
                        Text(queueRowMetadata(for: video))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if video.id == player.currentVideo?.id {
                        NowPlayingIndicator(videoID: video.id)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())

            if showsRemoveButton {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                        .contentShape(Circle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel("Remove from queue")
            }

            VideoMoreActionsMenu(
                video: video,
                offersPlayNext: true,
                onRemoveFromUpNext: showsRemoveButton ? nil : onRemove
            )
        }
        .overlay(alignment: .topLeading) {
            if branding.hasReplacement(for: video) {
                DeArrowToggleButton(video: video, model: branding, onThumbnail: true)
                    .frame(width: thumbnailSize.width, height: rowHeight, alignment: .topTrailing)
            }
        }
    }

    private func largeUpNextRow(
        _ video: Video,
        branding: DeArrowVideoViewModel,
        onRemove: @escaping () -> Void
    ) -> some View {
        let width = max(0, contentWidth - 32)
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button { player.load(video) } label: {
                    VideoThumbnail(
                        video: video,
                        size: CGSize(width: width, height: width * 9 / 16),
                        replacementData: branding.thumbnailData(for: video),
                        replacementCacheKey: branding.thumbnailCacheKey(for: video)
                    )
                }
                .buttonStyle(ResponsiveButtonStyle())
                if branding.hasReplacement(for: video) {
                    DeArrowToggleButton(video: video, model: branding, onThumbnail: true)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Button { player.load(video) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(branding.title(for: video))
                            .contentTransition(.opacity)
                            .appFont(.subheadline, weight: .semibold)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        Text(queueRowMetadata(for: video))
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                VideoMoreActionsMenu(video: video, offersPlayNext: true, onRemoveFromUpNext: onRemove)
            }
        }
        .frame(height: upNextRowHeight, alignment: .top)
    }

    private func queueRowMetadata(for video: Video) -> String {
        [video.channelName, video.viewCountString]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

}
