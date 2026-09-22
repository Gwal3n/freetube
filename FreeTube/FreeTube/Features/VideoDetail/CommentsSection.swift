import SwiftUI

@available(iOS 17.0, *)
struct CommentsSection: View {
    let countText: String?
    @State private var model: CommentsViewModel
    /// Permanently mounted below Up Next, but collapsed and unloaded by default so showing the
    /// header never brings the comment tree (or its network work) into play until the user asks.
    @State private var isExpanded = false
    @State private var expandedReplyCommentIDs: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("showFeaturedCommentPreview") private var showsFeaturedCommentPreview = false

    init(videoID: String, countText: String? = nil) {
        self.countText = countText
        _model = State(wrappedValue: CommentsViewModel(videoID: videoID))
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            header

            if showsFeaturedCommentPreview,
               !isExpanded,
               let teaserText = model.teaserText,
               !teaserText.isEmpty {
                Button {
                    expandComments()
                } label: {
                    Text(teaserText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityHint("Opens comments")
                .transition(.opacity)
            }

            if isExpanded {
                Group {
                    if model.isLoading && model.comments.isEmpty {
                        CommentListPlaceholder()
                    } else if model.commentsDisabled {
                        ContentUnavailableView(
                            "Comments disabled",
                            systemImage: "text.bubble",
                            description: Text("Comments are unavailable for this video.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(model.commentsForDisplay) { comment in
                            commentThread(comment)
                        }
                        if model.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .accessibilityLabel("Loading more comments")
                        } else if model.continuationToken != nil {
                            // A quiet pagination sentinel keeps comments moving as the user
                            // reaches the end without introducing a non-native action row.
                            Color.clear
                                .frame(height: 24)
                                .contentShape(Rectangle())
                                .onAppear {
                                    Task { await model.loadMore() }
                                }
                                .accessibilityHidden(true)
                        }
                    }
                }
                // Let the section reveal by changing its own height. A top-edge move starts the
                // rows behind the heading and briefly paints them through the label on first open.
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : InterfaceMotion.content, value: isExpanded)
        .animation(reduceMotion ? nil : InterfaceMotion.content, value: model.teaserText)
        .errorToast(Bindable(model).errorState)
        // Covers state restoration where the section mounts expanded. Collapsed sections remain
        // unloaded unless the user explicitly enables the featured-comment preview.
        .task(id: showsFeaturedCommentPreview) {
            if showsFeaturedCommentPreview {
                await model.loadTeaser()
            } else if isExpanded, model.comments.isEmpty, !model.isLoading {
                await model.load()
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 4) {
            Button {
                toggleComments()
            } label: {
                PlayerSectionHeading(
                    title: "Comments",
                    detail: normalizedCountText,
                    isExpanded: isExpanded,
                    showsDisclosureIndicator: false
                )
            }
            .buttonStyle(ResponsiveButtonStyle())

            if model.sortingModes.count > 1 {
                Menu {
                    ForEach(model.sortingModes) { mode in
                        Button {
                            if !isExpanded {
                                withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                                    isExpanded = true
                                }
                            }
                            expandedReplyCommentIDs.removeAll()
                            Task { await model.selectSortingMode(mode) }
                        } label: {
                            if mode.isSelected {
                                Label(mode.label, systemImage: "checkmark")
                            } else {
                                Text(mode.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                        .contentShape(Circle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .disabled(model.isLoading)
                .accessibilityLabel("Sort comments")
                .accessibilityValue(selectedSortingModeLabel)
            }

            Button {
                toggleComments()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .contentShape(Circle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel(isExpanded ? "Collapse comments" : "Expand comments")
        }
        .padding(.horizontal)
    }

    private var selectedSortingModeLabel: String {
        model.sortingModes.first(where: \.isSelected)?.label ?? ""
    }

    private var normalizedCountText: String? {
        guard let count = countText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !count.isEmpty else { return nil }
        return count
    }

    @ViewBuilder
    private func commentThread(_ comment: Comment) -> some View {
        CommentRow(
            comment: comment,
            repliesTitle: comment.replyCount > 0 && comment.replyContinuationToken != nil
                ? (expandedReplyCommentIDs.contains(comment.id)
                    ? "Hide replies"
                    : "View \(comment.replyCount) replies")
                : nil,
            repliesExpanded: expandedReplyCommentIDs.contains(comment.id),
            onToggleReplies: comment.replyCount > 0 && comment.replyContinuationToken != nil
                ? { toggleReplies(for: comment) }
                : nil
        )

        if comment.replyCount > 0, comment.replyContinuationToken != nil {
            if expandedReplyCommentIDs.contains(comment.id) {
                Group {
                    if model.loadingReplyCommentIDs.contains(comment.id), model.repliesByCommentID[comment.id] == nil {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 32)
                    } else {
                        let replies = model.repliesByCommentID[comment.id] ?? []
                        ForEach(orderedReplies(parent: comment, replies: replies)) { item in
                            HStack(alignment: .top, spacing: 8) {
                                HStack(spacing: 5) {
                                    ForEach(0..<item.depth, id: \.self) { _ in
                                        Capsule()
                                            .fill(Color.secondary.opacity(0.20))
                                            .frame(width: 2)
                                    }
                                }
                                CommentRow(comment: item.comment)
                            }
                            .padding(.leading, 20)
                        }

                        if model.loadingReplyCommentIDs.contains(comment.id) {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 32)
                        } else if model.replyContinuationTokens[comment.id] != nil {
                            Button {
                                Task { await model.loadMoreReplies(for: comment) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.down")
                                    Text("Load more replies")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .padding(.leading, 32)
                        }
                    }
                }
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : InterfaceMotion.content,
                    value: model.repliesByCommentID[comment.id]?.count ?? 0
                )
            }
        }
    }

    private func toggleReplies(for comment: Comment) {
        withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
            if expandedReplyCommentIDs.contains(comment.id) {
                expandedReplyCommentIDs.remove(comment.id)
            } else {
                expandedReplyCommentIDs.insert(comment.id)
                Task { await model.loadReplies(for: comment) }
            }
        }
    }

    private struct PresentedReply: Identifiable {
        let comment: Comment
        let depth: Int
        var id: String { comment.id }
    }

    /// Reconstruct a conservative tree from leading mentions, then emit every child directly
    /// beneath its parent. The endpoint itself supplies only a flat reply array.
    private func orderedReplies(parent: Comment, replies: [Comment]) -> [PresentedReply] {
        let rootID = parent.id
        var latestCommentIDByAuthor = [normalizedAuthor(parent.authorName): rootID]
        var children: [String: [Comment]] = [:]

        for reply in replies {
            let mentionedParentID = mentionedAuthor(
                in: reply.bodyText,
                candidates: latestCommentIDByAuthor.keys
            ).flatMap { latestCommentIDByAuthor[$0] }
            children[mentionedParentID ?? rootID, default: []].append(reply)
            latestCommentIDByAuthor[normalizedAuthor(reply.authorName)] = reply.id
        }

        var ordered: [PresentedReply] = []
        func appendChildren(of parentID: String, depth: Int) {
            for reply in children[parentID] ?? [] {
                ordered.append(PresentedReply(comment: reply, depth: min(5, depth)))
                appendChildren(of: reply.id, depth: depth + 1)
            }
        }
        appendChildren(of: rootID, depth: 1)
        return ordered
    }

    private func mentionedAuthor(
        in text: String,
        candidates: Dictionary<String, String>.Keys
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "@" else { return nil }
        let mentionText = trimmed.dropFirst().lowercased()
        return candidates.sorted { $0.count > $1.count }.first { candidate in
            guard mentionText.hasPrefix(candidate) else { return false }
            let boundary = mentionText.dropFirst(candidate.count).first
            return boundary == nil
                || boundary?.isWhitespace == true
                || boundary == ":"
                || boundary == ","
        }
    }

    private func normalizedAuthor(_ author: String) -> String {
        author
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }

    private func toggleComments() {
        withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
            isExpanded.toggle()
        }
        if isExpanded && model.comments.isEmpty && !model.isLoading {
            Task { await model.load() }
        }
    }

    private func expandComments() {
        guard !isExpanded else { return }
        withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
            isExpanded = true
        }
        if model.comments.isEmpty && !model.isLoading {
            Task { await model.load() }
        }
    }
}

/// Static geometry keeps the expanded section stable while its first page arrives. Deliberately
/// avoids shimmer so loading does not add continuous animation beneath a playing video.
private struct CommentListPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(width: index == 1 ? 112 : 148, height: 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(maxWidth: index == 2 ? 210 : 280)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(width: 72, height: 10)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading comments")
    }
}
