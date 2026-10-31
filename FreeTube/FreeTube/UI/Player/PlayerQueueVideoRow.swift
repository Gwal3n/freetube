import SwiftUI

import Kingfisher

/// A single manual-queue or Up Next row. Section disclosure, pagination, and ordering stay in
/// `PlayerQueueSections`; this view owns only the row's tap targets and presentation.
@available(iOS 17.0, *)
struct PlayerQueueVideoRow: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showUpNextChannelAvatars") private var showUpNextChannelAvatars = false
    @AppStorage("openUpNextChannelsOnTap") private var openUpNextChannelsOnTap = false

    let video: Video
    let kind: PlayerQueueSections.Kind
    let upNextSize: UpNextRowSize
    let contentWidth: CGFloat
    let rowHeight: CGFloat
    let onOpenChannel: (String) -> Void
    let onPlay: (() -> Void)?
    let onRemove: (() -> Void)?
    let showsRemoveButton: Bool

    init(
        video: Video,
        kind: PlayerQueueSections.Kind,
        upNextSize: UpNextRowSize,
        contentWidth: CGFloat,
        rowHeight: CGFloat,
        onOpenChannel: @escaping (String) -> Void,
        onPlay: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil,
        showsRemoveButton: Bool = false
    ) {
        self.video = video
        self.kind = kind
        self.upNextSize = upNextSize
        self.contentWidth = contentWidth
        self.rowHeight = rowHeight
        self.onOpenChannel = onOpenChannel
        self.onPlay = onPlay
        self.onRemove = onRemove
        self.showsRemoveButton = showsRemoveButton
    }

    private var rowThumbnailSize: CGSize {
        if kind == .upNext && upNextSize == .small {
            return dynamicTypeSize.isAccessibilitySize
                ? CGSize(width: 104, height: 58.5)
                : CGSize(width: 144, height: 81)
        }
        return CGSize(width: 80, height: 45)
    }

    private var removalAction: () -> Void {
        onRemove ?? { player.removeFromUpNext(videoID: video.id) }
    }

    var body: some View {
        DeArrowVideoContent(video: video) { branding in
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
        return HStack(spacing: 0) {
            if canOpenUpNextChannel(for: video) {
                linkedHorizontalContent(
                    video, branding: branding, thumbnailSize: thumbnailSize,
                    rowHeight: rowHeight, onPlay: onPlay
                )
            } else {
                Button {
                    playQueueVideo(video, onPlay: onPlay)
                } label: {
                    HStack(spacing: 12) {
                        compactThumbnail(video, branding: branding, size: thumbnailSize)
                        VStack(alignment: .leading, spacing: 2) {
                            queueTitle(video, branding: branding)
                            passiveQueueMetadata(for: video)
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
            }

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

    private func linkedHorizontalContent(
        _ video: Video,
        branding: DeArrowVideoViewModel,
        thumbnailSize: CGSize,
        rowHeight: CGFloat,
        onPlay: (() -> Void)?
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                playQueueVideo(video, onPlay: onPlay)
            } label: {
                compactThumbnail(video, branding: branding, size: thumbnailSize)
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel("Play \(branding.title(for: video))")

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    playQueueVideo(video, onPlay: onPlay)
                } label: {
                    queueTitle(video, branding: branding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel("Play \(branding.title(for: video))")
                linkedChannelMetadata(for: video)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if video.id == player.currentVideo?.id {
                NowPlayingIndicator(videoID: video.id)
            }
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
    }

    private func compactThumbnail(
        _ video: Video, branding: DeArrowVideoViewModel, size: CGSize
    ) -> some View {
        VideoThumbnail(
            video: video,
            size: size,
            cornerRadius: 4,
            replacementData: branding.thumbnailData(for: video),
            replacementCacheKey: branding.thumbnailCacheKey(for: video),
            compactBadge: size.width == 80
        )
    }

    private func queueTitle(_ video: Video, branding: DeArrowVideoViewModel) -> some View {
        Text(branding.title(for: video))
            .contentTransition(.opacity)
            .appFont(.subheadline)
            .lineLimit(2)
    }

    private func playQueueVideo(_ video: Video, onPlay: (() -> Void)?) {
        if let onPlay { onPlay() } else { player.load(video) }
    }

    private func canOpenUpNextChannel(for video: Video) -> Bool {
        kind == .upNext && openUpNextChannelsOnTap && !video.channelID.isEmpty
    }

    private func channelAvatar(for video: Video) -> some View {
        KFImage(video.channelThumbnailURL)
            .thumbnail(size: CGSize(width: 18, height: 18)) {
                Circle().fill(MediaStyle.placeholderFill)
            }
            .resizable()
            .scaledToFill()
            .frame(width: 18, height: 18)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private func passiveQueueMetadata(for video: Video) -> some View {
        HStack(spacing: 5) {
            if kind == .upNext && showUpNextChannelAvatars {
                channelAvatar(for: video)
            }
            Text(queueRowMetadata(for: video))
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func linkedChannelMetadata(for video: Video) -> some View {
        HStack(spacing: 0) {
            Button {
                onOpenChannel(video.channelID)
            } label: {
                HStack(spacing: 5) {
                    if showUpNextChannelAvatars {
                        channelAvatar(for: video)
                    }
                    Text(video.channelName)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minHeight: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel("Open \(video.channelName)")

            if !video.viewCountString.isEmpty {
                Text(verbatim: " • \(video.viewCountString)")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                if canOpenUpNextChannel(for: video) {
                    VStack(alignment: .leading, spacing: 2) {
                        Button { player.load(video) } label: {
                            largeQueueTitle(video, branding: branding)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ResponsiveButtonStyle())
                        linkedChannelMetadata(for: video)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button { player.load(video) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            largeQueueTitle(video, branding: branding)
                            passiveQueueMetadata(for: video)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                }
                VideoMoreActionsMenu(video: video, offersPlayNext: true, onRemoveFromUpNext: onRemove)
            }
        }
        .frame(height: rowHeight, alignment: .top)
    }

    private func largeQueueTitle(_ video: Video, branding: DeArrowVideoViewModel) -> some View {
        Text(branding.title(for: video))
            .contentTransition(.opacity)
            .appFont(.subheadline, weight: .semibold)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
    }

    private func queueRowMetadata(for video: Video) -> String {
        [video.channelName, video.viewCountString]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}
