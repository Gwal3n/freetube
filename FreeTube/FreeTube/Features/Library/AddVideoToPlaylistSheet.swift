import SwiftUI

import Kingfisher

@available(iOS 17.0, *)
struct AddVideoToPlaylistSheet: View {
    let playlistID: String
    @Environment(\.dismiss) private var dismiss
    @State private var model = AddVideoToPlaylistViewModel()

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
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isAdding)
        .errorToast(Bindable(model).errorState)
    }

    private var searchResults: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search videos or paste a link", text: Bindable(model).query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .disabled(model.isAdding)
                    .onSubmit { Task { await submit() } }
                if model.isAdding {
                    ProgressView().controlSize(.small)
                } else if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

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
                        description: Text("Search by title or channel, or paste a YouTube link or video ID.")
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
        }
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

    private func add(_ video: Video) async {
        if await model.add(video: video, to: playlistID) { dismiss() }
    }

    private func submit() async {
        if await model.submit(to: playlistID) { dismiss() }
    }
}
