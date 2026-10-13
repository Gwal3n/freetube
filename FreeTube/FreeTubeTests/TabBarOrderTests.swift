import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
@MainActor
final class TabBarOrderTests: XCTestCase {
    func testDefaultOrderIsStable() {
        XCTAssertEqual(TabBarOrder.tabs(from: ""), [.feed, .library, .downloads])
    }

    func testStoredOrderIgnoresSearchDuplicatesAndUnknownTabs() {
        XCTAssertEqual(
            TabBarOrder.tabs(from: "downloads,search,feed,downloads,unknown"),
            [.downloads, .feed, .library]
        )
    }

    func testOrderRoundTrips() {
        let tabs: [RootView.Tab] = [.library, .downloads, .feed]
        XCTAssertEqual(TabBarOrder.tabs(from: TabBarOrder.rawValue(for: tabs)), tabs)
    }
}
