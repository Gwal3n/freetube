import Foundation
import XCTest

@testable import FreeTube

@MainActor
final class CommentAvatarResponseTests: XCTestCase {
    func testMapsCurrentAuthorAvatarFieldWithoutChangingCommentParsing() throws {
        let data = Data(#"""
        {
          "onResponseReceivedEndpoints": [{
            "reloadContinuationItemsCommand": {
              "continuationItems": [{
                "commentThreadRenderer": {
                  "commentViewModel": {
                    "commentViewModel": {"commentId": "comment-1", "commentKey": "entity-1"}
                  }
                }
              }]
            }
          }],
          "frameworkUpdates": {
            "entityBatchUpdate": {
              "mutations": [{
                "entityKey": "entity-1",
                "payload": {
                  "commentEntityPayload": {
                    "properties": {
                      "commentId": "comment-1",
                      "content": {"content": "A comment"}
                    },
                    "author": {
                      "channelId": "UCexample",
                      "displayName": "Example",
                      "avatarThumbnailUrl": "https://yt3.ggpht.com/avatar-example"
                    }
                  }
                }
              }]
            }
          }
        }
        """#.utf8)

        let response = try CommentAvatarResponse.decodeData(data: data)
        let comment = try XCTUnwrap(response.page.results.first)
        let mapped = Mappers.comment(
            from: comment,
            authorAvatarURL: response.authorAvatarURLs[comment.commentIdentifier]
        )

        XCTAssertEqual(mapped.authorName, "Example")
        XCTAssertEqual(mapped.bodyText, "A comment")
        XCTAssertEqual(mapped.authorThumbnailURL?.absoluteString, "https://yt3.ggpht.com/avatar-example")
    }
}
