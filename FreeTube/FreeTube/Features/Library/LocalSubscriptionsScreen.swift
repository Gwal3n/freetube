import SwiftUI
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct LocalSubscriptionsScreen: View {
    @State private var store = LocalSubscriptionStore.shared
    @State private var showingImporter = false
    @State private var showingClearConfirmation = false
    @State private var importMessage: String?
    @State private var importError: String?
    @State private var refreshError: String?
    @State private var isRefreshing = false
    private let channelService: any ChannelServicing = ChannelService()

    var body: some View {
        Group {
            if store.subscriptions.isEmpty {
                EmptyStateView(
                    systemImage: "person.2.slash",
                    title: "No local subscriptions",
                    message: "Subscribe from a channel page or import a YouTube subscriptions CSV."
                )
            } else {
                List {
                    ForEach(store.subscriptions) { subscription in
                        NavigationLink {
                            ChannelScreen(channelID: subscription.id)
                        } label: {
                            ChannelRow(channel: subscription.channel)
                        }
                    }
                    .onDelete(perform: store.remove)
                }
                .listStyle(.plain)
                .refreshable {
                    await refreshProfilePhotos()
                }
            }
        }
        .navigationTitle("Local subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import subscriptions", systemImage: "square.and.arrow.down")
                    }
                    if !store.subscriptions.isEmpty {
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear all", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importFile(result)
        }
        .confirmationDialog(
            "Remove all local subscriptions?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) { store.removeAll() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Import complete", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .alert("Couldn’t import subscriptions", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
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

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let count = try store.importCSV(data: Data(contentsOf: url))
            importMessage = "Imported \(count) \(count == 1 ? "channel" : "channels")."
        } catch {
            importError = error.localizedDescription
        }
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
