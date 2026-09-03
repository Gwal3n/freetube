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
    var translations: [String: String] = [:]

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

    func toggleLike(_ comment: Comment) async {
        do {
            if comment.isLikedByUser {
                try await service.removeLike(commentID: comment.id)
            } else {
                try await service.like(commentID: comment.id)
            }
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func toggleDislike(_ comment: Comment) async {
        do {
            if comment.isDislikedByUser {
                try await service.removeDislike(commentID: comment.id)
            } else {
                try await service.dislike(commentID: comment.id)
            }
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func reply(to comment: Comment, text: String) async {
        do {
            let new = try await service.reply(commentID: comment.id, text: text)
            comments.insert(new, at: 0)
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func post(_ text: String) async {
        do {
            let new = try await service.create(videoID: videoID, text: text)
            comments.insert(new, at: 0)
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func edit(_ comment: Comment, text: String) async {
        do {
            let updated = try await service.edit(commentID: comment.id, text: text)
            if let idx = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[idx] = updated
            }
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func delete(_ comment: Comment) async {
        do {
            try await service.delete(commentID: comment.id)
            comments.removeAll { $0.id == comment.id }
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func translate(_ comment: Comment, targetLanguage: String = Locale.current.language.languageCode?.identifier ?? "en") async {
        do {
            translations[comment.id] = try await service.translate(commentID: comment.id, targetLanguage: targetLanguage)
        } catch {
            errorState = ErrorState(from: error)
        }
    }
}
