import CryptoKit
import Foundation

protocol SponsorBlockServicing: Sendable {
    func fetchSegments(videoID: String, categories: Set<SponsorBlockCategory>) async throws -> [SponsorBlockSegment]
}

/// Read-only SponsorBlock client. Lookups use the service's k-anonymity endpoint and never report
/// skips, views, votes, or any other playback activity back to SponsorBlock.
final class SponsorBlockService: SponsorBlockServicing, @unchecked Sendable {
    private final class CacheEntry: NSObject {
        let segments: [SponsorBlockSegment]

        init(segments: [SponsorBlockSegment]) {
            self.segments = segments
        }
    }

    private struct SegmentPayload: Decodable {
        let segment: [Double]
        let uuid: String
        let category: String
        let actionType: String?

        private enum CodingKeys: String, CodingKey {
            case segment
            case uuid = "UUID"
            case category
            case actionType
        }
    }

    private struct VideoPayload: Decodable {
        let videoID: String
        let segments: [SegmentPayload]
    }

    private let session: URLSession
    private let cache = NSCache<NSString, CacheEntry>()

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 64
    }

    func fetchSegments(
        videoID: String,
        categories: Set<SponsorBlockCategory>
    ) async throws -> [SponsorBlockSegment] {
        guard !videoID.isEmpty, !categories.isEmpty else { return [] }
        let categoryValues = categories.map(\.rawValue).sorted()
        let cacheKey = "\(videoID)|\(categoryValues.joined(separator: ","))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.segments
        }

        let digest = SHA256.hash(data: Data(videoID.utf8))
        let prefix = digest.prefix(2).map { String(format: "%02x", $0) }.joined()
        guard var components = URLComponents(
            string: "https://sponsor.ajay.app/api/skipSegments/\(prefix)"
        ) else { throw URLError(.badURL) }
        let categoriesData = try JSONEncoder().encode(categoryValues)
        guard let categoriesJSON = String(data: categoriesData, encoding: .utf8) else {
            throw URLError(.cannotEncodeContentData)
        }
        components.queryItems = [URLQueryItem(name: "categories", value: categoriesJSON)]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 { return [] }
            throw URLError(.badServerResponse)
        }
        guard data.count <= 1_048_576 else { throw URLError(.cannotDecodeContentData) }

        let payload = try JSONDecoder().decode([VideoPayload].self, from: data)
        let allowed = Set(categoryValues)
        let result = payload
            .first(where: { $0.videoID == videoID })?
            .segments
            .compactMap { item -> SponsorBlockSegment? in
                guard item.segment.count == 2,
                      allowed.contains(item.category),
                      item.actionType == nil || item.actionType == "skip",
                      let category = SponsorBlockCategory(rawValue: item.category) else { return nil }
                let start = item.segment[0]
                let end = item.segment[1]
                guard start.isFinite, end.isFinite, start >= 0, end > start else { return nil }
                return SponsorBlockSegment(
                    id: item.uuid,
                    startTime: start,
                    endTime: end,
                    category: category
                )
            }
            .sorted { $0.startTime < $1.startTime } ?? []
        if !result.isEmpty { cache.setObject(CacheEntry(segments: result), forKey: cacheKey) }
        return result
    }
}
