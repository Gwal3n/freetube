import SwiftUI

/// A group editor that keeps membership changes immediate while renames require explicit saving.
@available(iOS 17.0, *)
struct SubscriptionGroupMembersScreen: View {
    let groupID: UUID

    @State private var store = LocalSubscriptionGroupStore.shared
    @State private var subscriptions = LocalSubscriptionStore.shared
    @State private var draftName = ""
    @State private var showingAddChannels = false

    private var group: SubscriptionGroup? {
        store.groups.first(where: { $0.id == groupID })
    }

    private var canSaveName: Bool {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 60 && name != group?.name && !store.groups.contains {
            $0.id != groupID && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private var members: [LocalSubscription] {
        subscriptions.subscriptions.filter { group?.channelIDs.contains($0.id) == true }
    }

    var body: some View {
        List {
            Section("Name") {
                HStack {
                    TextField("Group name", text: $draftName)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                    if canSaveName {
                        Button("Save", action: saveName)
                    }
                }
            }

            Section("Channels") {
                if members.isEmpty {
                    ContentUnavailableView(
                        "No channels in this group",
                        systemImage: "person.2.slash",
                        description: Text("Add channels from your local subscriptions.")
                    )
                } else {
                    ForEach(members) { channel in
                        ChannelRow(channel: channel.channel)
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.setMember(channel.id, in: groupID, isMember: false)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                                .tint(.red)
                            }
                    }
                }
            }
        }
        .navigationTitle(group?.name ?? "Group")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingAddChannels) {
            SubscriptionGroupAddChannelsScreen(groupID: groupID)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddChannels = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add channels")
            }
        }
        .onAppear { draftName = group?.name ?? "" }
    }

    private func saveName() {
        guard canSaveName else { return }
        _ = store.rename(id: groupID, to: draftName)
        draftName = group?.name ?? ""
    }
}
