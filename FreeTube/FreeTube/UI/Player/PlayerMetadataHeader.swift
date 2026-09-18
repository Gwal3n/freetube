import SwiftUI

import Kingfisher

/// The presentation-only header shown beneath the player surface.
///
/// State ownership and side effects deliberately remain in `FullScreenPlayer`; this view only
/// gives the title, statistics, channel, and action row one consistent layout.
@available(iOS 17.0, *)
struct PlayerMetadataHeader<Actions: View>: View {
    let video: Video
    let statsText: String
    let isDetailsExpanded: Bool
    let canOpenChannel: Bool
    let onToggleDetails: () -> Void
    let onOpenChannel: () -> Void
    let actions: Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        video: Video,
        statsText: String,
        isDetailsExpanded: Bool,
        canOpenChannel: Bool,
        onToggleDetails: @escaping () -> Void,
        onOpenChannel: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.video = video
        self.statsText = statsText
        self.isDetailsExpanded = isDetailsExpanded
        self.canOpenChannel = canOpenChannel
        self.onToggleDetails = onToggleDetails
        self.onOpenChannel = onOpenChannel
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggleDetails) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(video.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isDetailsExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel(video.title)
            .accessibilityValue(isDetailsExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides video details")

            if video.isLive || !statsText.isEmpty {
                HStack(spacing: 7) {
                    if video.isLive {
                        Text("LIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red, in: RoundedRectangle(cornerRadius: 3))
                    }
                    if !statsText.isEmpty {
                        Text(statsText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    channelControl
                    Spacer(minLength: 4)
                    actions
                }
                VStack(alignment: .leading, spacing: 4) {
                    channelControl
                    actions
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var channelControl: some View {
        if canOpenChannel {
            Button(action: onOpenChannel) {
                channelRow
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel("Open channel, \(video.channelName)")
        } else {
            channelRow
        }
    }

    private var channelRow: some View {
        HStack(spacing: 12) {
            KFImage(video.channelThumbnailURL)
                .thumbnail(size: CGSize(width: 32, height: 32)) {
                    Circle().fill(MediaStyle.placeholderFill)
                }
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())

            Text(video.channelName)
                .font(.subheadline.weight(.medium))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
        .frame(minHeight: 44)
    }
}
