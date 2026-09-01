import SwiftUI

@available(iOS 17.0, *)
struct CommentsSection: View {
    @State private var model: CommentsViewModel
    /// Expanded by default. The CommentsSection is only mounted when the player's lower panel is
    /// switched to `.comments`, so this is *not* a per-video-view load — it fires exactly once
    /// when the user moves away from the queue to look at comments, which is what they wanted.
    /// The chevron pill still lets them collapse the body if they need the room back.
    @State private var isExpanded = true

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
        // Mount-time load. Since `CommentsSection` only mounts when the panel toggles to
        // `.comments`, this fires the first time the user switches away from the queue, not on
        // every video view. Cheap re-mounts (same videoID) short-circuit because comments are
        // already cached on the view model.
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
