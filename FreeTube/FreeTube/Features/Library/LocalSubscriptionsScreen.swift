import SwiftUI

@available(iOS 17.0, *)
struct LocalSubscriptionsScreen: View {
    @State private var store = LocalSubscriptionStore.shared
    @State private var showingClearConfirmation = false
    @State private var refreshError: String?
    @State private var isRefreshing = false
    @State private var activeIndexTitle: String?
    private let channelService: any ChannelServicing = ChannelService()

    var body: some View {
        let groups = Dictionary(grouping: store.subscriptions) { subscription in
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
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await refreshProfilePhotos()
                        }

                        if store.subscriptions.count > 10, titles.count > 1 {
                            sectionIndex(titles: titles, scrollProxy: scrollProxy)
                        }
                    }
                }
            }
        }
        .navigationTitle("Local subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.subscriptions.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear all", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
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

    private func sectionIndex(titles: [String], scrollProxy: ScrollViewProxy) -> some View {
        GeometryReader { geometry in
            let itemHeight = min(18, geometry.size.height / CGFloat(titles.count))
            let topInset = max(0, (geometry.size.height - itemHeight * CGFloat(titles.count)) / 2)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(titles, id: \.self) { title in
                    Button {
                        scrollProxy.scrollTo(title, anchor: .top)
                    } label: {
                        Text(verbatim: title)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: itemHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to \(title)")
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = (value.location.y - topInset) / max(itemHeight, 1)
                        let index = min(max(Int(position), 0), titles.count - 1)
                        let title = titles[index]
                        guard activeIndexTitle != title else { return }
                        activeIndexTitle = title
                        scrollProxy.scrollTo(title, anchor: .top)
                    }
                    .onEnded { _ in activeIndexTitle = nil }
            )
        }
        .frame(width: 26)
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
