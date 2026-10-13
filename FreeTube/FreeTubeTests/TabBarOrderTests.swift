import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
@MainActor
final class TabBarOrderTests: XCTestCase {
    func testDefaultOrderIsStable() {
        XCTAssertEqual(TabBarOrder.tabs(from: ""), [.feed, .library, .downloads, .settings])
    }

    func testStoredOrderIgnoresSearchDuplicatesAndUnknownTabs() {
        XCTAssertEqual(
            TabBarOrder.tabs(from: "downloads,search,feed,downloads,unknown"),
            [.downloads, .feed, .library, .settings]
        )
    }

    func testOrderRoundTrips() {
        let tabs: [RootView.Tab] = [.library, .downloads, .settings, .feed]
        XCTAssertEqual(TabBarOrder.tabs(from: TabBarOrder.rawValue(for: tabs)), tabs)
    }

    func testSettingsRemainsReachableWithoutLibrary() {
        XCTAssertEqual(
            TabBarOrder.visibleTabs(
                from: TabBarOrder.defaultValue,
                feed: false,
                library: false,
                downloads: false,
                search: false,
                settings: false
            ),
            [.settings]
        )
    }

    func testSearchKeepsItsTrailingSystemPosition() {
        XCTAssertEqual(
            TabBarOrder.visibleTabs(
                from: "settings,downloads,feed,library",
                feed: true,
                library: true,
                downloads: false,
                search: true,
                settings: true
            ),
            [.settings, .feed, .library, .search]
        )
    }
}
