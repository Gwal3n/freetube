import XCTest
@testable import FreeTube

final class SettingsSearchIndexTests: XCTestCase {
    func testSearchFindsTopLevelAndNestedSettings() {
        let holdSpeed = SettingsSearchIndex.results(matching: String(localized: "Hold to speed up"))
        XCTAssertTrue(holdSpeed.contains { $0.destination == .playback })

        let defaultSpeed = SettingsSearchIndex.results(matching: String(localized: "Default playback speed"))
        XCTAssertTrue(defaultSpeed.contains { $0.destination == .playbackSpeeds })

        let importSubscriptions = SettingsSearchIndex.results(matching: String(localized: "Import Subscriptions CSV"))
        XCTAssertTrue(importSubscriptions.contains { $0.destination == .importExport })

        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Double-tap seek"))
            .contains { $0.destination == .player })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Resume after interruptions"))
            .contains { $0.destination == .playback })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Remember mini player position"))
            .contains { $0.destination == .player })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Show watch progress"))
            .contains { $0.destination == .browsing })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Prefetch details and comments"))
            .contains { $0.destination == .cache })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Accent color"))
            .contains { $0.destination == .appearance })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Left side"))
            .contains { $0.destination == .player })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Clear all temporary caches"))
            .contains { $0.destination == .cache })
        XCTAssertTrue(SettingsSearchIndex.results(matching: String(localized: "Storage used"))
            .contains { $0.destination == .cache })
    }

    func testSearchResultsFocusTheOwningControl() {
        let light = SettingsSearchIndex.results(matching: String(localized: "Light"))
            .first { $0.destination == .appearance && $0.displayTitle == String(localized: "Light") }
        XCTAssertEqual(light?.focusTitle, String(localized: "Appearance"))

        let importPage = SettingsSearchIndex.results(matching: String(localized: "Import & Export"))
            .first { $0.destination == .importExport }
        XCTAssertEqual(importPage?.focusTitle, String(localized: "Export All Settings and Data"))
    }

    func testEmptySearchShowsSettingsIndex() {
        XCTAssertTrue(SettingsSearchIndex.results(matching: "  ").isEmpty)
    }
}
