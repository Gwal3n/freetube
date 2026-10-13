import SwiftUI

/// Keeps the system tab bar while letting people arrange its ordinary destinations.
@available(iOS 17.0, *)
struct TabBarSettingsScreen: View {
    @AppStorage("tabBarOrder") private var tabBarOrderRaw = TabBarOrder.defaultValue
    @AppStorage("showTabBarLabels") private var showTabBarLabels = true
    @AppStorage("showSubscriptionFeedTab") private var showFeedTab = true
    @AppStorage("showLibraryTab") private var showLibraryTab = true
    @AppStorage("showDownloadsTab") private var showDownloadsTab = true
    @AppStorage("showSearchTab") private var showSearchTab = true
    @AppStorage("showSettingsTab") private var showSettingsTab = false

    var body: some View {
        List {
            Section {
                Toggle("Show tab names", isOn: $showTabBarLabels)
            } footer: {
                Text("Icons remain accessible by name when labels are hidden.")
            }

            Section {
                ForEach(TabBarOrder.tabs(from: tabBarOrderRaw), id: \.self) { tab in
                    Toggle(isOn: visibility(for: tab)) {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                    .disabled(tab == .settings && !showLibraryTab)
                }
                .onMove(perform: moveTabs)

                Toggle(isOn: $showSearchTab) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .moveDisabled(true)
            } header: {
                Text("Tab order")
            } footer: {
                Text("Drag the handles to reorder tabs. Search keeps its native system position. Settings remains available when Library is hidden.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tab Bar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moveTabs(from source: IndexSet, to destination: Int) {
        var tabs = TabBarOrder.tabs(from: tabBarOrderRaw)
        tabs.move(fromOffsets: source, toOffset: min(destination, tabs.count))
        tabBarOrderRaw = TabBarOrder.rawValue(for: tabs)
    }

    private func visibility(for tab: RootView.Tab) -> Binding<Bool> {
        switch tab {
        case .feed: $showFeedTab
        case .library: Binding(
            get: { showLibraryTab },
            set: { visible in
                if !visible { showSettingsTab = true }
                showLibraryTab = visible
            }
        )
        case .downloads: $showDownloadsTab
        case .settings: Binding(
            get: { showSettingsTab || !showLibraryTab },
            set: { showSettingsTab = $0 }
        )
        case .search: $showSearchTab
        }
    }
}
