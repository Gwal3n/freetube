import SwiftUI

/// Presentation-only composition for the content below the player viewport.
///
/// `FullScreenPlayer` continues to own loading, navigation, download, and playback side effects.
/// Keeping those decisions in the parent makes this component predictable while preventing the
/// player orchestrator from also owning the lower panel's visual hierarchy.
@available(iOS 17.0, *)
struct PlayerInformationPanel<Actions: View>: View {
    let video: Video
    let statsText: String
    let descriptionText: String?
    let descriptionParts: [VideoDescriptionPart]
    let likesText: String?
    let commentsCountText: String?
    let isDetailsExpanded: Bool
    let isLoadingDetails: Bool
    let detailsLoadFailed: Bool
    let showsUpNext: Bool
    let upNextInitialCount: Int
    let showsComments: Bool
    let onToggleDetails: () -> Void
    let onExpandDetails: () -> Void
    let onRetryDetails: () -> Void
    let onOpenChannel: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onOpenPlaylist: (String) -> Void
    let actions: Actions

    init(
        video: Video,
        statsText: String,
        descriptionText: String?,
        descriptionParts: [VideoDescriptionPart],
        likesText: String?,
        commentsCountText: String?,
        isDetailsExpanded: Bool,
        isLoadingDetails: Bool,
        detailsLoadFailed: Bool,
        showsUpNext: Bool,
        upNextInitialCount: Int,
        showsComments: Bool,
        onToggleDetails: @escaping () -> Void,
        onExpandDetails: @escaping () -> Void,
        onRetryDetails: @escaping () -> Void,
        onOpenChannel: @escaping () -> Void,
        onSeek: @escaping (TimeInterval) -> Void,
        onOpenPlaylist: @escaping (String) -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.video = video
        self.statsText = statsText
        self.descriptionText = descriptionText
        self.descriptionParts = descriptionParts
        self.likesText = likesText
        self.commentsCountText = commentsCountText
        self.isDetailsExpanded = isDetailsExpanded
        self.isLoadingDetails = isLoadingDetails
        self.detailsLoadFailed = detailsLoadFailed
        self.showsUpNext = showsUpNext
        self.upNextInitialCount = upNextInitialCount
        self.showsComments = showsComments
        self.onToggleDetails = onToggleDetails
        self.onExpandDetails = onExpandDetails
        self.onRetryDetails = onRetryDetails
        self.onOpenChannel = onOpenChannel
        self.onSeek = onSeek
        self.onOpenPlaylist = onOpenPlaylist
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlayerMetadataHeader(
                video: video,
                statsText: statsText,
                isDetailsExpanded: isDetailsExpanded,
                canOpenChannel: !video.channelID.isEmpty,
                onToggleDetails: onToggleDetails,
                onOpenChannel: onOpenChannel
            ) {
                actions
            }

            PlayerDescription(
                text: descriptionText,
                parts: descriptionParts,
                likesText: likesText,
                isExpanded: isDetailsExpanded,
                isLoading: isLoadingDetails,
                loadFailed: detailsLoadFailed,
                onSeek: onSeek,
                onRetry: onRetryDetails,
                onExpand: onExpandDetails
            )

            VStack(alignment: .leading, spacing: 0) {
                PlayerQueueSections(
                    showsUpNext: showsUpNext,
                    upNextInitialCount: upNextInitialCount,
                    onOpenPlaylist: onOpenPlaylist
                )

                if showsComments {
                    CommentsSection(videoID: video.id, countText: commentsCountText)
                        .id(video.id)
                }
            }
        }
    }
}
