import Foundation
import OSLog
import YouTubeKit

protocol CommentServicing: Sendable {
    func fetchComments(videoID: String, continuation: String?) async throws -> CommentThread
    func fetchReplies(continuation: String) async throws -> CommentThread
}

/// Anonymous, read-only comment and reply loader.
final class CommentService: CommentServicing {
    private let client: YouTubeKitClient
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "CommentService")

    nonisolated init(client: YouTubeKitClient = .shared) {
        self.client = client
    }

    // MARK: - Read

    /// First call (no continuation): fetches `MoreVideoInfosResponse` to obtain the comments
    /// continuation token, then resolves the actual comments via `VideoCommentsResponse`.
    /// Subsequent pages use the continuation token directly.
    func fetchComments(videoID: String, continuation: String?) async throws -> CommentThread {
        let token: String
        if let continuation {
            token = continuation
        } else {
            do {
                let info = try await MoreVideoInfosResponse.sendThrowingRequest(
                    youtubeModel: client.model,
                    data: [.query: videoID]
                )
                guard let initial = info.commentsContinuationToken else {
                    log.notice("MoreVideoInfosResponse returned no commentsContinuationToken")
                    let availability: CommentThread.Availability = info.commentsCount == nil
                        ? .disabled
                        : .available
                    return CommentThread(
                        comments: [],
                        continuationToken: nil,
                        availability: availability
                    )
                }
                token = initial
            } catch {
                throw YouTubeServiceError.network(error)
            }
        }

        do {
            let response = try await VideoCommentsResponse.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.continuation: token]
            )
            let comments = response.results.map { Mappers.comment(from: $0) }
            return CommentThread(
                comments: comments,
                continuationToken: response.continuationToken,
                availability: .available,
                sortingModes: response.sortingModes.map {
                    CommentSortingMode(
                        label: $0.label,
                        token: $0.token,
                        isSelected: $0.isSelected
                    )
                }
            )
        } catch {
            throw YouTubeServiceError.network(error)
        }
    }

    func fetchReplies(continuation: String) async throws -> CommentThread {
        do {
            let response = try await VideoCommentsResponse.Continuation.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.continuation: continuation]
            )
            let comments = response.results.map { Mappers.comment(from: $0) }
            return CommentThread(
                comments: comments,
                continuationToken: response.continuationToken,
                availability: .available
            )
        } catch {
            throw YouTubeServiceError.network(error)
        }
    }

}
