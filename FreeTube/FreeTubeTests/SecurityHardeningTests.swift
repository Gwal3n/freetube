import XCTest
@testable import FreeTube

final class SecurityHardeningTests: XCTestCase {
    func testRedactedURLStripsQuery() {
        let url = URL(string: "https://rr1---sn-abc.googlevideo.com/videoplayback?expire=1&signature=deadbeef&id=x")!
        let redacted = SecurityHardening.redactedForLog(url)
        XCTAssertFalse(redacted.contains("signature"))
        XCTAssertFalse(redacted.contains("expire"))
        XCTAssertTrue(redacted.hasSuffix("?…"))
        XCTAssertTrue(redacted.contains("googlevideo.com"))
        XCTAssertTrue(redacted.contains("/videoplayback"))
    }

    func testSanitizeLogMessageRedactsInlineSignedURL() {
        let raw = #"download failed https://rr1---sn-abc.googlevideo.com/videoplayback?expire=1&signature=deadbeef id=abc"#
        let sanitized = SecurityHardening.sanitizeLogMessage(raw)
        XCTAssertFalse(sanitized.contains("signature=deadbeef"))
        XCTAssertFalse(sanitized.contains("expire=1"))
        XCTAssertTrue(sanitized.contains("?…"))
        XCTAssertTrue(sanitized.contains("id=abc"))
    }

    func testRedactedErrorOmitsUserInfoURLs() {
        let url = URL(string: "https://rr1---sn-abc.googlevideo.com/videoplayback?signature=secret")!
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorUnknown,
            userInfo: [NSURLErrorFailingURLErrorKey: url]
        )
        let redacted = SecurityHardening.redactedForLog(error)
        XCTAssertFalse(redacted.contains("signature"))
        XCTAssertFalse(redacted.contains("googlevideo"))
        XCTAssertTrue(redacted.contains("domain=\(NSURLErrorDomain)"))
    }

    func testSensitiveMediaURLDetection() {
        XCTAssertTrue(SecurityHardening.isSensitiveMediaURLString(
            "https://rr1---sn-abc.googlevideo.com/videoplayback?expire=1&ip=1.2.3.4"
        ))
        XCTAssertTrue(SecurityHardening.isSensitiveMediaURLString(
            "https://www.youtube.com/videoplayback?signature=abc"
        ))
        XCTAssertFalse(SecurityHardening.isSensitiveMediaURLString(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        ))
        XCTAssertFalse(SecurityHardening.isSensitiveMediaURLString(
            "https://example.com/clip.mp4"
        ))
    }
}
