import SwiftUI
import Kingfisher

/// Compact native bottom sheet with channel identity, stats, about, and local actions.
@available(iOS 17.0, *)
struct ChannelPreviewSheet: View {
    let request: ChannelPreviewRequest

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metadata = ChannelPreviewMetadataStore.shared
    @State private var subscriptions = LocalSubscriptionStore.shared
    @State private var isDescriptionExpanded = false
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

    /// Only offer a taller detent when there is a longer about to read.
    private var canExpand: Bool { aboutText.count > 120 }

    private var pageInfo: ChannelPreviewPageInfo {
        metadata.pageInfo(for: request.id)
    }

    private var detents: Set<PresentationDetent> {
        var set: Set<PresentationDetent> = [.height(max(fittedHeight, 1))]
        if canExpand {
            set.insert(.medium)
        }
        return set
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if let title = pageInfo.latestTitle {
                latestUploadRow(
                    title: title,
                    relative: pageInfo.latestRelative,
                    viewCount: pageInfo.latestViewCount
                )
            }
            aboutSection

            // Pull actions off the header block and keep the sheet height fitted to content
            // so leftover chrome doesn't pool as empty space under the buttons.
            actionRow
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        // Leave room below the grabber so the header isn't flush with the sheet edge.
        .padding(.top, 18)
        // Keep bottom padding modest — oversizing the detent left empty chrome under the buttons.
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
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        // Leave corner radius to the system so Liquid Glass / device bezels stay matched.
        .task(id: request.id) {
            await metadata.preparePreview(for: seed)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: details.name)
                    .appFont(.headline, weight: .semibold)
                    .lineLimit(2)
                if let handle = details.handle, !handle.isEmpty {
                    Text(verbatim: handle)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                statsLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        return parts
    }

    private func latestUploadRow(title: String, relative: String?, viewCount: Int?) -> some View {
        let metaParts = latestMetaParts(relative: relative, viewCount: viewCount)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Latest")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(verbatim: title)
                    .appFont(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            if !metaParts.isEmpty {
                Text(verbatim: metaParts.joined(separator: " · "))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(latestAccessibilityLabel(title: title, relative: relative, viewCount: viewCount))
    }

    private func latestMetaParts(relative: String?, viewCount: Int?) -> [String] {
        var parts: [String] = []
        if let viewCount, viewCount > 0 {
            parts.append(Video.viewCountLabel(viewCount))
        }
        if let relative, !relative.isEmpty {
            parts.append(relative)
        }
        return parts
    }

    private func latestAccessibilityLabel(title: String, relative: String?, viewCount: Int?) -> String {
        var parts = [String(localized: "Latest upload: \(title)")]
        if let viewCount, viewCount > 0 {
            parts.append(Video.viewCountLabel(viewCount))
        }
        if let relative, !relative.isEmpty {
            parts.append(relative)
        }
        return parts.joined(separator: ", ")
    }

    private var aboutLineLimit: Int {
        if !canExpand { return 3 }
        return isDescriptionExpanded ? 10 : 2
    }

    @ViewBuilder
    private var aboutSection: some View {
        if !aboutText.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: aboutText)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(aboutLineLimit)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if canExpand {
                    Button(isDescriptionExpanded ? "Show Less" : "More") {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                            isDescriptionExpanded.toggle()
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: toggleSubscribe) {
                Text(details.isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(details.isSubscribed
                        ? Color.primary
                        : (colorScheme == .dark ? Color.black : Color.white))
                    .background(
                        details.isSubscribed
                            ? AnyShapeStyle(Color.primary.opacity(0.10))
                            : AnyShapeStyle(colorScheme == .dark ? Color.white : Color.black),
                        in: Capsule()
                    )
            }
            .buttonStyle(ResponsiveButtonStyle())
            .animation(reduceMotion ? nil : InterfaceMotion.quick, value: details.isSubscribed)

            Button(action: openChannel) {
                Text("Go to Channel")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(.primary)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(ResponsiveButtonStyle())
        }
    }

    private func toggleSubscribe() {
        if subscriptions.contains(details.id) {
            subscriptions.remove(channelID: details.id)
        } else {
            subscriptions.add(details.withSubscribed(true))
        }
    }

    private func openChannel() {
        let channelID = request.id
        metadata.prefetchChannelPage(id: channelID)
        dismiss()
        // Same collapse-then-navigate path as the uploader control. Collapse completion is
        // deadline-backed so a competing sheet dismiss cannot stall the push.
        AppLog(subsystem: "com.leshko.freetube", category: "Navigation")
            .info("Channel preview Go to channel; collapsing player")
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
