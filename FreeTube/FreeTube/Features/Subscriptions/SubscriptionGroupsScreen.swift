import SwiftUI

/// Native, device-local management for the groups used by the subscription feed.
@available(iOS 17.0, *)
struct SubscriptionGroupsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = LocalSubscriptionGroupStore.shared
    @State private var name = ""
    @State private var selectedGroup: SubscriptionGroup?
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
                                .foregroundStyle(canAdd ? Color.white : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAdd)
                        .accessibilityLabel("Create group")
                    }
                } footer: {
                    Text("A channel can belong to more than one group. Groups are saved only on this device.")
                }

                if !store.groups.isEmpty {
                    Section("Groups") {
                        ForEach(store.groups) { group in
                            Button {
                                selectedGroup = group
                            } label: {
                                HStack {
                                    Text(group.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(group.channelIDs.count, format: .number)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
            .navigationDestination(item: $selectedGroup) { group in
                SubscriptionGroupMembersScreen(groupID: group.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.white)
    }

    private func addGroup() {
        guard store.add(name: name) else { return }
        name = ""
        nameFocused = false
    }
}
