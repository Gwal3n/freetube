import SwiftUI

@available(iOS 17.0, *)
struct CommentsSection: View {
    @State private var model: CommentsViewModel
    /// Permanently mounted below Up Next, but collapsed and unloaded by default so showing the
    /// header never brings the comment tree (or its network work) into play until the user asks.
    @State private var isExpanded = false
    @State private var expandedReplyCommentIDs: Set<String> = []

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
                        commentThread(comment)
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
        Button {
            isExpanded.toggle()
            if isExpanded && model.comments.isEmpty && !model.isLoading {
                Task { await model.load() }
            }
        } label: {
            HStack {
                SectionHeader(title: "Comments")
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func commentThread(_ comment: Comment) -> some View {
        CommentRow(
            comment: comment,
            onLike: { Task { await model.toggleLike(comment) } }
        )

        if comment.replyCount > 0, comment.replyContinuationToken != nil {
            Button {
                if expandedReplyCommentIDs.contains(comment.id) {
                    expandedReplyCommentIDs.remove(comment.id)
                } else {
                    expandedReplyCommentIDs.insert(comment.id)
                    Task { await model.loadReplies(for: comment) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expandedReplyCommentIDs.contains(comment.id) ? "chevron.up" : "chevron.down")
                    Text(expandedReplyCommentIDs.contains(comment.id) ? "Hide replies" : "View \(comment.replyCount) replies")
                }
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .padding(.leading, 16)

            if expandedReplyCommentIDs.contains(comment.id) {
                if model.loadingReplyCommentIDs.contains(comment.id), model.repliesByCommentID[comment.id] == nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 32)
                } else {
                    ForEach(model.repliesByCommentID[comment.id] ?? []) { reply in
                        CommentRow(
                            comment: reply,
                            onLike: { Task { await model.toggleLike(reply) } }
                        )
                        .padding(.leading, 20)
                    }

                    if model.loadingReplyCommentIDs.contains(comment.id) {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 32)
                    } else if model.replyContinuationTokens[comment.id] != nil {
                        Button("Load more replies") {
                            Task { await model.loadMoreReplies(for: comment) }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .padding(.leading, 32)
                    }
                }
            }
        }
    }
}
