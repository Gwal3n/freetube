import SwiftUI

/// Manual queue and recommendations shown below the expanded player's metadata.
///
/// This view owns only disclosure/windowing state. Playback and queue mutations remain in the
/// shared `PlayerStateManager`, while navigation out of the player remains with its parent.
@available(iOS 17.0, *)
struct PlayerQueueSections: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let showsUpNext: Bool
    let upNextInitialCount: Int

    @State private var isQueueExpanded = false
    @State private var isManualQueueExpanded = true
    @State private var upNextVisibleLimit = 5

    @AppStorage("com.leshko.freetube.deArrowTitles") private var replacesTitles = false
    @AppStorage("com.leshko.freetube.deArrowThumbnails") private var replacesThumbnails = false

    // Reserve the trailing action column before branding arrives, so loading it never moves
    // neighboring rows or makes the fixed-height queue List clip its controls.
    private var queueRowHeight: CGFloat { replacesTitles || replacesThumbnails ? 76 : 56 }
    private var queueRowFootprint: CGFloat { queueRowHeight + 8 }

    @ViewBuilder
    var body: some View {
        if !player.manualQueue.isEmpty || showsUpNext {
            VStack(alignment: .leading, spacing: 8) {
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

    private func queueRow(
        _ video: Video,
        onPlay: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil,
        showsRemoveButton: Bool = false
    ) -> some View {
        let removalAction: () -> Void = onRemove ?? { player.removeFromUpNext(videoID: video.id) }

        return DeArrowVideoContent(video: video) { branding in
            HStack(spacing: 0) {
                Group {
                    Button {
                        if let onPlay {
                            onPlay()
                        } else {
                            player.load(video)
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
                                    .lineLimit(2)
                                Text(queueRowMetadata(for: video))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if video.id == player.currentVideo?.id {
                                NowPlayingIndicator(videoID: video.id)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: queueRowHeight, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                }

                if showsRemoveButton {
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
                        offersPlayNext: true,
                        onRemoveFromUpNext: showsRemoveButton ? nil : removalAction
                    )
                }
            }
        }
    }

    private func queueRowMetadata(for video: Video) -> String {
        [video.channelName, video.viewCountString]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

}
