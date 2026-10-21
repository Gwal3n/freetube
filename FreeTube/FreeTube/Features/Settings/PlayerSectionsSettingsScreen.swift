import SwiftUI

/// Native reorder list for the independently collapsible player sections.
@available(iOS 17.0, *)
struct PlayerSectionsSettingsScreen: View {
    @AppStorage("playerPanelSectionOrder") private var storedOrder = PlayerPanelSection.defaultOrder

    private var sections: [PlayerPanelSection] {
        PlayerPanelSection.ordered(from: storedOrder)
    }

    var body: some View {
        List {
            Section {
                ForEach(sections) { section in
                    Label(section.title, systemImage: section.symbol)
                        .foregroundStyle(.primary)
                }
                .onMove { offsets, destination in
                    var reordered = sections
                    reordered.move(fromOffsets: offsets, toOffset: destination)
                    storedOrder = PlayerPanelSection.storedValue(for: reordered)
                }
            } footer: {
                Text("Hidden sections keep their position and reappear here when available.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Rearrange sections")
        .navigationBarTitleDisplayMode(.inline)
    }
}
