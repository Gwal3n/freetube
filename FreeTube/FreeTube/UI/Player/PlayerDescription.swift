import SwiftUI

/// Description presentation has no playback-progress dependency. The parent retains loading
/// and expansion state so extracting the view cannot reset an open description.
struct PlayerDescription: View {
    let text: String?
    let parts: [VideoDescriptionPart]
    let likesText: String?
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
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading details…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if loadFailed {
                    HStack(spacing: 8) {
                        Text("Description unavailable").font(.subheadline).foregroundStyle(.secondary)
                        Button("Retry", action: onRetry)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                    }
                }
                if let likesText {
                    Text("\(likesText) likes").font(.caption).foregroundStyle(.secondary)
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
                .buttonStyle(.plain)
                .accessibilityHint("Expand description")
            }
        }
        .padding(.horizontal)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isExpanded)
    }
}
