import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
@MainActor
final class PlayerSponsorBlockCoordinatorTests: XCTestCase {
    func testOnlyEligibleSegmentsAreObserved() {
        let coordinator = PlayerSponsorBlockCoordinator()
        let sponsor = segment("sponsor", start: 10, end: 20)

        XCTAssertTrue(coordinator.shouldObserve(sponsor, behavior: .autoSkip, minimumSkipSeconds: 10))
        XCTAssertFalse(coordinator.shouldObserve(sponsor, behavior: .showOnly, minimumSkipSeconds: 0))
        XCTAssertFalse(coordinator.shouldObserve(sponsor, behavior: .autoSkip, minimumSkipSeconds: 11))
        XCTAssertFalse(coordinator.shouldObserve(
            segment("label", start: 0, end: 100, isFullVideoLabel: true),
            behavior: .autoSkip,
            minimumSkipSeconds: 0
        ))
        XCTAssertFalse(coordinator.shouldObserve(
            segment("chapter", start: 10, end: 20, category: .chapter),
            behavior: .autoSkip,
            minimumSkipSeconds: 0
        ))
    }

    func testSkipIsClaimedOnceAndUndoReturnsToEntryPoint() {
        let coordinator = PlayerSponsorBlockCoordinator()
        let sponsor = segment("sponsor", start: 10, end: 20)

        XCTAssertEqual(coordinator.claimSkip(
            for: sponsor, enteredAt: 10.5, isEnabled: true, hasVideo: true,
            behavior: .autoSkip, minimumSkipSeconds: 0
        ), 10)
        XCTAssertNil(coordinator.claimSkip(
            for: sponsor, enteredAt: 15, isEnabled: true, hasVideo: true,
            behavior: .autoSkip, minimumSkipSeconds: 0
        ))
        coordinator.rearm(afterSeekingTo: 15, segments: [sponsor])
        XCTAssertEqual(coordinator.claimSkip(
            for: sponsor, enteredAt: 15, isEnabled: true, hasVideo: true,
            behavior: .autoSkip, minimumSkipSeconds: 0
        ), 15)
        coordinator.rearm(afterSeekingTo: 20, segments: [sponsor])
        XCTAssertNil(coordinator.claimSkip(
            for: sponsor, enteredAt: 15, isEnabled: true, hasVideo: true,
            behavior: .autoSkip, minimumSkipSeconds: 0
        ))
    }

    func testDisabledOrInvalidEntryNeverClaimsSegment() {
        let coordinator = PlayerSponsorBlockCoordinator()
        let sponsor = segment("sponsor", start: 10, end: 20)

        XCTAssertNil(coordinator.claimSkip(
            for: sponsor, enteredAt: 15, isEnabled: false, hasVideo: true,
            behavior: .autoSkip, minimumSkipSeconds: 0
        ))
        XCTAssertNil(coordinator.claimSkip(
            for: sponsor, enteredAt: 20, isEnabled: true, hasVideo: true,
            behavior: .autoSkip, minimumSkipSeconds: 0
        ))
        XCTAssertEqual(coordinator.claimSkip(
            for: sponsor, enteredAt: 15, isEnabled: true, hasVideo: true,
            behavior: .autoSkip, minimumSkipSeconds: 0
        ), 15)
    }

    private func segment(
        _ id: String,
        start: TimeInterval,
        end: TimeInterval,
        category: SponsorBlockCategory = .sponsor,
        isFullVideoLabel: Bool = false
    ) -> SponsorBlockSegment {
        SponsorBlockSegment(
            id: id, startTime: start, endTime: end,
            category: category, isFullVideoLabel: isFullVideoLabel
        )
    }
}
