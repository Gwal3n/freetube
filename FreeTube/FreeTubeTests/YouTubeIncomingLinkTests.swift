import XCTest

@testable import FreeTube

@MainActor
final class YouTubeIncomingLinkTests: XCTestCase {
    func testVideoLinks() {
        XCTAssertEqual(
            YouTubeIncomingLink.parse(URL(string: "https://youtu.be/dQw4w9WgXcQ?t=42")!),
            .video("dQw4w9WgXcQ")
        )
        XCTAssertEqual(
            YouTubeIncomingLink.parse(URL(string: "https://www.youtube.com/shorts/dQw4w9WgXcQ")!),
            .video("dQw4w9WgXcQ")
        )
    }

    func testPlaylistAndChannelLinks() {
        XCTAssertEqual(
            YouTubeIncomingLink.parse(URL(string: "https://www.youtube.com/playlist?list=PL1234567890")!),
            .playlist("PL1234567890")
        )
        XCTAssertEqual(
            YouTubeIncomingLink.parse(URL(string: "https://www.youtube.com/channel/UC1234567890123456789012")!),
            .channel("UC1234567890123456789012")
        )
        XCTAssertEqual(
            YouTubeIncomingLink.parse(URL(string: "https://www.youtube.com/@ExampleChannel")!),
            .channelHandle("@ExampleChannel")
        )
    }

    func testWrappedLinkAndUntrustedHosts() {
        let wrapped = URL(string: "com.leshko.freetube://open?url=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ")!
        XCTAssertEqual(YouTubeIncomingLink.parse(wrapped), .video("dQw4w9WgXcQ"))
        XCTAssertNil(YouTubeIncomingLink.parse(URL(string: "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ")!))
        XCTAssertNil(YouTubeIncomingLink.parse(URL(string: "com.leshko.freetube://open?url=https%3A%2F%2Fevil.example%2F")!))
        XCTAssertNil(YouTubeIncomingLink.parse(URL(string: "com.leshko.freetube://open?url=com.leshko.freetube%3A%2F%2Fopen")!))
    }
}
