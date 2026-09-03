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
        // Preserve YouTube's signed query byte-for-byte. Reconstructing it through URLComponents
        // can normalize percent escaping and invalidate the caption request signature.
        let separator = track.url.query == nil ? "?" : "&"
        guard let url = URL(string: track.url.absoluteString + separator + "fmt=json3") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

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
        log.info("Loaded \(cues.count, privacy: .public) caption cues for \(track.languageCode, privacy: .public)")
        return cues
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
