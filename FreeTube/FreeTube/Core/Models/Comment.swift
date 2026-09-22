import Foundation

struct Comment: Identifiable, Hashable, Sendable {
    let id: String
    let authorName: String
    let authorChannelID: String?
    let authorThumbnailURL: URL?
    let bodyText: String
    let likeCount: Int
    let isLikedByUser: Bool
    let isDislikedByUser: Bool
    let isAuthoredByUser: Bool
    let publishedRelative: String
    let replyCount: Int
    let replyContinuationToken: String?
}

struct CommentThread: Sendable {
    enum Availability: Equatable, Sendable {
        case available
        case disabled
    }

    let comments: [Comment]
    let continuationToken: String?
    let availability: Availability
    let sortingModes: [CommentSortingMode]

    init(
        comments: [Comment],
        continuationToken: String?,
        availability: Availability,
        sortingModes: [CommentSortingMode] = []
    ) {
        self.comments = comments
        self.continuationToken = continuationToken
        self.availability = availability
        self.sortingModes = sortingModes
    }
}

struct CommentSortingMode: Identifiable, Hashable, Sendable {
    let label: String
    let token: String
    let isSelected: Bool

    var id: String { token }
}
