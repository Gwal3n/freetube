import Foundation

/// One span of source caption text. Positioning and other YouTube pen attributes are intentionally
/// omitted until the renderer has a safe video-relative layout for them.
struct VideoCaptionRun: Sendable, Equatable {
    let text: String
    let isItalic: Bool
    let colorRGB: UInt32?

    static func trimmed(_ source: [VideoCaptionRun]) -> [VideoCaptionRun] {
        var runs = source.filter { !$0.text.isEmpty }
        while let first = runs.first {
            let trimmed = String(first.text.drop(while: \.isWhitespace))
            if trimmed.isEmpty {
                runs.removeFirst()
            } else {
                runs[0] = VideoCaptionRun(
                    text: trimmed, isItalic: first.isItalic, colorRGB: first.colorRGB
                )
                break
            }
        }
        while let last = runs.last {
            let trimmed = String(last.text.reversed().drop(while: \.isWhitespace).reversed())
            if trimmed.isEmpty {
                runs.removeLast()
            } else {
                runs[runs.count - 1] = VideoCaptionRun(
                    text: trimmed, isItalic: last.isItalic, colorRGB: last.colorRGB
                )
                break
            }
        }
        return runs
    }
}
