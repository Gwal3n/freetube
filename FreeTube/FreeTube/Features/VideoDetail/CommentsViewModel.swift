import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class CommentsViewModel {
    struct TimedComment {
        let time: TimeInterval
        let comment: Comment
    }

    let videoID: String
    private(set) var comments: [Comment] = []
    private(set) var continuationToken: String?
    private(set) var isLoading: Bool = false
    private(set) var commentsDisabled = false
    private(set) var sortingModes: [CommentSortingMode] = []
    private(set) var teaserText: String?
    private(set) var timedComments: [TimedComment] = []
    private var focusedCommentID: String?
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
            refreshTimedComments()
            continuationToken = thread.continuationToken
            commentsDisabled = thread.availability == .disabled
            sortingModes = thread.sortingModes
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    /// Keep the native excerpt as a fallback, then use the shared first comments page for
    /// playback-time matches. The preview setting is opt-in, and expansion reuses this page.
    func loadTeaser(onlyTimed: Bool = false) async {
        guard comments.isEmpty || (!onlyTimed && teaserText == nil) else { return }
        do {
            if !onlyTimed && teaserText == nil {
                let details = try await VideoContentPrefetchStore.shared.fetchDetails(videoID: videoID)
                let nativeTeaser = details.teaserCommentText?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let nativeTeaser, !nativeTeaser.isEmpty {
                    teaserText = nativeTeaser
                }
            }

            if comments.isEmpty {
                let thread = try await VideoContentPrefetchStore.shared.fetchComments(videoID: videoID)
                comments = thread.comments
                refreshTimedComments()
                continuationToken = thread.continuationToken
                commentsDisabled = thread.availability == .disabled
                sortingModes = thread.sortingModes
            }
            if !onlyTimed && teaserText == nil {
                teaserText = comments.first?.bodyText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // The teaser is optional polish. Full comments retain their ordinary error handling.
        }
    }

    /// YouTube's teaser has no comment ID. If its excerpt occurs in a loaded full comment, place
    /// that comment first so expanding the preview reveals the complete text immediately.
    var commentsForDisplay: [Comment] {
        if let focusedCommentID,
           let matchIndex = comments.firstIndex(where: { $0.id == focusedCommentID }),
           matchIndex != comments.startIndex {
            var ordered = comments
            ordered.insert(ordered.remove(at: matchIndex), at: 0)
            return ordered
        }
        // The featured excerpt belongs to YouTube's default (normally Top) ordering. Never move it
        // ahead of the server's results after the user explicitly chooses another sort mode.
        let selectedSortID = sortingModes.first(where: \.isSelected)?.id
        guard selectedSortID == nil || selectedSortID == sortingModes.first?.id else {
            return comments
        }
        guard let teaser = teaserText, !teaser.isEmpty,
              let matchIndex = comments.firstIndex(where: { comment in
                  Self.matchesTeaser(teaser, commentBody: comment.bodyText)
              }), matchIndex != comments.startIndex else { return comments }
        var ordered = comments
        let match = ordered.remove(at: matchIndex)
        ordered.insert(match, at: 0)
        return ordered
    }

    func focusComment(_ id: String?) {
        focusedCommentID = id
    }

    /// Only one-timestamp comments are suitable for a brief preview. Chapter lists and dense
    /// timestamp indexes would otherwise appear to match throughout the video.
    private func refreshTimedComments() {
        timedComments = comments.compactMap { comment in
            let matches = CommentTimestampLinks.matches(in: comment.bodyText)
            guard matches.count == 1, let match = matches.first else { return nil }
            return TimedComment(time: match.seconds, comment: comment)
        }
    }

    func featuredComment(near playbackTime: TimeInterval) -> TimedComment? {
        guard playbackTime.isFinite else { return nil }
        return timedComments
            .filter { $0.time <= playbackTime && playbackTime - $0.time <= 30 }
            .min { left, right in
                let leftDistance = playbackTime - left.time
                let rightDistance = playbackTime - right.time
                return leftDistance == rightDistance
                    ? left.comment.likeCount > right.comment.likeCount
                    : leftDistance < rightDistance
            }
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
            refreshTimedComments()
            continuationToken = thread.continuationToken
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func selectSortingMode(_ mode: CommentSortingMode) async {
        guard !mode.isSelected, !isLoading else { return }
        let previousComments = comments
        let previousContinuationToken = continuationToken
        let previousSortingModes = sortingModes
        let previousReplies = repliesByCommentID
        let previousReplyTokens = replyContinuationTokens
        isLoading = true
        comments = []
        timedComments = []
        focusedCommentID = nil
        continuationToken = nil
        repliesByCommentID = [:]
        replyContinuationTokens = [:]
        sortingModes = sortingModes.map {
            CommentSortingMode(label: $0.label, token: $0.token, isSelected: $0.id == mode.id)
        }
        defer { isLoading = false }

        do {
            let thread = try await service.fetchComments(videoID: videoID, continuation: mode.token)
            comments = thread.comments
            refreshTimedComments()
            continuationToken = thread.continuationToken
            commentsDisabled = thread.availability == .disabled
            if !thread.sortingModes.isEmpty {
                sortingModes = thread.sortingModes
            }
        } catch {
            comments = previousComments
            refreshTimedComments()
            continuationToken = previousContinuationToken
            sortingModes = previousSortingModes
            repliesByCommentID = previousReplies
            replyContinuationTokens = previousReplyTokens
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
