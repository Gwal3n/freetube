import SwiftUI

/// Presentation-only playlist identity and statistics. Loading and actions remain in the screen.
@available(iOS 17.0, *)
struct PlaylistMetadataBlock: View {
    let details: PlaylistDetails
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(details.playlist.title)
                .font(.title3.weight(.semibold))
                .lineLimit(3)

            if let channelName = details.playlist.channelName, !channelName.isEmpty {
                Text(channelName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: "Videos", value: videoCountLabel)
                statRow(label: "Views", value: viewsLabel)
                descriptionRow(details.playlist.descriptionText)
            }

            if shouldShowMoreButton {
                Button {
                    withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Less" : "More details")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(ResponsiveButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var videoCountLabel: String {
        if let total = details.playlist.videoCount { return "\(total)" }
        return "\(details.videos.count)\(details.continuationToken == nil ? "" : "+")"
    }

    private var viewsLabel: String? {
        guard let views = details.playlist.viewCount else { return nil }
        return abbreviated(views)
    }

    private var shouldShowMoreButton: Bool {
        guard let description = details.playlist.descriptionText else { return false }
        return description.count > 100
    }

    @ViewBuilder
    private func descriptionRow(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                metadataLabel("Description")
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func statRow(label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                metadataLabel(label)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metadataLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.tertiary)
            .frame(width: 84, alignment: .leading)
    }

    private func abbreviated(_ value: Int) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}
