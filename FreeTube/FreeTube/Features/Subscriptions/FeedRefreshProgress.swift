import SwiftUI

/// Scrollable feed status. The same row shows bounded refresh progress or the last
/// successful refresh age, so the list does not jump between those two states.
@available(iOS 17.0, *)
struct FeedRefreshProgress: View {
    let model: SubscriptionFeedViewModel
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if model.isRefreshing {
                Text("Refreshing \(model.refreshedChannels)/\(model.refreshChannelCount)")
            } else if let lastRefreshAt = model.lastRefreshAt {
                lastRefreshedText(since: lastRefreshAt)
            }

            Group {
                if model.isRefreshing {
                    ProgressView(
                        value: Double(model.refreshedChannels),
                        total: Double(max(1, model.refreshChannelCount))
                    )
                    .progressViewStyle(.linear)
                    .tint(.white)
                } else {
                    Color.clear
                }
            }
            .frame(height: 4)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func lastRefreshedText(since date: Date) -> Text {
        let elapsed = max(0, referenceDate.timeIntervalSince(date))
        if elapsed < 3_600 {
            return Text("Last refreshed less than an hour ago")
        }
        let hours = Int(elapsed / 3_600)
        if hours == 1 {
            return Text("Last refreshed 1 hour ago")
        }
        if hours < 48 {
            return Text("Last refreshed \(hours) hours ago")
        }
        let days = Int(elapsed / 86_400)
        return Text("Last refreshed \(days) days ago")
    }
}
