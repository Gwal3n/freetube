import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class CommentsViewModel {
    let videoID: String
    private(set) var comments: [Comment] = []
    private(set) var continuationToken: String?
    private(set) var isLoading: Bool = false
    private(set) var commentsDisabled = false
    private(set) var teaserText: String?
    private(set) var repliesByCommentID: [String: [Comment]] = [:]
    private(set) var replyContinuationTokens: [String: String] = [:]
    private(set) var loadingReplyCommentIDs: Set<String> = []
    var errorState: ErrorState?

    private let service: any CommentServicing

    init(videoID: String, service: any CommentServicing = CommentService()) {
        self.videoID = videoID
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let thread = try await VideoContentPrefetchStore.shared.fetchComments(videoID: videoID)
            comments = thread.comments
            continuationToken = thread.continuationToken
            commentsDisabled = thread.availability == .disabled
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    /// Loads only the shared watch-page metadata. Unlike `load()`, this does not fetch the comments
    /// continuation when YouTubeKit decoded its native teaser. YouTube currently emits more than
    /// one teaser JSON shape, while b5i only decodes the older `simpleText` form; when that field is
    /// absent, fall back to the first top-level comment and retain the page for instant expansion.
    func loadTeaser() async {
        guard teaserText == nil else { return }
        do {
            let details = try await VideoContentPrefetchStore.shared.fetchDetails(videoID: videoID)
            let nativeTeaser = details.teaserCommentText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let nativeTeaser, !nativeTeaser.isEmpty {
                teaserText = nativeTeaser
                return
            }

            let thread = try await VideoContentPrefetchStore.shared.fetchComments(videoID: videoID)
            comments = thread.comments
            continuationToken = thread.continuationToken
            commentsDisabled = thread.availability == .disabled
            teaserText = thread.comments.first?.bodyText
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // The teaser is optional polish. Full comments retain their ordinary error handling.
        }
    }

    /// YouTube's teaser has no comment ID. If its excerpt occurs in a loaded full comment, place
    /// that comment first so expanding the preview reveals the complete text immediately.
    var commentsForDisplay: [Comment] {
        guard let teaser = teaserText, !teaser.isEmpty,
              let matchIndex = comments.firstIndex(where: { comment in
                  Self.matchesTeaser(teaser, commentBody: comment.bodyText)
              }), matchIndex != comments.startIndex else { return comments }
        var ordered = comments
        let match = ordered.remove(at: matchIndex)
        ordered.insert(match, at: 0)
        return ordered
    }

    private static func matchesTeaser(_ teaser: String, commentBody: String) -> Bool {
        let excerpt = teaser
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".…"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !excerpt.isEmpty, !commentBody.isEmpty else { return false }
        return commentBody.localizedCaseInsensitiveContains(excerpt)
            || excerpt.localizedCaseInsensitiveContains(commentBody)
    }

    func loadMore() async {
        guard let token = continuationToken, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let thread = try await service.fetchComments(videoID: videoID, continuation: token)
            comments.append(contentsOf: thread.comments)
            continuationToken = thread.continuationToken
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func loadReplies(for comment: Comment) async {
        guard repliesByCommentID[comment.id] == nil,
              let token = comment.replyContinuationToken,
              !loadingReplyCommentIDs.contains(comment.id) else { return }
        await fetchReplies(for: comment.id, continuation: token, appending: false)
    }

    func loadMoreReplies(for comment: Comment) async {
        guard let token = replyContinuationTokens[comment.id],
              !loadingReplyCommentIDs.contains(comment.id) else { return }
        await fetchReplies(for: comment.id, continuation: token, appending: true)
    }

    private func fetchReplies(for commentID: String, continuation: String, appending: Bool) async {
        loadingReplyCommentIDs.insert(commentID)
        defer { loadingReplyCommentIDs.remove(commentID) }
        do {
            let thread = try await service.fetchReplies(continuation: continuation)
            if appending {
                repliesByCommentID[commentID, default: []].append(contentsOf: thread.comments)
            } else {
                repliesByCommentID[commentID] = thread.comments
            }
            if let nextToken = thread.continuationToken {
                replyContinuationTokens[commentID] = nextToken
            } else {
                replyContinuationTokens.removeValue(forKey: commentID)
            }
        } catch {
            errorState = ErrorState(from: error)
        }
    }

}
