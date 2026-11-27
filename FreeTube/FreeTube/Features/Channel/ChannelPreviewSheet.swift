import SwiftUI
import Kingfisher

/// Compact native bottom sheet with channel identity, stats, about, and local actions.
@available(iOS 17.0, *)
struct ChannelPreviewSheet: View {
    let request: ChannelPreviewRequest

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var metadata = ChannelPreviewMetadataStore.shared
    @State private var subscriptions = LocalSubscriptionStore.shared
    @State private var hiddenAuthors = HiddenCommentAuthorsStore.shared
    @State private var fittedHeight: CGFloat = 188

    private var seed: Channel { request.seedChannel }

    private var details: Channel {
        let enriched = metadata.enriched(seed)
        return enriched.withSubscribed(subscriptions.contains(enriched.id))
    }

    private var aboutText: String {
        details.descriptionText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var pageInfo: ChannelPreviewPageInfo {
        metadata.pageInfo(for: request.id)
    }

    private var commentsHidden: Bool {
        hiddenAuthors.isHidden(channelID: request.id)
    }

    private var fittedDetent: PresentationDetent {
        .height(max(fittedHeight, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            activitySection
            aboutSection
            footerRow
        }
        .padding(.horizontal, 20)
        // Leave room below the grabber so the header isn't flush with the sheet edge.
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChannelPreviewHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(ChannelPreviewHeightKey.self) { height in
            guard height > 1, abs(height - fittedHeight) > 1 else { return }
            fittedHeight = height
        }
        // Single height detent keeps the sheet fixed to content — no medium/large resize.
        .presentationDetents([fittedDetent])
        .presentationDragIndicator(.visible)
        // Leave corner radius to the system so Liquid Glass / device bezels stay matched.
        .task(id: request.id) {
            await metadata.preparePreview(for: seed)
        }
    }

    private var headerRow: some View {
        Button(action: openChannel) {
            HStack(alignment: .center, spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: details.name)
                        .appFont(.headline, weight: .semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let handle = details.handle, !handle.isEmpty {
                        Text(verbatim: handle)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    statsLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to \(details.name)")
        .accessibilityHint("Opens the channel")
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(MediaStyle.placeholderFill)
            Text(details.name.prefix(1).uppercased())
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            KFImage(details.thumbnailURL)
                .thumbnail(size: CGSize(width: 48, height: 48)) { Color.clear }
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statsLine: some View {
        let parts = statsParts
        if parts.isEmpty {
            if metadata.isLoading(request.id) {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Loading channel details")
            }
        } else {
            Text(verbatim: parts.joined(separator: " · "))
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statsParts: [String] {
        var parts: [String] = []
        if let count = details.subscriberCount {
            parts.append(subscriberCountLabel(count))
        }
        if let count = details.videoCount {
            parts.append(videoCountLabel(count))
        }
        if details.isSubscribed {
            parts.append(String(localized: "Subscribed"))
        }
        return parts
    }

    @ViewBuilder
    private var activitySection: some View {
        if pageInfo.showsLatestTitle, let title = pageInfo.latestTitle {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Latest")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(verbatim: title)
                    .appFont(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Latest upload: \(title)"))
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        if !aboutText.isEmpty {
            Text(verbatim: aboutText)
                .appFont(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let joined = pageInfo.joinedText, !joined.isEmpty {
                Text(verbatim: joined)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                if commentsHidden {
                    hiddenAuthors.unhide(channelID: request.id)
                } else {
                    hiddenAuthors.hide(channelID: request.id, name: details.name)
                }
            } label: {
                Text(commentsHidden ? "Show user" : "Hide user")
                    .appFont(.caption, weight: .semibold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(commentsHidden ? .secondary : .primary)
            .accessibilityLabel(commentsHidden ? "Show comments from this channel" : "Hide comments from this channel")
        }
    }

    private func openChannel() {
        let channelID = request.id
        metadata.prefetchChannelPage(id: channelID)
        dismiss()
        // Same collapse-then-navigate path as the uploader control. Collapse completion is
        // deadline-backed so a competing sheet dismiss cannot stall the push.
        AppLog(subsystem: "com.leshko.freetube", category: "Navigation")
            .info("Channel preview opening channel; collapsing player")
        player.channelPreviewRequest = nil
        player.requestPlayerCollapse {
            AppLog(subsystem: "com.leshko.freetube", category: "Navigation")
                .info("Channel preview posting channel navigation")
            NotificationCenter.default.post(name: .freetubeOpenChannel, object: channelID)
        }
    }

    /// Uses the integer plural catalog for small counts; abbreviated counts stay plural prose.
    private func videoCountLabel(_ count: Int) -> String {
        if abs(count) >= 1_000 {
            let compact = count.formatted(.number.notation(.compactName))
            return String(localized: "\(compact) videos")
        }
        return String(localized: "\(count) videos")
    }

    private func subscriberCountLabel(_ count: Int) -> String {
        if abs(count) >= 1_000 {
            let compact = count.formatted(.number.notation(.compactName))
            return String(localized: "\(compact) subscribers")
        }
        if count == 1 {
            return String(localized: "1 subscriber")
        }
        return String(localized: "\(count) subscribers")
    }
}

@available(iOS 17.0, *)
private struct ChannelPreviewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
