import SwiftUI

/// Shared dimensions for the loaded channel header and its first-frame placeholder.
@available(iOS 17.0, *)
enum ChannelProfileMetrics {
    static let bannerHeight: CGFloat = 190
    static let avatarSize: CGFloat = 72
    static let headerRowSpacing: CGFloat = 14
    static let headerRowInset: CGFloat = 20
    static let navigationTitleLead: CGFloat = 20
    static let contentTopInset: CGFloat = 12
    static var estimatedHeaderHeight: CGFloat { bannerHeight + avatarSize + 34 }
    static let estimatedTabBarHeight: CGFloat = 44
}
