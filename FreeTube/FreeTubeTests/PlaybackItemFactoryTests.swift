import AVFoundation
import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
@MainActor
final class PlaybackItemFactoryTests: XCTestCase {
    func testDirectCandidateCreatesAnUninstalledURLItem() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/video.mp4"))
        let candidate = PlaybackCandidate(source: .direct(url), strategy: .native)

        let item = try await PlaybackItemFactory().makeItem(for: candidate)

        XCTAssertEqual((item.asset as? AVURLAsset)?.url, url)
    }

    func testExtensionlessCandidateWithMIMEOverrideCreatesURLAsset() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/stream"))
        let candidate = PlaybackCandidate(
            source: .direct(url), strategy: .native, mimeTypeOverride: "application/vnd.apple.mpegurl"
        )

        let item = try await PlaybackItemFactory().makeItem(for: candidate)

        XCTAssertEqual((item.asset as? AVURLAsset)?.url, url)
    }
}
