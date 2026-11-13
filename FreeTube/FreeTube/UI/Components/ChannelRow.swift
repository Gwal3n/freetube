import SwiftUI
import Kingfisher

@available(iOS 17.0, *)
struct ChannelRow: View {
    let channel: Channel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Leave nil inside NavigationLink — an inner Button swallows the link tap.
    var onTap: (() -> Void)? = nil
    var trailing: AnyView? = nil

    private var detailLine: String {
        var parts: [String] = []
        if let handle = channel.handle, !handle.isEmpty { parts.append(handle) }
        if let subs = channel.subscriberCount {
            parts.append("\(Self.formattedCount(subs)) subscribers")
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { content }
                    .buttonStyle(ResponsiveButtonStyle())
            } else {
                content
            }
        }
        .mediaListRow()
        .channelContextMenu(channel: channel)
    }

    private var content: some View {
        HStack(spacing: MediaStyle.spacing) {
            KFImage(channel.thumbnailURL)
                .thumbnail(size: CGSize(width: 48, height: 48)) {
                    Circle().fill(MediaStyle.placeholderFill)
                }
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: MediaStyle.labelSpacing) {
                Text(channel.name).appFont(.subheadline, weight: .semibold)
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
            }
            Spacer()
            trailing
        }
        .contentShape(Rectangle())
    }

    /// Compact "1.2M" / "856K" / "12,345" formatter for subscriber counts. Static so SwiftUI's
    /// view recompute doesn't allocate a fresh formatter each call.
    private static func formattedCount(_ value: Int) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}
