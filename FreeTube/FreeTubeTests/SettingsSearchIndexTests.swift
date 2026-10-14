import XCTest
@testable import FreeTube

final class SettingsSearchIndexTests: XCTestCase {
    func testSearchFindsTopLevelAndNestedSettings() {
        let holdSpeed = SettingsSearchIndex.results(matching: String(localized: "Hold for speed"))
        XCTAssertTrue(holdSpeed.contains { $0.destination == .playback })

        let defaultSpeed = SettingsSearchIndex.results(matching: String(localized: "Default playback speed"))
        XCTAssertTrue(defaultSpeed.contains { $0.destination == .playbackSpeeds })

        let importSubscriptions = SettingsSearchIndex.results(matching: String(localized: "Import Subscriptions CSV"))
        XCTAssertTrue(importSubscriptions.contains { $0.destination == .importExport })

        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Double-tap seek"))
            .contains { $0.destination == .playback })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Resume after interruptions"))
            .contains { $0.destination == .playback })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Remember floating player placement"))
            .contains { $0.destination == .playback })
    }

    func testEmptySearchShowsSettingsIndex() {
        XCTAssertTrue(SettingsSearchIndex.results(matching: "  ").isEmpty)
    }
}
