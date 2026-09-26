import XCTest
@testable import FreeTube

@MainActor
final class PlayerPolishTests: XCTestCase {
    func testPlaylistCountsAcceptDisplayStrings() {
        XCTAssertEqual(Mappers.parseAbbreviatedCount("123 videos"), 123)
        XCTAssertEqual(Mappers.parseAbbreviatedCount("1,234 videos"), 1_234)
        XCTAssertEqual(Mappers.parseAbbreviatedCount("1.2K videos"), 1_200)
        XCTAssertNil(Mappers.parseAbbreviatedCount(nil))
        XCTAssertNil(Mappers.parseAbbreviatedCount(""))
    }

    func testMatchingAspectRatioNeedsNoFillZoom() {
        XCTAssertEqual(PlayerZoomGeometry.fillScale(
            video: CGSize(width: 1920, height: 1080),
            viewport: CGSize(width: 1600, height: 900)
        ), 1, accuracy: 0.0001)
    }

    func testFillZoomHandlesBothLetterboxDirections() {
        let video = CGSize(width: 1920, height: 1080)
        let wide = PlayerZoomGeometry.fillScale(video: video, viewport: CGSize(width: 2400, height: 1080))
        let tall = PlayerZoomGeometry.fillScale(video: video, viewport: CGSize(width: 1920, height: 1350))
        XCTAssertEqual(wide, 1.25, accuracy: 0.0001)
        XCTAssertEqual(tall, 1.25, accuracy: 0.0001)
    }

    func testUnknownVideoSizeIsSafe() {
        XCTAssertEqual(PlayerZoomGeometry.fillScale(video: .zero, viewport: CGSize(width: 800, height: 400)), 1)
        XCTAssertEqual(PlayerZoomGeometry.clamped(.infinity, fillScale: 1.25), 1)
    }

    func testZoomSettlesNearDetentsAndRetainsIntermediatePositions() {
        XCTAssertEqual(PlayerZoomGeometry.settled(1.04, fillScale: 1.4), 1)
        XCTAssertEqual(PlayerZoomGeometry.settled(1.38, fillScale: 1.4), 1.4)
        XCTAssertEqual(PlayerZoomGeometry.settled(1.2, fillScale: 1.4), 1.2)
        XCTAssertEqual(PlayerZoomGeometry.clamped(0.6, fillScale: 1.4), 1)
        XCTAssertEqual(PlayerZoomGeometry.clamped(8, fillScale: 1.4), 3)
    }
}
