import Foundation
import XCTest
@testable import FreeTube

@MainActor
final class RecentChannelTests: XCTestCase {
    func testOlderHistoryIsLimitedAndDeletionDoesNotRevealHiddenEntries() throws {
        let channels = (1...5).map { index in
            RecentChannel(id: "channel-\(index)", name: "Channel \(index)",
                          handle: nil, thumbnailURL: nil)
        }
        let oldJSON = try XCTUnwrap(String(data: JSONEncoder().encode(channels), encoding: .utf8))
        var visible = RecentChannel.entries(from: oldJSON)
        XCTAssertEqual(visible.map(\.id), ["channel-1", "channel-2", "channel-3"])
        let limitedJSON = try XCTUnwrap(RecentChannel.json(from: channels))
        XCTAssertEqual(try JSONDecoder().decode([RecentChannel].self,
                                                from: XCTUnwrap(limitedJSON.data(using: .utf8))).count, 3)

        visible.remove(at: 1)
        let updatedJSON = try XCTUnwrap(RecentChannel.json(from: visible))
        XCTAssertEqual(RecentChannel.entries(from: updatedJSON).map(\.id),
                       ["channel-1", "channel-3"])
    }
}
