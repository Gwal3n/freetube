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
    @State private var editedTabs: [RootView.Tab]?

    private var tabs: [RootView.Tab] {
        editedTabs ?? TabBarOrder.tabs(from: tabBarOrderRaw)
    }

    var body: some View {
        List {
            Section {
                Toggle("Show tab names", isOn: $showTabBarLabels)
            } footer: {
                Text("Icons remain accessible by name when labels are hidden.")
            }

            Section {
                ForEach(tabs, id: \.self) { tab in
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
        .onChange(of: tabBarOrderRaw) { _, rawValue in
            let storedTabs = TabBarOrder.tabs(from: rawValue)
            if editedTabs != storedTabs { editedTabs = storedTabs }
        }
    }

    private func moveTabs(from source: IndexSet, to destination: Int) {
        var reordered = tabs
        reordered.move(fromOffsets: source, toOffset: min(destination, reordered.count))
        editedTabs = reordered
        tabBarOrderRaw = TabBarOrder.rawValue(for: reordered)
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
