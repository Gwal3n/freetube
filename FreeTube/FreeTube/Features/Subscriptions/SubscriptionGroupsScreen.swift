import SwiftUI

/// Native, device-local management for the groups used by the subscription feed.
@available(iOS 17.0, *)
struct SubscriptionGroupsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = LocalSubscriptionGroupStore.shared
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var canAdd: Bool {
        let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !candidate.isEmpty && candidate.count <= 60 && !store.groups.contains {
            $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New group", text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(addGroup)
                        Button(action: addGroup) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(!canAdd)
                        .accessibilityLabel("Create group")
                    }
                } footer: {
                    Text("A channel can belong to more than one group. Groups are saved only on this device.")
                }

                if !store.groups.isEmpty {
                    Section("Groups") {
                        ForEach(store.groups) { group in
                            NavigationLink {
                                SubscriptionGroupMembersScreen(groupID: group.id)
                            } label: {
                                HStack {
                                    Text(group.name)
                                    Spacer()
                                    Text(group.channelIDs.count, format: .number)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets.sorted(by: >) where store.groups.indices.contains(index) {
                                store.remove(id: store.groups[index].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Subscription groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addGroup() {
        guard store.add(name: name) else { return }
        name = ""
        nameFocused = false
    }
}
