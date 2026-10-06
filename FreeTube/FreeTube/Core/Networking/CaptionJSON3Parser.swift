import Foundation

/// Reads the small part of YouTube JSON3 needed for styled captions. The normal b5i decoder
/// remains the plain-text fallback if YouTube changes this optional styling representation.
enum CaptionJSON3Parser {
    static func parse(_ data: Data) -> [VideoCaptionCue] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        let pens = root["pens"] as? [[String: Any]] ?? []

        let candidates: [(start: TimeInterval, duration: TimeInterval?, runs: [VideoCaptionRun])] =
            events.compactMap { event in
                guard let startMilliseconds = (event["tStartMs"] as? NSNumber)?.doubleValue,
                      startMilliseconds.isFinite, startMilliseconds >= 0,
                      let segments = event["segs"] as? [[String: Any]] else { return nil }
                let eventPenID = (event["pPenId"] as? NSNumber)?.intValue
                let eventPen = eventPenID.flatMap { pens.indices.contains($0) ? pens[$0] : nil }
                let runs = VideoCaptionRun.trimmed(segments.compactMap { segment in
                    guard let text = segment["utf8"] as? String, !text.isEmpty else { return nil }
                    let penID = (segment["pPenId"] as? NSNumber)?.intValue
                    let pen = penID.flatMap { pens.indices.contains($0) ? pens[$0] : nil }
                    return VideoCaptionRun(
                        text: text,
                        isItalic: ((pen?["iAttr"] ?? eventPen?["iAttr"]) as? NSNumber)?.intValue == 1,
                        colorRGB: CaptionSourceColor.rgb(
                            from: pen?["fcForeColor"] ?? eventPen?["fcForeColor"]
                        )
                    )
                })
                guard !runs.isEmpty else { return nil }
                let durationMilliseconds = (event["dDurationMs"] as? NSNumber)?.doubleValue
                return (
                    start: startMilliseconds / 1_000,
                    duration: durationMilliseconds.map { $0 / 1_000 },
                    runs: runs
                )
            }
            .sorted { $0.start < $1.start }

        return candidates.enumerated().compactMap { index, candidate in
            let nextStart = candidates.indices.contains(index + 1)
                ? candidates[index + 1].start : candidate.start + 3
            let duration = candidate.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                ?? max(0.1, nextStart - candidate.start)
            let text = candidate.runs.map(\.text).joined()
            guard !text.isEmpty else { return nil }
            return VideoCaptionCue(
                startTime: candidate.start,
                endTime: min(candidate.start + duration, max(nextStart, candidate.start + 0.1)),
                text: text,
                runs: candidate.runs
            )
        }
    }
}
