import SwiftUI

@available(iOS 17.0, *)
struct LocalSubscriptionsScreen: View {
    @State private var store = LocalSubscriptionStore.shared
    @State private var showingClearConfirmation = false
    @State private var refreshError: String?
    @State private var isRefreshing = false
    @State private var searchText = ""
    private let channelService: any ChannelServicing = ChannelService()

    var body: some View {
        let groups = Dictionary(grouping: visibleSubscriptions) { subscription in
            sectionTitle(for: subscription.name)
        }
        let titles = groups.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        Group {
            if store.subscriptions.isEmpty {
                ContentUnavailableView(
                    "No local subscriptions",
                    systemImage: "person.2.slash",
                    description: Text(
                        "Subscribe from a channel page or import a YouTube subscriptions CSV in Settings."
                    )
                )
            } else if visibleSubscriptions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollViewReader { scrollProxy in
                    HStack(spacing: 0) {
                        List {
                            ForEach(titles, id: \.self) { title in
                                Section {
                                    ForEach(groups[title] ?? []) { subscription in
                                        NavigationLink {
                                            ChannelScreen(channelID: subscription.id)
                                        } label: {
                                            ChannelRow(channel: subscription.channel)
                                        }
                                        .mediaListRow()
                                    }
                                    .onDelete { offsets in
                                        let items = groups[title] ?? []
                                        for offset in offsets where items.indices.contains(offset) {
                                            store.remove(channelID: items[offset].id)
                                        }
                                    }
                                } header: {
                                    Text(verbatim: title)
                                }
                                .id(title)
                            }
                            if searchText.isEmpty {
                                Section {
                                    Button(role: .destructive) {
                                        showingClearConfirmation = true
                                    } label: {
                                        Label("Remove all subscriptions", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await refreshProfilePhotos()
                        }

                        if searchText.isEmpty, store.subscriptions.count > 10, titles.count > 1 {
                            SubscriptionSectionIndex(titles: titles) { title in
                                scrollProxy.scrollTo(title, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Local subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search subscriptions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    NotificationCenter.default.post(name: .freetubeOpenSubscriptionGroups, object: nil)
                } label: {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Subscription groups")
            }
        }
        .confirmationDialog(
            "Remove all local subscriptions?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) { store.removeAll() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Some photos weren’t refreshed", isPresented: Binding(
            get: { refreshError != nil },
            set: { if !$0 { refreshError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refreshError ?? "")
        }
    }

    private var visibleSubscriptions: [LocalSubscription] {
        guard !searchText.isEmpty else { return store.subscriptions }
        return store.subscriptions.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.id.localizedStandardContains(searchText)
        }
    }

    private func sectionTitle(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "#"
        }
        let title = String(first)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased(with: .current)
        return title.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
            ? title
            : "#"
    }

    /// Refresh in small batches: enough parallelism for a large imported list without launching
    /// hundreds of simultaneous YouTube browse requests. Successful channels are persisted as
    /// each batch completes, so partial progress survives if the screen is dismissed.
    private func refreshProfilePhotos() async {
        guard !isRefreshing else { return }
        let channelIDs = store.subscriptions.map(\.id)
        guard !channelIDs.isEmpty else { return }

        isRefreshing = true
        var failureCount = 0
        defer { isRefreshing = false }

        for start in stride(from: 0, to: channelIDs.count, by: 4) {
            let end = min(start + 4, channelIDs.count)
            let batch = Array(channelIDs[start..<end])
            let results = await withTaskGroup(of: Channel?.self) { group in
                for channelID in batch {
                    group.addTask {
                        try? await channelService.fetchChannelMetadata(id: channelID)
                    }
                }
                var channels: [Channel] = []
                for await channel in group {
                    if let channel { channels.append(channel) }
                }
                return channels
            }

            for channel in results { store.add(channel) }
            failureCount += batch.count - results.count
        }

        if failureCount > 0 {
            refreshError = failureCount == 1
                ? "One channel could not be refreshed. Your existing subscription was kept."
                : "\(failureCount) channels could not be refreshed. Your existing subscriptions were kept."
        }
    }
}
