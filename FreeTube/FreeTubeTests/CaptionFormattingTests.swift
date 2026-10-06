import Foundation
import XCTest

@testable import FreeTube

@MainActor
final class CaptionFormattingTests: XCTestCase {
    func testJSON3PreservesPenItalicAndColor() throws {
        let payload: [String: Any] = [
            "pens": [["iAttr": 1, "fcForeColor": "#00FF00"]],
            "events": [[
                "tStartMs": 1_000,
                "dDurationMs": 2_000,
                "segs": [
                    ["utf8": " Green ", "pPenId": 0],
                    ["utf8": "plain"]
                ]
            ]]
        ]
        let cues = CaptionJSON3Parser.parse(try JSONSerialization.data(withJSONObject: payload))

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.text, "Green plain")
        XCTAssertEqual(cues.first?.runs.first?.isItalic, true)
        XCTAssertEqual(cues.first?.runs.first?.colorRGB, 0x00FF00)
        XCTAssertEqual(cues.first?.runs.last?.isItalic, false)
    }

    func testTTMLPreservesReferencedSpanStyle() {
        let ttml = """
        <tt xmlns:tts="http://www.w3.org/ns/ttml#styling">
          <head><styling>
            <style xml:id="accent" tts:fontStyle="italic" tts:color="#FFCC00"/>
          </styling></head>
          <body><div><p begin="00:00:01.000" end="00:00:03.000"><span style="accent">Gold</span> text</p></div></body>
        </tt>
        """
        let cues = CaptionTTMLParser.parse(Data(ttml.utf8))

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.text, "Gold text")
        XCTAssertEqual(cues.first?.runs.first?.isItalic, true)
        XCTAssertEqual(cues.first?.runs.first?.colorRGB, 0xFFCC00)
        XCTAssertEqual(cues.first?.runs.last?.isItalic, false)
    }

    func testOfflineCueRoundTripRetainsTimingAndFormatting() throws {
        let original = [VideoCaptionCue(
            startTime: 1.25,
            endTime: 3.5,
            text: "Gold text",
            runs: [
                VideoCaptionRun(text: "Gold", isItalic: true, colorRGB: 0xFFCC00),
                VideoCaptionRun(text: " text", isItalic: false, colorRGB: nil)
            ]
        )]

        let restored = try JSONDecoder().decode(
            [VideoCaptionCue].self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(restored, original)
    }
}
