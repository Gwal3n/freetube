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
        guard var components = URLComponents(url: track.url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "fmt" }
        queryItems.append(URLQueryItem(name: "fmt", value: "json3"))
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let document = try JSONDecoder().decode(JSON3Document.self, from: data)
        let cues = document.events.compactMap { event -> CaptionCue? in
            guard let startMilliseconds = event.tStartMs,
                  let durationMilliseconds = event.dDurationMs else { return nil }
            let text = event.segs
                .compactMap(\.utf8)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let start = TimeInterval(startMilliseconds) / 1_000
            return CaptionCue(
                startTime: start,
                endTime: start + TimeInterval(durationMilliseconds) / 1_000,
                text: text
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
