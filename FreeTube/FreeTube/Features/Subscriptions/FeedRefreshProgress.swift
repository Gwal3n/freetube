import SwiftUI

/// A compact feed status that shares one header line with the selected subscription group.
@available(iOS 17.0, *)
struct FeedRefreshProgress: View {
    let model: SubscriptionFeedViewModel
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if model.isRefreshing {
                Text("Refreshing \(model.refreshedChannels)/\(model.refreshChannelCount)")
            } else if let lastRefreshAt = model.lastRefreshAt {
                ViewThatFits(in: .horizontal) {
                    Text("Updated \(relativeAge(since: lastRefreshAt))")
                    Text(verbatim: relativeAge(since: lastRefreshAt))
                }
            }

            if model.isRefreshing {
                ProgressView(
                    value: Double(model.refreshedChannels),
                    total: Double(max(1, model.refreshChannelCount))
                )
                .progressViewStyle(.linear)
                .tint(.white)
                .frame(height: 2)
            } else {
                Color.clear.frame(height: 2)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityStatus)
    }

    private var accessibilityStatus: Text {
        if model.isRefreshing {
            return Text("Refreshing \(model.refreshedChannels) of \(model.refreshChannelCount) channels")
        }
        guard let lastRefreshAt = model.lastRefreshAt else { return Text("Not refreshed yet") }
        return Text("Last refreshed \(relativeAge(since: lastRefreshAt, style: .full))")
    }

    private func relativeAge(
        since date: Date,
        style: RelativeDateTimeFormatter.UnitsStyle = .abbreviated
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = style
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
