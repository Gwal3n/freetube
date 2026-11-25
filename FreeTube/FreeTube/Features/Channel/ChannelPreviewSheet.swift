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

    private var seed: Channel { request.seedChannel }

    private var details: Channel {
        let enriched = metadata.enriched(seed)
        return enriched.withSubscribed(subscriptions.contains(enriched.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            aboutSection
            actionRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .presentationDetents([.height(268), .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .task(id: request.id) {
            await metadata.preparePreview(for: seed)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 14) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            KFImage(details.thumbnailURL)
                .thumbnail(size: CGSize(width: 56, height: 56)) { Color.clear }
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
        }
        .frame(width: 56, height: 56)
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
            let compact = count.formatted(.number.notation(.compactName))
            parts.append(String(localized: "\(compact) subscribers"))
        }
        if let count = details.videoCount {
            let compact = count.formatted(.number.notation(.compactName))
            parts.append(String(localized: "\(compact) videos"))
        }
        return parts
    }

    @ViewBuilder
    private var aboutSection: some View {
        let description = details.descriptionText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: description)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(isDescriptionExpanded ? 8 : 3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if description.count > 140 {
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
                    .frame(maxWidth: .infinity, minHeight: 44)
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
                    .frame(maxWidth: .infinity, minHeight: 44)
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

    /// Collapse and navigate immediately — do not wait for the player spring completion.
    /// Logs showed multi-second stalls when Go to Channel waited on `finishPlayerCollapse`.
    private func openChannel() {
        let channelID = request.id
        metadata.prefetchChannelPage(id: channelID)
        dismiss()
        MediaContextNavigation.open(.freetubeOpenChannel, id: channelID, player: player)
    }
}
