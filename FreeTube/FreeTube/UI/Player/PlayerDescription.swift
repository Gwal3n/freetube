import SwiftUI

/// Description presentation has no playback-progress dependency. The parent retains loading
/// and expansion state so extracting the view cannot reset an open description.
struct PlayerDescription: View {
    let text: String?
    let parts: [VideoDescriptionPart]
    let isExpanded: Bool
    let isLoading: Bool
    let loadFailed: Bool
    let onSeek: (TimeInterval) -> Void
    let onRetry: () -> Void
    let onExpand: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isExpanded {
                if let text {
                    RichDescriptionText(parts: parts, fallback: text, onSeek: onSeek)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                } else if isLoading {
                    PlayerDescriptionPlaceholder()
                } else if loadFailed {
                    HStack(spacing: 8) {
                        Text("Description unavailable").font(.subheadline).foregroundStyle(.secondary)
                        Button("Retry", action: onRetry)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                    }
                }
            } else if let text {
                Button(action: onExpand) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityHint("Expand description")
            }
        }
        .padding(.horizontal)
        .animation(reduceMotion ? nil : InterfaceMotion.content, value: isExpanded)
    }
}

/// Reserves text-like geometry while metadata arrives, avoiding a spinner-to-paragraph jump.
private struct PlayerDescriptionPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(height: 11)
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(maxWidth: 290)
                .frame(height: 11)
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(width: 150, height: 9)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading video details")
    }
}
