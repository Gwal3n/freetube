import SwiftUI
import Kingfisher

/// Horizontal compact video row — used in search results, history, library lists.
@available(iOS 17.0, *)
struct VideoRow: View {
    enum Accessory {
        case none
        case actions(offersPlayNext: Bool)
        case reserved
    }

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var launchAnchor = VideoLaunchAnchor()
    @State private var branding = DeArrowVideoViewModel()
    let video: Video
    var accessory: Accessory
    var showsChannelAvatar: Bool
    var playbackProgress: Double?
    var watchStatus: WatchHistoryStatus?
    var isNewSinceLastVisit = false
    var isSuggested = false
    var relativeDateReference: Date?
    var onOpenChannel: (() -> Void)?
    var channelLinkID: String?
    var onTapChannel: (() -> Void)?
    var onTap: () -> Void

    /// Keep the action closure last so existing SwiftUI call sites can continue to use trailing-
    /// closure syntax as optional row capabilities are added.
    init(
        video: Video,
        accessory: Accessory = .none,
        showsChannelAvatar: Bool = false,
        playbackProgress: Double? = nil,
        watchStatus: WatchHistoryStatus? = nil,
        isNewSinceLastVisit: Bool = false,
        isSuggested: Bool = false,
        relativeDateReference: Date? = nil,
        onOpenChannel: (() -> Void)? = nil,
        channelLinkID: String? = nil,
        onTapChannel: (() -> Void)? = nil,
        onTap: @escaping () -> Void = {}
    ) {
        self.video = video
        self.accessory = accessory
        self.showsChannelAvatar = showsChannelAvatar
        self.playbackProgress = playbackProgress
        self.watchStatus = watchStatus
        self.isNewSinceLastVisit = isNewSinceLastVisit
        self.isSuggested = isSuggested
        self.relativeDateReference = relativeDateReference
        self.onOpenChannel = onOpenChannel
        self.channelLinkID = channelLinkID
        self.onTapChannel = onTapChannel
        self.onTap = onTap
    }

    /// Playback count + relative upload date joined by a middle dot. Either half can be empty
    /// (older listings sometimes omit one), so we filter before joining to avoid stray separators.
    private var statsLine: String {
        VideoMetadataLine.details(for: video, relativeTo: relativeDateReference)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let onTapChannel {
                    linkedContent(branding: branding, channelID: nil, onTapChannel: onTapChannel)
                } else if let channelLinkID, !channelLinkID.isEmpty {
                    linkedContent(branding: branding, channelID: channelLinkID, onTapChannel: nil)
                } else {
                    Button(action: openVideo) {
                        content(branding: branding)
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .accessibilityLabel(rowAccessibilityLabel(title: branding.title(for: video)))
                    .accessibilityHint("Plays video")
                }
            }

            switch accessory {
            case .none:
                EmptyView()
            case .actions(let offersPlayNext):
                VideoMoreActionsMenu(video: video, offersPlayNext: offersPlayNext, onOpenChannel: onOpenChannel)
            case .reserved:
                Color.clear
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsThumbnailToggle && branding.hasReplacement(for: video) {
                DeArrowToggleButton(video: video, model: branding, onThumbnail: true)
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height, alignment: .topTrailing)
            }
        }
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
        .loadDeArrowBranding(video: video, model: branding)
        // The menu must be on the outer List row, not a nested branding view that can lag behind
        // the scrolling cell while iOS animates its lifted preview back into place.
        .mediaListRow()
        .videoContextMenu(video: video, previewBranding: branding, offersPlayNext: true,
                          onOpenChannel: onOpenChannel)
    }

    private var offersPlayNext: Bool {
        guard case .actions(let offersPlayNext) = accessory else { return false }
        return offersPlayNext
    }

    private var showsThumbnailToggle: Bool {
        if case .reserved = accessory { return false }
        return true
    }

    private var thumbnailSize: CGSize {
        MediaStyle.compactVideoThumbnailSize(for: dynamicTypeSize)
    }

    private func rowAccessibilityLabel(title: String) -> String {
        [isSuggested ? String(localized: "Suggested") : "",
         isNewSinceLastVisit ? String(localized: "New since last visit") : "",
         title, video.channelName, statsLine, video.durationString]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func openVideo() {
        player.prepareLaunch(for: video.id, from: launchAnchor.frame)
        onTap()
    }

    private func content(branding: DeArrowVideoViewModel) -> some View {
        HStack(alignment: .top, spacing: MediaStyle.spacing) {
            thumbnail(branding: branding)

            VStack(alignment: .leading, spacing: 4) {
                title(branding: branding)
                channelLine
                secondaryLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Give channel identity its own tap target without nesting it inside the playback button.
    private func linkedContent(
        branding: DeArrowVideoViewModel, channelID: String?, onTapChannel: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: MediaStyle.spacing) {
            Button(action: openVideo) { thumbnail(branding: branding) }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Button(action: openVideo) {
                    title(branding: branding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel(rowAccessibilityLabel(title: branding.title(for: video)))
                .accessibilityHint("Plays video")

                // Only the avatar opens the channel; the name belongs to the playback target.
                HStack(spacing: 5) {
                    if showsChannelAvatar {
                        if let onTapChannel {
                            Button(action: onTapChannel) {
                                channelAvatar.contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(video.channelName)")
                        } else if let channelID {
                            NavigationLink {
                                ChannelScreen(channelID: channelID)
                            } label: {
                                channelAvatar.contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(video.channelName)")
                        }
                    }
                    Button(action: openVideo) {
                        channelName
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .accessibilityHidden(true)
                }

                if !statsLine.isEmpty || isNewSinceLastVisit || isSuggested {
                    Button(action: openVideo) {
                        secondaryLine
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thumbnail(branding: DeArrowVideoViewModel) -> some View {
        VideoThumbnail(
            video: video,
            size: thumbnailSize,
            progress: playbackProgress,
            watchStatus: watchStatus,
            replacementData: branding.thumbnailData(for: video),
            replacementCacheKey: branding.thumbnailCacheKey(for: video)
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            launchAnchor.frame = frame
        }
    }

    private func title(branding: DeArrowVideoViewModel) -> some View {
        Text(branding.title(for: video))
            .contentTransition(.opacity)
            .appFont(.subheadline, weight: .semibold)
            .lineLimit(MediaStyle.mediaTitleLineLimit(for: dynamicTypeSize))
    }

    private var channelLine: some View {
        HStack(spacing: 5) {
            if showsChannelAvatar {
                channelAvatar
            }
            channelName
        }
    }

    private var channelAvatar: some View {
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

    private var channelName: some View {
        Text(video.channelName)
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if !statsLine.isEmpty {
            HStack(spacing: 6) {
                if isSuggested {
                    Text("Suggested")
                        .appFont(.caption2, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityHidden(true)
                } else if isNewSinceLastVisit {
                    Text("New")
                        .appFont(.caption2, weight: .semibold)
                        .foregroundStyle(.primary)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                Text(statsLine)
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        } else if isSuggested {
            Text("Suggested")
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else if isNewSinceLastVisit {
            Text("New")
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
        }
    }
}
