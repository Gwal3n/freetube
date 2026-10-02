import SwiftUI

/// Selects local subscriptions to add without showing existing group members in the picker.
@available(iOS 17.0, *)
struct SubscriptionGroupAddChannelsScreen: View {
    let groupID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var groups = LocalSubscriptionGroupStore.shared
    @State private var subscriptions = LocalSubscriptionStore.shared
    @State private var searchText = ""
    @State private var selectedIDs: Set<String> = []

    private var availableChannels: [LocalSubscription] {
        let memberIDs = groups.groups.first(where: { $0.id == groupID })?.channelIDs ?? []
        return subscriptions.subscriptions.filter { channel in
            !memberIDs.contains(channel.id)
                && (searchText.isEmpty || channel.name.localizedStandardContains(searchText))
        }
    }

    var body: some View {
        List {
            if availableChannels.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "All subscriptions added" : "No matching channels",
                    systemImage: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass"
                )
            } else {
                ForEach(availableChannels) { channel in
                    Button {
                        if !selectedIDs.insert(channel.id).inserted {
                            selectedIDs.remove(channel.id)
                        }
                    } label: {
                        ChannelRow(
                            channel: channel.channel,
                            trailing: AnyView(
                                Image(systemName: selectedIDs.contains(channel.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIDs.contains(channel.id) ? Color.white : Color.secondary)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedIDs.contains(channel.id) ? .isSelected : [])
                }
            }
        }
        .navigationTitle("Add channels")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search subscriptions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add \(selectedIDs.count)") {
                    for channelID in selectedIDs {
                        groups.setMember(channelID, in: groupID, isMember: true)
                    }
                    dismiss()
                }
                .disabled(selectedIDs.isEmpty)
            }
        }
    }
}
