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
