import SwiftUI

/// A group editor that keeps membership changes immediate while renames require explicit saving.
@available(iOS 17.0, *)
struct SubscriptionGroupMembersScreen: View {
    let groupID: UUID

    @State private var store = LocalSubscriptionGroupStore.shared
    @State private var subscriptions = LocalSubscriptionStore.shared
    @State private var draftName = ""

    private var group: SubscriptionGroup? {
        store.groups.first(where: { $0.id == groupID })
    }

    private var canSaveName: Bool {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 60 && name != group?.name && !store.groups.contains {
            $0.id != groupID && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
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
                if subscriptions.subscriptions.isEmpty {
                    ContentUnavailableView("No subscriptions", systemImage: "person.2.slash")
                } else {
                    ForEach(subscriptions.subscriptions) { channel in
                        let isMember = group?.channelIDs.contains(channel.id) ?? false
                        Button {
                            store.setMember(channel.id, in: groupID, isMember: !isMember)
                        } label: {
                            HStack {
                                Text(channel.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isMember {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(isMember ? .isSelected : [])
                    }
                }
            }
        }
        .navigationTitle(group?.name ?? "Group")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draftName = group?.name ?? "" }
    }

    private func saveName() {
        guard canSaveName else { return }
        _ = store.rename(id: groupID, to: draftName)
        draftName = group?.name ?? ""
    }
}
