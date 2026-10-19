import SwiftUI
import XCTest
@testable import FreeTube

@MainActor
final class SponsorBlockColorPaletteTests: XCTestCase {
    func testCustomCategoryColorRoundTripsAndResetsToDefault() {
        var palette = SponsorBlockColorPalette(json: "{}")
        XCTAssertFalse(palette.usesCustomColor(for: .sponsor))

        palette.setCustomColorEnabled(true, for: .sponsor)
        palette.setColor(Color(red: 1, green: 0, blue: 0), for: .sponsor)
        let restored = SponsorBlockColorPalette(json: palette.json)
        XCTAssertTrue(restored.usesCustomColor(for: .sponsor))
        XCTAssertEqual(WatchIndicatorStyle.hex(color: restored.color(for: .sponsor)), "#FF0000")
        XCTAssertFalse(restored.usesCustomColor(for: .intro))

        palette.setCustomColorEnabled(false, for: .sponsor)
        XCTAssertFalse(SponsorBlockColorPalette(json: palette.json).usesCustomColor(for: .sponsor))
        palette.setCustomColorEnabled(true, for: .sponsor)
        XCTAssertEqual(WatchIndicatorStyle.hex(color: palette.color(for: .sponsor)), "#FF0000")
    }

    func testInvalidSavedColorsFallBackToDefaults() {
        let palette = SponsorBlockColorPalette(json: #"{"sponsor":{"usesCustomColor":true,"hex":"not-a-color"}}"#)
        XCTAssertFalse(palette.usesCustomColor(for: .sponsor))
        XCTAssertEqual(WatchIndicatorStyle.hex(color: palette.color(for: .sponsor)),
                       WatchIndicatorStyle.hex(color: SponsorBlockColorPalette.defaultColor(for: .sponsor)))
    }
}
