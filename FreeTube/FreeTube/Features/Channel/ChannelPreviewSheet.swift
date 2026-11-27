import SwiftUI
import Kingfisher

/// Compact native bottom sheet with channel identity and optional latest/about info.
@available(iOS 17.0, *)
struct ChannelPreviewSheet: View {
    let request: ChannelPreviewRequest

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var metadata = ChannelPreviewMetadataStore.shared
    @State private var subscriptions = LocalSubscriptionStore.shared
    @State private var fittedHeight: CGFloat = 160

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

    private var showsLatest: Bool {
        pageInfo.showsLatestTitle && !(pageInfo.latestTitle?.isEmpty ?? true)
    }

    private var showsAbout: Bool { !aboutText.isEmpty }

    private var showsInfoGroup: Bool { showsLatest || showsAbout }

    private var joinedYearLabel: String? { pageInfo.joinedYearLabel }

    private var coreStatsParts: [String] {
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

    private var statsPartsIncludingJoin: [String] {
        var parts = coreStatsParts
        if let joinedYearLabel {
            // Keep join before Subscribed when both are present.
            if details.isSubscribed, let subscribed = parts.last {
                parts.removeLast()
                parts.append(joinedYearLabel)
                parts.append(subscribed)
            } else {
                parts.append(joinedYearLabel)
            }
        }
        return parts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            identityGroup
            if showsInfoGroup {
                infoGroup
            }
        }
        .padding(.horizontal, 20)
        // Clearance under the system drag indicator; keep the bottom tight to content.
        .padding(.top, 14)
        .padding(.bottom, 10)
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
            guard height > 1, abs(height - fittedHeight) > 0.5 else { return }
            fittedHeight = height
        }
        // One content-height detent only — native chrome stays; the sheet does not resize to medium/large.
        .presentationDetents([.height(max(fittedHeight, 1))])
        .presentationDragIndicator(.visible)
        .task(id: request.id) {
            await metadata.preparePreview(for: seed)
        }
    }

    // MARK: - Identity

    private var identityGroup: some View {
        Button(action: openChannel) {
            HStack(alignment: .center, spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: details.name)
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let handle = details.handle, !handle.isEmpty {
                        Text(verbatim: handle)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    statsBlock
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
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
    private var statsBlock: some View {
        let core = coreStatsParts
        let joined = joinedYearLabel
        if core.isEmpty && joined == nil {
            if metadata.isLoading(request.id) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.secondary)
                    .accessibilityLabel("Loading channel details")
            }
        } else if let joined {
            // Prefer one line; if join makes it too wide, drop join onto its own gray line.
            ViewThatFits(in: .horizontal) {
                statsText(statsPartsIncludingJoin)
                    .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    if !core.isEmpty {
                        statsText(core)
                    }
                    Text(verbatim: joined)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            statsText(core)
        }
    }

    private func statsText(_ parts: [String]) -> some View {
        Text(verbatim: parts.joined(separator: " · "))
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    // MARK: - Info

    private var infoGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsLatest, let title = pageInfo.latestTitle {
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
            if showsAbout {
                Text(verbatim: aboutText)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private func openChannel() {
        let channelID = request.id
        metadata.prefetchChannelPage(id: channelID)
        dismiss()
        AppLog(subsystem: "com.leshko.freetube", category: "Navigation")
            .info("Channel preview opening channel; collapsing player")
        player.channelPreviewRequest = nil
        player.requestPlayerCollapse {
            AppLog(subsystem: "com.leshko.freetube", category: "Navigation")
                .info("Channel preview posting channel navigation")
            NotificationCenter.default.post(name: .freetubeOpenChannel, object: channelID)
        }
    }

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
