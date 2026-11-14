import SwiftUI

@available(iOS 17.0, *)
struct SponsorBlockWhitelistSettingsScreen: View {
    @AppStorage("sponsorBlockChannelWhitelistJSON") private var whitelistJSON = "[]"
    @State private var subscriptions = LocalSubscriptionStore.shared
    @State private var showingAddSheet = false

    private var whitelistedIDs: [String] {
        guard let data = whitelistJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids.sorted()
    }

    private var addableSubscriptions: [LocalSubscription] {
        let blocked = Set(whitelistedIDs)
        return subscriptions.subscriptions
            .filter { !blocked.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                if whitelistedIDs.isEmpty {
                    Text("Channels on this list skip SponsorBlock entirely.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(whitelistedIDs, id: \.self) { channelID in
                        whitelistRow(channelID)
                    }
                    .onDelete(perform: remove)
                }
            } footer: {
                Text("Useful for channels whose segments you never want applied.")
            }
        }
        .navigationTitle("Channel whitelist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(addableSubscriptions.isEmpty)
                .accessibilityLabel("Add channel")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                List(addableSubscriptions) { subscription in
                    Button {
                        add(subscription.id)
                        showingAddSheet = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(subscription.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(verbatim: subscription.id)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .navigationTitle("Add channel")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func whitelistRow(_ channelID: String) -> some View {
        let name = subscriptions.subscriptions.first { $0.id == channelID }?.name
        VStack(alignment: .leading, spacing: 2) {
            Text(name ?? channelID)
            if name != nil {
                Text(verbatim: channelID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .settingsSearchRow("Channel whitelist")
    }

    private func add(_ channelID: String) {
        var ids = Set(whitelistedIDs)
        ids.insert(channelID)
        save(Array(ids))
    }

    private func remove(at offsets: IndexSet) {
        var ids = whitelistedIDs
        ids.remove(atOffsets: offsets)
        save(ids)
    }

    private func save(_ ids: [String]) {
        let unique = Array(Set(ids.filter { !$0.isEmpty })).sorted()
        guard let data = try? JSONEncoder().encode(unique),
              let json = String(data: data, encoding: .utf8) else {
            whitelistJSON = "[]"
            return
        }
        whitelistJSON = json
    }
}
