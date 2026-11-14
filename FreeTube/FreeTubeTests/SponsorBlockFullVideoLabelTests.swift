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

    func testCommunityChaptersAreDecodedFromChapterActionType() throws {
        let payload = Data("""
        [{"videoID":"video123456","segments":[
          {"segment":[0,12],"UUID":"c1","category":"chapter","actionType":"chapter","description":"Intro"},
          {"segment":[12,40],"UUID":"c2","category":"chapter","actionType":"chapter","description":"Main"},
          {"segment":[40,50],"UUID":"bad","category":"chapter","actionType":"chapter","description":"  "},
          {"segment":[10,20],"UUID":"skip","category":"sponsor","actionType":"skip"}
        ]}]
        """.utf8)

        let segments = try SponsorBlockService.decodeSegments(
            payload,
            videoID: "video123456",
            categories: [.chapter, .sponsor]
        )

        let chapters = segments.filter { $0.category == .chapter }
        XCTAssertEqual(chapters.map(\.title), ["Intro", "Main"])
        XCTAssertEqual(chapters.map(\.startTime), [0, 12])
    }

    func testActionTypesIncludeChapterPoiAndFullWhenNeeded() {
        XCTAssertEqual(SponsorBlockService.actionTypes(for: [.sponsor]), ["skip", "full"])
        XCTAssertEqual(SponsorBlockService.actionTypes(for: [.chapter]), ["chapter"])
        XCTAssertEqual(SponsorBlockService.actionTypes(for: [.highlight]), ["poi"])
        XCTAssertEqual(
            SponsorBlockService.actionTypes(for: [.sponsor, .highlight, .chapter]),
            ["skip", "full", "poi", "chapter"]
        )
        XCTAssertEqual(SponsorBlockService.actionTypes(for: [.exclusiveAccess]), ["full"])
    }
}
