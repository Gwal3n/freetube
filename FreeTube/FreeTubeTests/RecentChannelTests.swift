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

    func testChannelSavingHasIndependentSwitchAndPreservesExistingEntries() throws {
        let suiteName = "RecentChannelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let channel = Channel(id: "channel-1", name: "Channel 1", handle: nil,
                              thumbnailURL: nil, bannerURL: nil, subscriberCount: nil,
                              videoCount: nil, isSubscribed: false, descriptionText: nil)

        defaults.set(false, forKey: "saveSearchHistory")
        RecentChannel.record(channel, defaults: defaults)
        XCTAssertTrue(RecentChannel.entries(from: defaults.string(forKey: "recentChannelsJSON") ?? "[]").isEmpty)

        defaults.set(true, forKey: "saveRecentChannels")
        RecentChannel.record(channel, defaults: defaults)
        XCTAssertEqual(RecentChannel.entries(from: defaults.string(forKey: "recentChannelsJSON") ?? "[]").map(\.id),
                       [channel.id])

        defaults.set(false, forKey: "saveRecentChannels")
        let secondChannel = Channel(id: "channel-2", name: "Channel 2", handle: nil,
                                    thumbnailURL: nil, bannerURL: nil, subscriberCount: nil,
                                    videoCount: nil, isSubscribed: false, descriptionText: nil)
        RecentChannel.record(secondChannel, defaults: defaults)
        XCTAssertEqual(RecentChannel.entries(from: defaults.string(forKey: "recentChannelsJSON") ?? "[]").map(\.id),
                       [channel.id])
    }
}
