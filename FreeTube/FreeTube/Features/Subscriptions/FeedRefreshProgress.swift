import SwiftUI

/// Isolates per-channel progress observation from the feed List. Navigation-bar placement keeps
/// existing videos at the same scroll position while the native pull-to-refresh control runs.
@available(iOS 17.0, *)
struct FeedRefreshProgress: View {
    let model: SubscriptionFeedViewModel

    var body: some View {
        if model.isRefreshing {
            HStack(spacing: 8) {
                ProgressView(
                    value: Double(model.refreshedChannels),
                    total: Double(max(1, model.refreshChannelCount))
                )
                .frame(width: 64)
                Text(verbatim: "\(model.refreshedChannels)/\(model.refreshChannelCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Refreshing subscriptions")
            .accessibilityValue("\(model.refreshedChannels) of \(model.refreshChannelCount)")
        }
    }
}
