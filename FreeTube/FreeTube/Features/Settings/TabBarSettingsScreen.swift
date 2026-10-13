import SwiftUI

/// Keeps the system tab bar while letting people arrange its ordinary destinations.
@available(iOS 17.0, *)
struct TabBarSettingsScreen: View {
    @AppStorage("tabBarOrder") private var tabBarOrderRaw = TabBarOrder.defaultValue
    @AppStorage("showTabBarLabels") private var showTabBarLabels = true

    var body: some View {
        List {
            Section {
                Toggle("Show tab names", isOn: $showTabBarLabels)
            } footer: {
                Text("Icons remain accessible by name when labels are hidden.")
            }

            Section {
                ForEach(TabBarOrder.tabs(from: tabBarOrderRaw), id: \.self) { tab in
                    Label(tab.title, systemImage: tab.symbol)
                        .foregroundStyle(.primary)
                }
                .onMove(perform: moveTabs)

                Label("Search", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .moveDisabled(true)
            } header: {
                Text("Tab order")
            } footer: {
                Text("Drag the handles to reorder tabs. Search keeps its native system position.")
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
}
