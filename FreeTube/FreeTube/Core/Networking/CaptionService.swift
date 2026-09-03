import Foundation
import OSLog

protocol CaptionServicing: Sendable {
    func fetchCues(for track: VideoCaptionTrack) async throws -> [CaptionCue]
}

/// Downloads YouTube's JSON3 timed-text document and maps it into dependency-neutral cues.
final class CaptionService: CaptionServicing, @unchecked Sendable {
    private let session: URLSession
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "CaptionService")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCues(for track: VideoCaptionTrack) async throws -> [CaptionCue] {
        let jsonURL = try captionURL(from: track.url, format: "json3")
        if let jsonData = try? await fetchData(from: jsonURL),
           let cues = try? decodeJSON3(jsonData),
           !cues.isEmpty {
            log.info("Loaded \(cues.count, privacy: .public) JSON3 caption cues for \(track.languageCode, privacy: .public)")
            return cues
        }

        // Some caption endpoints continue returning srv3/XML despite the requested format. VTT is
        // intentionally a second request so the primary JSON path stays cheap and strongly typed.
        let webVTTURL = try captionURL(from: track.url, format: "vtt")
        let webVTTData = try await fetchData(from: webVTTURL)
        let cues = decodeWebVTT(webVTTData)
        guard !cues.isEmpty else { throw URLError(.cannotDecodeContentData) }
        log.info("Loaded \(cues.count, privacy: .public) WebVTT caption cues for \(track.languageCode, privacy: .public)")
        return cues
    }

    /// Replaces an existing `fmt` value without reconstructing or normalizing the rest of the
    /// signed query. Appending a duplicate parameter is insufficient because YouTube may honor
    /// the original `fmt=srv3` value first.
    private func captionURL(from sourceURL: URL, format: String) throws -> URL {
        var value = sourceURL.absoluteString
        if let range = value.range(
            of: #"[?&]fmt=[^&#]*"#,
            options: .regularExpression
        ) {
            let separator = value[range.lowerBound]
            value.replaceSubrange(range, with: "\(separator)fmt=\(format)")
        } else if let fragmentIndex = value.firstIndex(of: "#") {
            let separator = sourceURL.query == nil ? "?" : "&"
            value.insert(contentsOf: separator + "fmt=\(format)", at: fragmentIndex)
        } else {
            value += (sourceURL.query == nil ? "?" : "&") + "fmt=\(format)"
        }
        guard let url = URL(string: value) else { throw URLError(.badURL) }
        return url
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty else { throw URLError(.zeroByteResource) }
        return data
    }

    private func decodeJSON3(_ data: Data) throws -> [CaptionCue] {
        let document = try JSONDecoder().decode(JSON3Document.self, from: data)
        let timedLines = document.events.compactMap { event -> TimedLine? in
            guard let startMilliseconds = event.tStartMs else { return nil }
            let text = event.segs
                .compactMap(\.utf8)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TimedLine(
                startMilliseconds: startMilliseconds,
                durationMilliseconds: event.dDurationMs,
                text: text
            )
        }
        let cues = timedLines.enumerated().map { index, line in
            let start = TimeInterval(line.startMilliseconds) / 1_000
            let inferredEndMilliseconds = timedLines.indices.contains(index + 1)
                ? timedLines[index + 1].startMilliseconds
                : line.startMilliseconds + 5_000
            let explicitEndMilliseconds = line.durationMilliseconds.map {
                line.startMilliseconds + $0
            }
            let endMilliseconds = max(
                line.startMilliseconds + 100,
                explicitEndMilliseconds ?? inferredEndMilliseconds
            )
            return CaptionCue(
                startTime: start,
                endTime: TimeInterval(endMilliseconds) / 1_000,
                text: line.text
            )
        }
        return cues
    }

    private func decodeWebVTT(_ data: Data) -> [CaptionCue] {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
        return text.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let timing = lines[timingIndex].components(separatedBy: "-->")
            guard timing.count == 2,
                  let start = parseWebVTTTime(timing[0]),
                  let end = parseWebVTTTime(String(timing[1].split(separator: " ").first ?? "")),
                  end > start else { return nil }
            let cueText = lines.dropFirst(timingIndex + 1)
                .joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cueText.isEmpty else { return nil }
            return CaptionCue(startTime: start, endTime: end, text: cueText)
        }
    }

    private func parseWebVTTTime(_ rawValue: String) -> TimeInterval? {
        let parts = rawValue.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2 || parts.count == 3,
              let seconds = Double(parts[parts.count - 1]),
              let minutes = Double(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? Double(parts[0]) ?? 0 : 0
        return hours * 3_600 + minutes * 60 + seconds
    }
}

private struct JSON3Document: Decodable {
    let events: [JSON3Event]
}

private struct JSON3Event: Decodable {
    let tStartMs: Int?
    let dDurationMs: Int?
    let segs: [JSON3Segment]

    private enum CodingKeys: String, CodingKey {
        case tStartMs
        case dDurationMs
        case segs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tStartMs = try container.decodeIfPresent(Int.self, forKey: .tStartMs)
        dDurationMs = try container.decodeIfPresent(Int.self, forKey: .dDurationMs)
        segs = try container.decodeIfPresent([JSON3Segment].self, forKey: .segs) ?? []
    }
}

private struct JSON3Segment: Decodable {
    let utf8: String?
}

private struct TimedLine {
    let startMilliseconds: Int
    let durationMilliseconds: Int?
    let text: String
}
