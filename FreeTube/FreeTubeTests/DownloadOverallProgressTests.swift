import XCTest
@testable import FreeTube

final class DownloadOverallProgressTests: XCTestCase {
    func testVideoAndAudioShareOneProgressRange() {
        var progress = DownloadOverallProgress()
        XCTAssertEqual(progress.update(1, phase: "video"), 0.8, accuracy: 0.001)
        XCTAssertEqual(progress.update(0, phase: "audio"), 0.8, accuracy: 0.001)
        XCTAssertEqual(progress.update(1, phase: "audio"), 0.95, accuracy: 0.001)
        XCTAssertEqual(progress.update(0, phase: "muxing"), 0.95, accuracy: 0.001)
        XCTAssertLessThan(progress.update(1, phase: "muxing"), 1)
    }

    func testWholeTransferAndRetriesNeverRegressOrPrematurelyFinish() {
        var progress = DownloadOverallProgress()
        XCTAssertEqual(progress.update(1, phase: "stream"), 0.95, accuracy: 0.001)
        XCTAssertEqual(progress.update(0, phase: "stream"), 0.95, accuracy: 0.001)
        XCTAssertLessThan(progress.value, 1)
    }

    func testAudioOnlyStartsAtZeroAndInvalidSamplesAreSafe() {
        var progress = DownloadOverallProgress()
        XCTAssertEqual(progress.update(0, phase: "audio"), 0)
        XCTAssertEqual(progress.update(.nan, phase: "audio"), 0)
        XCTAssertEqual(progress.update(-1, phase: "audio"), 0)
        XCTAssertEqual(progress.update(2, phase: "audio"), 0.95, accuracy: 0.001)
    }
}
