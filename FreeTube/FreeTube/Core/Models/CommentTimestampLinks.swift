import Foundation

/// Finds YouTube-style mm:ss and h:mm:ss timestamps without changing the comment's text.
nonisolated enum CommentTimestampLinks {
    struct Match {
        let range: NSRange
        let seconds: TimeInterval
    }

    private static let expression = try? NSRegularExpression(
        pattern: #"(?<![\d:])(?:(\d{1,2}):)?(\d{1,2}):([0-5]\d)(?![\d:])"#
    )

    static func matches(in text: String) -> [Match] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return (expression?.matches(in: text, range: fullRange) ?? []).compactMap { result in
            guard let minutes = capture(2, in: result, text: text),
                  let seconds = capture(3, in: result, text: text) else { return nil }
            let hoursValue = capture(1, in: result, text: text)
            if hoursValue != nil && minutes >= 60 { return nil }
            let hours = hoursValue ?? 0
            return Match(range: result.range, seconds: TimeInterval(hours * 3600 + minutes * 60 + seconds))
        }
    }

    private static func capture(_ index: Int, in match: NSTextCheckingResult, text: String) -> Int? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }
}
