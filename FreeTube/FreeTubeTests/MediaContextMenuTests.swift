import XCTest
@testable import FreeTube

final class MediaContextMenuTests: XCTestCase {
    func testPlaylistLinkStripsBrowsePrefix() throws {
        let url = try XCTUnwrap(playlist(" VLPL123 ").youtubeURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "www.youtube.com")
        XCTAssertEqual(components.path, "/playlist")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "list", value: "PL123")])
        XCTAssertEqual(playlist("PL123").youtubeURL, url)
    }

    func testPlaylistLinkKeepsIdentifierInOneQueryValue() throws {
        let url = try XCTUnwrap(playlist("PL123&other=value").youtubeURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "list", value: "PL123&other=value")])
    }

    func testMissingIdentifiersDoNotProduceShareLinks() {
        XCTAssertNil(playlist(" ").youtubeURL)
        XCTAssertNil(playlist("VL").youtubeURL)
        XCTAssertNil(channel(" ").youtubeURL)
    }

    func testChannelLinkUsesChannelIdentifier() {
        XCTAssertEqual(channel(" UC123 ").youtubeURL?.absoluteString, "https://www.youtube.com/channel/UC123")
    }

    private func playlist(_ id: String) -> Playlist {
        Playlist(id: id, title: "Playlist", channelID: nil, channelName: nil,
                 thumbnailURL: nil, videoCount: nil, descriptionText: nil, isOwnedByUser: false)
    }

    private func channel(_ id: String) -> Channel {
        Channel(id: id, name: "Channel", handle: nil, thumbnailURL: nil, bannerURL: nil,
                subscriberCount: nil, videoCount: nil, isSubscribed: false, descriptionText: nil)
    }
}
