import SwiftUI

/// A lightweight local group picker for a channel; no network request is made.
@available(iOS 17.0, *)
struct ChannelGroupPickerSheet: View {
    let channel: Channel
    let onSubscribe: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groups = LocalSubscriptionGroupStore.shared
    @State private var subscriptions = LocalSubscriptionStore.shared
    @State private var newGroupName = ""

    private var canCreateGroup: Bool {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 60 && !groups.groups.contains {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !subscriptions.contains(channel.id) {
                    Section {
                        Button {
                            Task { await onSubscribe() }
                        } label: {
                            Label("Subscribe to add to groups", systemImage: "person.badge.plus")
                                .foregroundStyle(.primary)
                        }
                    } footer: {
                        Text("Groups organize your local subscriptions. Subscribing does not use a YouTube account.")
                    }
                } else {
                    groupSections
                }
            }
            .navigationTitle("Add to group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var groupSections: some View {
        Section {
            ForEach(groups.groups) { group in
                let isMember = group.channelIDs.contains(channel.id)
                Button {
                    groups.setMember(channel.id, in: group.id, isMember: !isMember)
                } label: {
                    HStack {
                        Text(group.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if isMember {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isMember ? .isSelected : [])
            }
            if groups.groups.isEmpty {
                Text("Create a group to organize this channel in your feed.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Groups")
        } footer: {
            Text("Changes are saved on this device and take effect in the Feed immediately.")
        }

        Section("New group") {
            HStack {
                TextField("Group name", text: $newGroupName)
                    .submitLabel(.done)
                    .onSubmit(createGroup)
                Button(action: createGroup) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(canCreateGroup ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canCreateGroup)
                .accessibilityLabel("Create and add to group")
            }
        }
    }

    private func createGroup() {
        guard groups.add(name: newGroupName),
              let group = groups.groups.last else { return }
        groups.setMember(channel.id, in: group.id, isMember: true)
        newGroupName = ""
    }
}
