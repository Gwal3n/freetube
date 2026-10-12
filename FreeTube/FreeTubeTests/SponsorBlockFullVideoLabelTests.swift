import XCTest
@testable import FreeTube

@MainActor
final class SponsorBlockFullVideoLabelTests: XCTestCase {
    func testFullVideoLabelsAreDecodedWithoutTurningIntoSkipRanges() throws {
        let payload = Data("""
        [{"videoID":"video123456","segments":[
          {"segment":[0,0],"UUID":"self","category":"selfpromo","actionType":"full"},
          {"segment":[0,0],"UUID":"exclusive","category":"exclusive_access","actionType":"full"},
          {"segment":[0,0],"UUID":"sponsor","category":"sponsor","actionType":"full"},
          {"segment":[10,20],"UUID":"skip","category":"sponsor","actionType":"skip"},
          {"segment":[0,0],"UUID":"invalid","category":"intro","actionType":"full"}
        ]}]
        """.utf8)

        let segments = try SponsorBlockService.decodeSegments(
            payload,
            videoID: "video123456",
            categories: [.sponsor, .selfPromotion, .exclusiveAccess, .intro]
        )

        XCTAssertEqual(segments.count, 4)
        XCTAssertEqual(segments.filter(\.isFullVideoLabel).count, 3)
        XCTAssertEqual(SponsorBlockSegment.primaryFullVideoLabel(in: segments), .sponsor)
        XCTAssertFalse(try XCTUnwrap(segments.first { $0.id == "skip" }).isFullVideoLabel)
    }

    func testDisabledCategoriesCannotAppearAsLabels() throws {
        let payload = Data("""
        [{"videoID":"video123456","segments":[
          {"segment":[0,0],"UUID":"sponsor","category":"sponsor","actionType":"full"},
          {"segment":[0,0],"UUID":"self","category":"selfpromo","actionType":"full"}
        ]}]
        """.utf8)

        let segments = try SponsorBlockService.decodeSegments(
            payload,
            videoID: "video123456",
            categories: [.selfPromotion]
        )

        XCTAssertEqual(SponsorBlockSegment.primaryFullVideoLabel(in: segments), .selfPromotion)
    }
}
