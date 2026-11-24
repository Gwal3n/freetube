import SwiftUI
import Kingfisher

/// Native bottom sheet with channel identity, stats, about, and local subscribe / open actions.
@available(iOS 17.0, *)
struct ChannelPreviewSheet: View {
    let request: ChannelPreviewRequest
    let onOpenChannel: () -> Void

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
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    identity
                    stats
                    actions
                    about
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .task(id: request.id) {
            await metadata.loadIfNeeded(for: seed)
        }
    }

    private var identity: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(MediaStyle.placeholderFill)
                Text(details.name.prefix(1).uppercased())
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.secondary)
                KFImage(details.thumbnailURL)
                    .thumbnail(size: CGSize(width: 96, height: 96)) { Color.clear }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)

            VStack(spacing: 4) {
                Text(verbatim: details.name)
                    .appFont(.title2, weight: .bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let handle = details.handle, !handle.isEmpty {
                    Text(verbatim: handle)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var stats: some View {
        if details.subscriberCount != nil || details.videoCount != nil {
            HStack(spacing: 0) {
                if let count = details.subscriberCount {
                    statCell(
                        value: count.formatted(.number.notation(.compactName)),
                        label: String(localized: "Subscribers")
                    )
                }
                if details.subscriberCount != nil, details.videoCount != nil {
                    Divider()
                        .frame(height: 36)
                }
                if let count = details.videoCount {
                    statCell(
                        value: count.formatted(.number.notation(.compactName)),
                        label: String(localized: "Videos")
                    )
                }
            }
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if metadata.isLoading(request.id) {
            ProgressView()
                .controlSize(.regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .accessibilityLabel("Loading channel details")
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value)
                .appFont(.title3, weight: .semibold)
                .monospacedDigit()
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: toggleSubscribe) {
                Text(details.isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
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

            Button {
                dismiss()
                // Let the sheet finish dismissing before collapsing the player for navigation.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    onOpenChannel()
                }
            } label: {
                Text("Go to Channel")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.primary)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(ResponsiveButtonStyle())
        }
    }

    @ViewBuilder
    private var about: some View {
        let description = details.descriptionText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("About")
                    .appFont(.headline, weight: .semibold)
                Text(verbatim: description)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(isDescriptionExpanded ? nil : 5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if description.count > 220 || description.split(separator: "\n").count > 5 {
                    Button(isDescriptionExpanded ? "Show Less" : "More") {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                            isDescriptionExpanded.toggle()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func toggleSubscribe() {
        if subscriptions.contains(details.id) {
            subscriptions.remove(channelID: details.id)
        } else {
            subscriptions.add(details.withSubscribed(true))
        }
    }
}
