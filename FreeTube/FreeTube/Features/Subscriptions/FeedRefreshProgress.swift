import SwiftUI

/// Slim, non-interactive refresh progress beneath the navigation bar. Overlay placement
/// keeps feed rows at their scroll positions and avoids extra toolbar glass chrome.
@available(iOS 17.0, *)
struct FeedRefreshProgress: View {
    let model: SubscriptionFeedViewModel

    var body: some View {
        if model.isRefreshing {
            ProgressView(
                value: Double(model.refreshedChannels),
                total: Double(max(1, model.refreshChannelCount))
            )
            .progressViewStyle(.linear)
            .tint(.white)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Refreshing subscriptions")
            .accessibilityValue("\(model.refreshedChannels) of \(model.refreshChannelCount)")
        }
    }
}
