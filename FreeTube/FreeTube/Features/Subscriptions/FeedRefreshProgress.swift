import SwiftUI

/// The feed header keeps its status inside the row and gives the refresh bar the full row width.
@available(iOS 17.0, *)
struct FeedRefreshProgress<LeadingContent: View>: View {
    let model: SubscriptionFeedViewModel
    let referenceDate: Date
    let hasLeadingContent: Bool
    let onCancel: () -> Void
    let leadingContent: LeadingContent

    init(
        model: SubscriptionFeedViewModel,
        referenceDate: Date,
        hasLeadingContent: Bool,
        onCancel: @escaping () -> Void,
        @ViewBuilder leadingContent: () -> LeadingContent
    ) {
        self.model = model
        self.referenceDate = referenceDate
        self.hasLeadingContent = hasLeadingContent
        self.onCancel = onCancel
        self.leadingContent = leadingContent()
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                if hasLeadingContent {
                    leadingContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.isRefreshing || model.lastRefreshAt != nil {
                    HStack(spacing: 0) {
                        status
                        if model.isRefreshing {
                            Button(action: onCancel) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cancel feed refresh")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 24)

            if model.isRefreshing {
                ProgressView(
                    value: Double(model.refreshedChannels),
                    total: Double(max(1, model.refreshChannelCount))
                )
                .progressViewStyle(.linear)
                .tint(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 4)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var status: some View {
        Group {
            if model.isRefreshing {
                Text("Refreshing \(model.refreshedChannels)/\(model.refreshChannelCount)")
            } else if let lastRefreshAt = model.lastRefreshAt {
                ViewThatFits(in: .horizontal) {
                    Text("Updated \(relativeAge(since: lastRefreshAt))")
                    Text(verbatim: relativeAge(since: lastRefreshAt))
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
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
