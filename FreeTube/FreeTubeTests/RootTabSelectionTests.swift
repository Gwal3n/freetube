import XCTest
@testable import FreeTube

@MainActor
final class RootTabSelectionTests: XCTestCase {
    func testDiagnosticLaunchStartsOnLibraryAndReappearanceKeepsLiveSelection() {
        let state = RootTabSelection()
        state.start(showsFeed: true)
        XCTAssertEqual(state.selected, .library)
        state.select(.downloads, showsFeed: true)
        state.start(showsFeed: true)
        XCTAssertEqual(state.selected, .downloads)
    }

    func testFeedVisibilityDoesNotMoveOtherTabs() {
        for tab in [RootView.Tab.library, .downloads, .search] {
            let state = RootTabSelection()
            state.select(tab, showsFeed: true)
            state.updateFeedVisibility(false)
            XCTAssertEqual(state.selected, tab)
            state.updateFeedVisibility(true)
            XCTAssertEqual(state.selected, tab)
        }
    }

    func testDiagnosticLaunchWithHiddenFeedKeepsLibraryAvailable() {
        let state = RootTabSelection()
        state.start(showsFeed: false)
        XCTAssertEqual(state.selected, .library)
        state.select(.library, showsFeed: false)
        XCTAssertEqual(state.selected, .library)
    }

    func testRepeatedDownloadsSelectionStaysInDownloads() {
        let state = RootTabSelection()
        state.start(showsFeed: true)
        state.select(.downloads, showsFeed: true)
        XCTAssertEqual(state.selected, .downloads)
    }
}
