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
        let content = ChannelScreen.minimumPageContentHeight(
            viewport: viewport, tabBar: tabBar, topInset: topInset
        )
        XCTAssertEqual(header + tabBar + topInset + content - viewport, header)
        XCTAssertEqual(ChannelScreen.minimumPageContentHeight(viewport: 0, tabBar: 44, topInset: 12), 0)
    }

    func testTopRubberBandAndReboundDoNotMoveHeader() {
        let samples: [CGFloat] = [0, -10, -70, -35, -5, 0]
        let normalized = samples.map(ChannelScreen.normalizedPageOffset)
        XCTAssertEqual(normalized, Array(repeating: CGFloat.zero, count: samples.count))
    }

    func testActualContentScrollingIsUnchanged() {
        let offsets: [CGFloat] = [0, 10, 200, 1_000]
        for value in offsets {
            XCTAssertEqual(ChannelScreen.normalizedPageOffset(value), value)
        }
    }
}
