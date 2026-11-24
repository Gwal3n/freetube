import XCTest
@testable import FreeTube

final class LiveChatDecodingTests: XCTestCase {
    func testBootstrapExtractorReadsKeyVersionAndContinuation() {
        let html = """
        <script>ytcfg.set({"INNERTUBE_API_KEY":"AIzaSyTestKey123","INNERTUBE_CONTEXT_CLIENT_VERSION":"2.20251119.01.00"});
        var ytInitialData = {"contents":{"liveChatRenderer":{"continuations":[{"timedContinuationData":{"timeoutMs":5000,"continuation":"0ofMyAOpContinuationTokenWithEnoughLength0123456789"}}]}}};
        </script>
        """
        let bootstrap = LiveChatBootstrapExtractor.extract(from: html)
        XCTAssertEqual(bootstrap?.apiKey, "AIzaSyTestKey123")
        XCTAssertEqual(bootstrap?.clientVersion, "2.20251119.01.00")
        XCTAssertEqual(
            bootstrap?.continuation,
            "0ofMyAOpContinuationTokenWithEnoughLength0123456789"
        )
    }

    func testPageDecoderReadsTextAndSuperChat() throws {
        let json = """
        {
          "continuationContents": {
            "liveChatContinuation": {
              "actions": [
                {
                  "addChatItemAction": {
                    "item": {
                      "liveChatTextMessageRenderer": {
                        "id": "msg1",
                        "authorName": { "simpleText": "Alice" },
                        "message": { "runs": [{ "text": "hello" }] }
                      }
                    }
                  }
                },
                {
                  "addChatItemAction": {
                    "item": {
                      "liveChatPaidMessageRenderer": {
                        "id": "msg2",
                        "authorName": { "simpleText": "Bob" },
                        "message": { "runs": [{ "text": "thanks" }] },
                        "purchaseAmountText": { "simpleText": "$5.00" }
                      }
                    }
                  }
                }
              ],
              "continuations": [
                {
                  "timedContinuationData": {
                    "timeoutMs": 2000,
                    "continuation": "next-token"
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: json)
        let page = LiveChatPageDecoder.decode(root)
        XCTAssertEqual(page.messages.count, 2)
        XCTAssertEqual(page.messages[0].authorName, "Alice")
        XCTAssertEqual(page.messages[0].text, "hello")
        XCTAssertEqual(page.messages[0].kind, .text)
        XCTAssertEqual(page.messages[1].kind, .superChat)
        XCTAssertEqual(page.messages[1].amountText, "$5.00")
        XCTAssertEqual(page.continuation, "next-token")
        XCTAssertEqual(page.timeout, .milliseconds(2000))
    }
}
