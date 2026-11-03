import SwiftUI
import Kingfisher

/// Vertical "feed" video card — used in Home, Subscriptions, Channel videos.
///
/// Set `showsMoreMenu: true` to render the trailing ellipsis Menu (open in browser, copy URL,
/// add to playlist, downloads) on the metadata row. The Menu sits as a sibling of
/// the card's main tap target so its taps don't trigger `onTap`.
@available(iOS 17.0, *)
struct VideoCard: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var launchAnchor = VideoLaunchAnchor()
    @State private var branding = DeArrowVideoViewModel()

    let video: Video
    var onTap: () -> Void = {}
    var showsMoreMenu: Bool = false
    var offersPlayNext = false
    var showsChannelAvatar = true
    var onTapChannel: (() -> Void)? = nil
    var playbackProgress: Double? = nil
    var watchStatus: WatchHistoryStatus? = nil
    var isNewSinceLastVisit = false
    var isSuggested = false
    var relativeDateReference: Date? = nil

    /// Channel name plus the playback count and relative upload date. Joined by middle dots so
    /// the line reads naturally and any missing segment is dropped without leaving stray
    /// separators ("Channel" / "Channel • 1.2M views" / "Channel • 1.2M views • 3 days ago").
    private var metadataLine: String {
        VideoMetadataLine.withChannel(for: video, relativeTo: relativeDateReference)
    }

    private var metadataDetails: String {
        VideoMetadataLine.details(for: video, relativeTo: relativeDateReference)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MediaStyle.cardContentSpacing) {
            ZStack(alignment: .topTrailing) {
                Button(action: openVideo) {
                    thumbnail(branding: branding)
                }
                .buttonStyle(ResponsiveButtonStyle())
                // The metadata control below performs the same action and carries the complete
                // spoken label. Exposing both would make VoiceOver announce every card twice.
                .accessibilityHidden(true)

                if branding.hasReplacement(for: video) {
                    DeArrowToggleButton(video: video, model: branding, onThumbnail: true)
                }
            }

            // Metadata and its ellipsis remain siblings of the thumbnail's tap target.
            metadataRow(branding: branding)
        }
        // Include spacing in the List row that the native menu lifts and returns to.
        .padding(.top, MediaStyle.cardTopPadding)
        .padding(.bottom, MediaStyle.cardBottomPadding)
        .loadDeArrowBranding(video: video, model: branding)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if offersPlayNext {
                Button {
                    player.enqueue(video)
                } label: {
                    Label("Add to queue", systemImage: "text.badge.plus")
                }
                .tint(.indigo)
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .videoContextMenu(video: video, previewBranding: branding, offersPlayNext: offersPlayNext)
    }

    private func thumbnail(branding: DeArrowVideoViewModel) -> some View {
        GeometryReader { proxy in
            VideoThumbnail(
                video: video,
                size: CGSize(width: proxy.size.width, height: proxy.size.width * 9 / 16),
                progress: playbackProgress,
                watchStatus: watchStatus,
                replacementData: branding.thumbnailData(for: video),
                replacementCacheKey: branding.thumbnailCacheKey(for: video)
            )
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            launchAnchor.frame = frame
        }
    }

    private func metadataRow(branding: DeArrowVideoViewModel) -> some View {
        HStack(alignment: .top, spacing: MediaStyle.spacing) {
            if let onTapChannel {
                linkedMetadataContent(branding: branding, onTapChannel: onTapChannel)
            } else {
                Button(action: openVideo) {
                    playbackMetadataContent(branding: branding)
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel(cardAccessibilityLabel(title: branding.title(for: video)))
                .accessibilityHint("Plays video")
            }

            if showsMoreMenu {
                VideoMoreActionsMenu(video: video, offersPlayNext: offersPlayNext)
            }
        }
        .padding(.horizontal, MediaStyle.cardHorizontalPadding)
    }

    private func channelAvatar() -> some View {
        KFImage(video.channelThumbnailURL)
            .thumbnail(size: CGSize(width: MediaStyle.cardAvatarSize, height: MediaStyle.cardAvatarSize)) {
                Circle().fill(MediaStyle.placeholderFill)
            }
            .resizable()
            .scaledToFill()
            .frame(width: MediaStyle.cardAvatarSize, height: MediaStyle.cardAvatarSize)
            .clipShape(Circle())
    }

    private func playbackMetadataContent(branding: DeArrowVideoViewModel) -> some View {
        HStack(alignment: .top, spacing: MediaStyle.spacing) {
            if showsChannelAvatar {
                channelAvatar()
            }
            VStack(alignment: .leading, spacing: MediaStyle.labelSpacing) {
                title(branding: branding)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        newUploadLabel
                        metadataText
                    }
                } else {
                    HStack(spacing: 6) {
                        newUploadLabel
                        metadataText
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func linkedMetadataContent(
        branding: DeArrowVideoViewModel, onTapChannel: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: MediaStyle.spacing) {
            if showsChannelAvatar {
                Button(action: onTapChannel) {
                    channelAvatar()
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(video.channelName)")
            }
            VStack(alignment: .leading, spacing: MediaStyle.labelSpacing) {
                Button(action: openVideo) {
                    title(branding: branding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel(cardAccessibilityLabel(title: branding.title(for: video)))
                .accessibilityHint("Plays video")
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        linkedMetadataItems(onTapChannel: onTapChannel)
                    }
                } else {
                    HStack(spacing: 6) {
                        linkedMetadataItems(onTapChannel: onTapChannel)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var metadataText: some View {
        Text(metadataLine)
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
    }

    @ViewBuilder
    private func linkedMetadataItems(onTapChannel: @escaping () -> Void) -> some View {
        newUploadLabel
        Button(action: onTapChannel) {
            Text(video.channelName)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(video.channelName)")
        if !metadataDetails.isEmpty {
            Button(action: openVideo) {
                Text(verbatim: dynamicTypeSize.isAccessibilitySize
                     ? metadataDetails : " • \(metadataDetails)")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityHidden(true)
        }
    }

    private func title(branding: DeArrowVideoViewModel) -> some View {
        Text(branding.title(for: video))
            .contentTransition(.opacity)
            .appFont(.subheadline, weight: .semibold)
            .lineLimit(MediaStyle.mediaTitleLineLimit(for: dynamicTypeSize))
    }

    @ViewBuilder
    private var newUploadLabel: some View {
        if isSuggested {
            Text("Suggested")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityHidden(true)
        } else if isNewSinceLastVisit {
            Text("New")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.primary)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    private func cardAccessibilityLabel(title: String) -> String {
        [isSuggested ? String(localized: "Suggested") : "",
         isNewSinceLastVisit ? String(localized: "New since last visit") : "",
         title, metadataLine, video.durationString]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func openVideo() {
        player.prepareLaunch(for: video.id, from: launchAnchor.frame)
        onTap()
    }
}
