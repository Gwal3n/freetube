import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
final class PlayerItemReadinessGateTests: XCTestCase {
    func testItemErrorDescriptionNeverIncludesSignedURL() {
        let error = NSError(
            domain: "AVFoundationErrorDomain",
            code: -123,
            userInfo: [NSURLErrorFailingURLStringErrorKey: "https://example.invalid/play?sig=secret"]
        )

        XCTAssertEqual(
            PlayerItemReadinessGate.describe(itemError: error),
            "domain=AVFoundationErrorDomain code=-123"
        )
    }
}
