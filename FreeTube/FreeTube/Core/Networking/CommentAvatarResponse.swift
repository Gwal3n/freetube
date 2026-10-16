import Foundation

import YouTubeKit

/// Keeps YouTubeKit's comment parsing while reading the avatar URL from YouTube's newer author
/// field. The pinned decoder only checks `avatar.image.sources`, which is absent in current
/// anonymous comment responses. This adds no request and preserves the old field as a fallback.
nonisolated struct CommentAvatarResponse: YouTubeResponse {
    static let headersType = VideoCommentsResponse.headersType
    static let parametersValidationList = VideoCommentsResponse.parametersValidationList

    let page: VideoCommentsResponse
    let authorAvatarURLs: [String: URL]

    static func decodeJSON(json: JSON) throws -> CommentAvatarResponse {
        let page = try VideoCommentsResponse.decodeJSON(json: json)
        var authorAvatarURLs: [String: URL] = [:]

        for mutation in json["frameworkUpdates", "entityBatchUpdate", "mutations"].arrayValue {
            let payload = mutation["payload", "commentEntityPayload"]
            guard let commentID = payload["properties", "commentId"].string,
                  let rawURL = payload["author", "avatarThumbnailUrl"].string,
                  let url = URL(string: rawURL),
                  url.scheme?.lowercased() == "https" else { continue }
            authorAvatarURLs[commentID] = url
        }

        return CommentAvatarResponse(page: page, authorAvatarURLs: authorAvatarURLs)
    }

    /// Reply pages use different request headers but the same comment JSON and decoder.
    nonisolated struct Continuation: YouTubeResponse {
        static let headersType = VideoCommentsResponse.Continuation.headersType
        static let parametersValidationList = VideoCommentsResponse.Continuation.parametersValidationList

        let response: CommentAvatarResponse

        static func decodeJSON(json: JSON) throws -> Continuation {
            Continuation(response: try CommentAvatarResponse.decodeJSON(json: json))
        }
    }
}
