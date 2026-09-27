import CoreGraphics
import XCTest
@testable import FreeTube

@MainActor
final class ChannelScrollTests: XCTestCase {
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
