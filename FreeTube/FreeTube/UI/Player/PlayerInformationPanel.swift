import SwiftUI

/// Presentation-only composition for the content below the player viewport.
///
/// `FullScreenPlayer` continues to own loading, navigation, download, and playback side effects.
/// Keeping those decisions in the parent makes this component predictable while preventing the
/// player orchestrator from also owning the lower panel's visual hierarchy.
@available(iOS 17.0, *)
struct PlayerInformationPanel<Actions: View>: View {
    @AppStorage("playerPanelSectionOrder") private var storedSectionOrder = PlayerPanelSection.defaultOrder
    let video: Video
    let fullVideoLabel: SponsorBlockCategory?
    let statsText: String
    let descriptionText: String?
    let descriptionParts: [VideoDescriptionPart]
    let commentsCountText: String?
    let isDetailsExpanded: Bool
    let isLoadingDetails: Bool
    let detailsLoadFailed: Bool
    let showsDescription: Bool
    let showsUpNext: Bool
    let upNextInitialCount: Int
    let contentWidth: CGFloat
    let showsComments: Bool
    let onToggleDetails: () -> Void
    let onExpandDetails: () -> Void
    let onRetryDetails: () -> Void
    let onOpenChannel: () -> Void
    let onSeek: (TimeInterval) -> Void
    let actions: Actions

    init(
        video: Video,
        fullVideoLabel: SponsorBlockCategory?,
        statsText: String,
        descriptionText: String?,
        descriptionParts: [VideoDescriptionPart],
        commentsCountText: String?,
        isDetailsExpanded: Bool,
        isLoadingDetails: Bool,
        detailsLoadFailed: Bool,
        showsDescription: Bool,
        showsUpNext: Bool,
        upNextInitialCount: Int,
        contentWidth: CGFloat,
        showsComments: Bool,
        onToggleDetails: @escaping () -> Void,
        onExpandDetails: @escaping () -> Void,
        onRetryDetails: @escaping () -> Void,
        onOpenChannel: @escaping () -> Void,
        onSeek: @escaping (TimeInterval) -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.video = video
        self.fullVideoLabel = fullVideoLabel
        self.statsText = statsText
        self.descriptionText = descriptionText
        self.descriptionParts = descriptionParts
        self.commentsCountText = commentsCountText
        self.isDetailsExpanded = isDetailsExpanded
        self.isLoadingDetails = isLoadingDetails
        self.detailsLoadFailed = detailsLoadFailed
        self.showsDescription = showsDescription
        self.showsUpNext = showsUpNext
        self.upNextInitialCount = upNextInitialCount
        self.contentWidth = contentWidth
        self.showsComments = showsComments
        self.onToggleDetails = onToggleDetails
        self.onExpandDetails = onExpandDetails
        self.onRetryDetails = onRetryDetails
        self.onOpenChannel = onOpenChannel
        self.onSeek = onSeek
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlayerMetadataHeader(
                video: video,
                fullVideoLabel: fullVideoLabel,
                statsText: statsText,
                isDetailsExpanded: isDetailsExpanded,
                showsDescription: showsDescription,
                canOpenChannel: !video.channelID.isEmpty,
                onToggleDetails: onToggleDetails,
                onOpenChannel: onOpenChannel
            ) {
                actions
            }

            if showsDescription {
                PlayerDescription(
                    text: descriptionText,
                    parts: descriptionParts,
                    isExpanded: isDetailsExpanded,
                    isLoading: isLoadingDetails,
                    loadFailed: detailsLoadFailed,
                    onSeek: onSeek,
                    onRetry: onRetryDetails,
                    onExpand: onExpandDetails
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(PlayerPanelSection.ordered(from: storedSectionOrder)) { section in
                    switch section {
                    case .savedMoments:
                        SavedMomentsSection(videoID: video.id, onSeek: onSeek)
                    case .queue:
                        PlayerQueueSections(kind: .manualQueue, upNextInitialCount: upNextInitialCount, contentWidth: contentWidth)
                    case .upNext:
                        if showsUpNext {
                            PlayerQueueSections(kind: .upNext, upNextInitialCount: upNextInitialCount, contentWidth: contentWidth)
                        }
                    case .comments:
                        if showsComments {
                            CommentsSection(videoID: video.id, countText: commentsCountText)
                                .id(video.id)
                        }
                    }
                }
            }
        }
    }
}
