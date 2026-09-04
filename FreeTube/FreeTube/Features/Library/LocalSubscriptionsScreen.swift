import SwiftUI
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct LocalSubscriptionsScreen: View {
    @State private var store = LocalSubscriptionStore.shared
    @State private var showingImporter = false
    @State private var showingClearConfirmation = false
    @State private var importMessage: String?
    @State private var importError: String?

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
}
