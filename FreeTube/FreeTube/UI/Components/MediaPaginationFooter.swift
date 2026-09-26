import SwiftUI

/// Stable-height, neutral pagination feedback. The same row offers an explicit retry after a
/// failure; it never advertises background work with an endlessly spinning idle indicator.
@available(iOS 17.0, *)
struct MediaPaginationFooter: View {
    let isLoading: Bool
    var isRetry = false
    let onLoad: () -> Void

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading more…")
                }
                .accessibilityElement(children: .combine)
            } else {
                Button(action: onLoad) {
                    Text(isRetry ? "Try again" : "Load more")
                        .frame(maxWidth: .infinity, minHeight: MediaStyle.actionSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: MediaStyle.actionSize)
        .padding(.vertical, 8)
    }
}
