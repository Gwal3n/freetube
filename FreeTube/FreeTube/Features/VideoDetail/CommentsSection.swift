import SwiftUI

@available(iOS 17.0, *)
struct CommentsSection: View {
    @State private var model: CommentsViewModel
    /// Permanently mounted below Up Next, but collapsed and unloaded by default so showing the
    /// header never brings the comment tree (or its network work) into play until the user asks.
    @State private var isExpanded = false

    init(videoID: String) {
        _model = State(wrappedValue: CommentsViewModel(videoID: videoID))
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            header

            if isExpanded {
                if model.isLoading && model.comments.isEmpty {
                    LoadingView()
                        .padding(.vertical, 12)
                } else {
                    ForEach(model.comments) { comment in
                        CommentRow(
                            comment: comment,
                            onLike: { Task { await model.toggleLike(comment) } },
                            onDislike: { Task { await model.toggleDislike(comment) } },
                            onReply: { /* TODO: present reply sheet */ },
                            onTranslate: { Task { await model.translate(comment) } }
                        )
                        if let translation = model.translations[comment.id] {
                            Text(translation)
                                .font(.footnote)
                                .padding(.horizontal)
                                .padding(.bottom, 4)
                        }
                    }
                    if model.isLoading {
                        LoadingView()
                    } else if model.continuationToken != nil {
                        Button {
                            Task { await model.loadMore() }
                        } label: {
                            Label("Load more comments", systemImage: "chevron.down")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
                    }
                }
            }
        }
        .errorToast(Bindable(model).errorState)
        // Covers state restoration where the section mounts expanded. The normal collapsed state
        // performs no request; the header button lazily loads on first expansion.
        .task {
            if isExpanded && model.comments.isEmpty && !model.isLoading {
                await model.load()
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            SectionHeader(title: "Comments")
            Spacer()
            Button {
                isExpanded.toggle()
                // Lazy-load on first expand. Subsequent toggles just hide/show what's already
                // loaded — no extra network calls.
                if isExpanded && model.comments.isEmpty && !model.isLoading {
                    Task { await model.load() }
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }
}
