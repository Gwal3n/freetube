import CoreGraphics
import XCTest
@testable import FreeTube

@MainActor
final class ChannelScrollTests: XCTestCase {
    func testShortPageScrollRangeEqualsHeaderCollapseRange() {
        let viewport: CGFloat = 700
        let header: CGFloat = 300
        let tabBar: CGFloat = 44
        let topInset: CGFloat = 12
        let content = ChannelPagerState.minimumPageContentHeight(
            viewport: viewport, tabBar: tabBar, topInset: topInset
        )
        XCTAssertEqual(header + tabBar + topInset + content - viewport, header)
        XCTAssertEqual(ChannelPagerState.minimumPageContentHeight(viewport: 0, tabBar: 44, topInset: 12), 0)
    }

    func testTopRubberBandAndReboundDoNotMoveHeader() {
        let samples: [CGFloat] = [0, -10, -70, -35, -5, 0]
        let normalized = samples.map(ChannelPagerState.normalizedPageOffset)
        XCTAssertEqual(normalized, Array(repeating: CGFloat.zero, count: samples.count))
    }

    func testActualContentScrollingIsUnchanged() {
        let offsets: [CGFloat] = [0, 10, 200, 1_000]
        for value in offsets {
            XCTAssertEqual(ChannelPagerState.normalizedPageOffset(value), value)
        }
    }

    func testHeaderAndContentConsumeScrollInOrder() {
        let pager = ChannelPagerState()
        pager.headerContentHeight = 300

        pager.handlePageScroll(tab: .videos, offset: 0)
        pager.handlePageScroll(tab: .videos, offset: 360)
        XCTAssertEqual(pager.headerCollapse, 300)
        XCTAssertEqual(pager.pageContentPositions[ChannelProfileTab.videos.id] ?? -1, 60)

        pager.handlePageScroll(tab: .videos, offset: 340)
        XCTAssertEqual(pager.headerCollapse, 300)
        XCTAssertEqual(pager.pageContentPositions[ChannelProfileTab.videos.id] ?? -1, 40)

        pager.handlePageScroll(tab: .videos, offset: 0)
        XCTAssertEqual(pager.headerCollapse, 0)
        XCTAssertEqual(pager.pageContentPositions[ChannelProfileTab.videos.id] ?? -1, 0)
    }

    func testTabAlignmentPreservesOtherPagesReadingPosition() {
        guard #available(iOS 18.0, *) else { return }
        let pager = ChannelPagerState()
        pager.headerContentHeight = 300
        pager.headerCollapse = 300
        pager.pageContentPositions[ChannelProfileTab.shorts.id] = 100

        pager.alignPages([.videos, .shorts], excluding: .videos)
        XCTAssertEqual(pager.pageScrollTargets[ChannelProfileTab.shorts.id]?.y ?? -1, 400)
        XCTAssertEqual(pager.pageScrollTargets[ChannelProfileTab.shorts.id]?.token ?? -1, 1)

        pager.alignPages([.videos, .shorts], excluding: .videos)
        XCTAssertEqual(pager.pageScrollTargets[ChannelProfileTab.shorts.id]?.token ?? -1, 1)
    }
}
