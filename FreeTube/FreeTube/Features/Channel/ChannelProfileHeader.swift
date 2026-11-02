import SwiftUI

import Kingfisher

/// Channel artwork, identity, and the local subscription action.
@available(iOS 17.0, *)
struct ChannelProfileHeader: View {
    let channel: Channel
    let statsText: String
    let headerOffset: CGFloat
    let onToggleSubscribe: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ChannelProfileBanner(
                channel: channel,
                headerOffset: headerOffset,
                height: ChannelProfileMetrics.bannerHeight
            )

            HStack(alignment: .center, spacing: ChannelProfileMetrics.headerRowSpacing) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .appFont(.title3, weight: .bold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let handle = channel.handle, !handle.isEmpty {
                        Text(handle)
                            .appFont(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .lineLimit(1)
                    }

                    if !statsText.isEmpty {
                        Text(statsText)
                            .appFont(.footnote)
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)

                subscribeButton
            }
            .padding(.horizontal, ChannelProfileMetrics.headerRowInset)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(MediaStyle.placeholderFill)
            Text(channel.name.prefix(1).uppercased())
                .font(.title.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.7))
            KFImage(channel.thumbnailURL)
                .thumbnail(size: CGSize(
                    width: ChannelProfileMetrics.avatarSize,
                    height: ChannelProfileMetrics.avatarSize
                )) {
                    Color.clear
                }
                .resizable()
                .scaledToFill()
                .frame(
                    width: ChannelProfileMetrics.avatarSize,
                    height: ChannelProfileMetrics.avatarSize
                )
        }
        .frame(width: ChannelProfileMetrics.avatarSize, height: ChannelProfileMetrics.avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private var subscribeButton: some View {
        Button(action: onToggleSubscribe) {
            Group {
                if channel.isSubscribed {
                    Text("Subscribed")
                } else {
                    Text("Subscribe")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(channel.isSubscribed
                ? Color.primary
                : (colorScheme == .dark ? Color.black : Color.white))
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, channel.isSubscribed ? 12 : 18)
            .frame(height: 34)
            .background(
                channel.isSubscribed
                    ? AnyShapeStyle(Color.primary.opacity(0.12))
                    : AnyShapeStyle(colorScheme == .dark ? Color.white : Color.black),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(ResponsiveButtonStyle())
        .animation(reduceMotion ? nil : InterfaceMotion.quick, value: channel.isSubscribed)
    }
}
