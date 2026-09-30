import SwiftUI

import Kingfisher

@available(iOS 17.0, *)
struct AddVideoToPlaylistSheet: View {
    let playlistID: String
    @Environment(\.dismiss) private var dismiss
    @State private var model = AddVideoToPlaylistViewModel()
    @State private var showingLinkEntry = false
    @FocusState private var linkFocused: Bool

    var body: some View {
        NavigationStack {
            searchResults
                .navigationTitle("Add Video")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(model.isAdding)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingLinkEntry = true
                        } label: {
                            Image(systemName: "link")
                        }
                        .accessibilityLabel("Add by Link or ID")
                        .disabled(model.isAdding)
                    }
                }
                .navigationDestination(isPresented: $showingLinkEntry) {
                    linkEntry
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isAdding)
        .errorToast(Bindable(model).errorState)
    }

    private var searchResults: some View {
        List {
            if model.isSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if model.searchFailed {
                ContentUnavailableView {
                    Label("Search Unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Please try again.")
                } actions: {
                    Button("Retry") { Task { await model.search() } }
                }
                .listRowBackground(Color.clear)
            } else if model.searchedQuery == nil {
                ContentUnavailableView(
                    "Find a Video",
                    systemImage: "magnifyingglass",
                    description: Text("Search by title or channel, then tap a video to add it.")
                )
                .listRowBackground(Color.clear)
            } else if model.videos.isEmpty {
                ContentUnavailableView.search(text: model.searchedQuery ?? "")
                    .listRowBackground(Color.clear)
                if model.continuationToken != nil {
                    loadMoreButton
                }
            } else {
                ForEach(model.videos) { video in
                    Button {
                        Task { await add(video) }
                    } label: {
                        videoRow(video)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isAdding)
                }
                if model.continuationToken != nil {
                    loadMoreButton
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .searchable(
            text: Bindable(model).query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search videos"
        )
        .onSubmit(of: .search) { Task { await model.search() } }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await model.loadMore() }
        } label: {
            HStack {
                Spacer()
                if model.isLoadingMore {
                    ProgressView()
                } else {
                    Text(model.paginationFailed ? "Retry Loading" : "Load More")
                }
                Spacer()
            }
        }
        .disabled(model.isLoadingMore || model.isAdding)
    }

    private func videoRow(_ video: Video) -> some View {
        HStack(spacing: 12) {
            KFImage(video.thumbnailURL)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 56)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(video.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
        .accessibilityLabel("Add \(video.title) to playlist")
    }

    private var linkEntry: some View {
        Form {
            Section {
                TextField("YouTube link or video ID", text: Bindable(model).link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($linkFocused)
                    .onSubmit { Task { await addLink() } }
            } footer: {
                Text("Paste a video link or ID. The video information is saved locally with this playlist.")
            }
        }
        .navigationTitle("Add by Link")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await addLink() }
                } label: {
                    if model.isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .disabled(model.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAdding)
            }
        }
        .task { linkFocused = true }
    }

    private func add(_ video: Video) async {
        if await model.add(video: video, to: playlistID) { dismiss() }
    }

    private func addLink() async {
        if await model.addLink(to: playlistID) { dismiss() }
    }
}
