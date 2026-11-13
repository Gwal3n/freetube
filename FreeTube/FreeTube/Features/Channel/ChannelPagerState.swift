import CoreGraphics
import Observation

/// Coordinates the channel's shared collapsing header with each tab's own reading position.
@available(iOS 17.0, *)
@Observable
@MainActor
final class ChannelPagerState {
    var selectedTab: ChannelProfileTab = .videos
    var pagerOffset: CGFloat = 0
    var pageWidth: CGFloat = 0
    var pageViewportHeight: CGFloat = 0
    var pageScrollTargets: [String: ChannelPageScrollTarget] = [:]
    var headerCollapse: CGFloat = 0
    var pageContentPositions: [String: CGFloat] = [:]
    var pageOffsets: [String: CGFloat] = [:]

    // Estimated heights prevent the first page's rows from briefly sitting under the header.
    var headerContentHeight: CGFloat = ChannelProfileMetrics.estimatedHeaderHeight
    var tabBarHeight: CGFloat = ChannelProfileMetrics.estimatedTabBarHeight

    private static let supportsPageAlignment: Bool = {
        if #available(iOS 18.0, *) { return true }
        return false
    }()

    var headerOffset: CGFloat {
        let raw = Self.supportsPageAlignment
            ? headerCollapse
            : (pageOffsets[selectedTab.id] ?? 0)
        return min(max(0, raw), headerContentHeight)
    }

    var headerTotalHeight: CGFloat {
        headerContentHeight + tabBarHeight
    }

    var showsNavigationTitle: Bool {
        guard headerContentHeight > 0 else { return false }
        return headerOffset > headerContentHeight - ChannelProfileMetrics.navigationTitleLead
    }

    var pagePosition: CGFloat {
        guard pageWidth > 0 else { return 0 }
        return max(0, pagerOffset / pageWidth)
    }

    var isPagingActive: Bool {
        guard pageWidth > 0 else { return false }
        return abs(pagePosition - pagePosition.rounded()) > 0.01
    }

    func updateTabs(_ tabs: [ChannelProfileTab]) {
        guard !tabs.isEmpty else { return }
        let destination = tabs.contains(selectedTab) ? selectedTab : .videos
        selectedTab = destination
        if let index = tabs.firstIndex(of: destination), pageWidth > 0 {
            pagerOffset = CGFloat(index) * pageWidth
        }
    }

    /// Spend downward scroll on header collapse before moving content; reverse that order when
    /// scrolling upward. Each tab retains its own content position through tab changes.
    func handlePageScroll(tab: ChannelProfileTab, offset: CGFloat) {
        let offset = Self.normalizedPageOffset(offset)
        let previous = pageOffsets[tab.id] ?? offset
        pageOffsets[tab.id] = offset
        guard tab.id == selectedTab.id else { return }

        let delta = offset - previous
        guard delta != 0 else { return }

        let limit = headerContentHeight
        var collapse = min(max(0, headerCollapse), limit)
        var content = max(0, pageContentPositions[tab.id] ?? 0)
        if delta > 0 {
            let toHeader = min(delta, limit - collapse)
            collapse += toHeader
            content += delta - toHeader
        } else {
            let toContent = min(-delta, content)
            content -= toContent
            collapse = max(0, collapse - (-delta - toContent))
        }
        headerCollapse = collapse
        pageContentPositions[tab.id] = content
    }

    /// Re-seat the pages outside the current tab so their content position matches the shared
    /// header before they slide into view. Tokens make repeated destinations new requests.
    func alignPages(_ tabs: [ChannelProfileTab], excluding driver: ChannelProfileTab) {
        guard Self.supportsPageAlignment else { return }
        for tab in tabs where tab.id != driver.id {
            let target = headerOffset + max(0, pageContentPositions[tab.id] ?? 0)
            guard abs((pageOffsets[tab.id] ?? 0) - target) > 1 else { continue }
            pageOffsets[tab.id] = target
            let token = (pageScrollTargets[tab.id]?.token ?? 0) + 1
            pageScrollTargets[tab.id] = ChannelPageScrollTarget(y: target, token: token)
        }
    }

    nonisolated static func normalizedPageOffset(_ offset: CGFloat) -> CGFloat {
        max(0, offset)
    }

    nonisolated static func minimumPageContentHeight(viewport: CGFloat, tabBar: CGFloat, topInset: CGFloat) -> CGFloat {
        max(0, viewport - tabBar - topInset)
    }
}
