import CryptoKit
import Foundation

protocol SponsorBlockServicing: Sendable {
    func fetchSegments(videoID: String, categories: Set<SponsorBlockCategory>) async throws -> [SponsorBlockSegment]
    func clearCache()
}

extension SponsorBlockServicing {
    func clearCache() {}
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
        let description: String?

        private enum CodingKeys: String, CodingKey {
            case segment
            case uuid = "UUID"
            case category
            case actionType
            case description
        }
    }

    private struct VideoPayload: Decodable {
        let videoID: String
        let segments: [SegmentPayload]
    }

    private let session: URLSession
    private let cache = NSCache<NSString, CacheEntry>()

    init(session: URLSession? = nil) {
        self.session = session ?? AnonymousURLSession.make()
        cache.countLimit = 64
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    func fetchSegments(
        videoID: String,
        categories: Set<SponsorBlockCategory>
    ) async throws -> [SponsorBlockSegment] {
        guard !videoID.isEmpty, !categories.isEmpty else { return [] }
        let categoryValues = categories.map(\.rawValue).sorted()
        let actionTypeValues = Self.actionTypes(for: categories)
        let cacheKey = "\(videoID)|\(categoryValues.joined(separator: ","))|\(actionTypeValues.joined(separator: ","))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.segments
        }

        let digest = SHA256.hash(data: Data(videoID.utf8))
        let prefix = digest.prefix(2).map { String(format: "%02x", $0) }.joined()
        guard var components = URLComponents(
            string: "https://sponsor.ajay.app/api/skipSegments/\(prefix)"
        ) else { throw URLError(.badURL) }
        // The API defaults to actionTypes=["skip"], which omits chapters, highlights (poi),
        // and full-video labels. Request only the action types our enabled categories need.
        let categoriesData = try JSONEncoder().encode(categoryValues)
        let actionTypesData = try JSONEncoder().encode(actionTypeValues)
        guard let categoriesJSON = String(data: categoriesData, encoding: .utf8),
              let actionTypesJSON = String(data: actionTypesData, encoding: .utf8) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "categories", value: categoriesJSON),
            URLQueryItem(name: "actionTypes", value: actionTypesJSON),
        ]
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

        let result = try Self.decodeSegments(data, videoID: videoID, categories: categories)
        if !result.isEmpty { cache.setObject(CacheEntry(segments: result), forKey: cacheKey) }
        return result
    }

    /// Action types required for the enabled categories. Server default is only `skip`.
    static func actionTypes(for categories: Set<SponsorBlockCategory>) -> [String] {
        var types: [String] = []
        let skipCategories: Set<SponsorBlockCategory> = [
            .sponsor, .selfPromotion, .interaction, .intro, .outro, .preview, .hook, .musicOfftopic, .filler
        ]
        if !categories.isDisjoint(with: skipCategories) { types.append("skip") }
        if categories.contains(where: \.supportsFullVideoLabel) { types.append("full") }
        if categories.contains(.highlight) { types.append("poi") }
        if categories.contains(.chapter) { types.append("chapter") }
        return types
    }

    /// Keeps SponsorBlock's chapter and full-video actions distinct from skippable ranges.
    static func decodeSegments(
        _ data: Data,
        videoID: String,
        categories: Set<SponsorBlockCategory>
    ) throws -> [SponsorBlockSegment] {
        let payload = try JSONDecoder().decode([VideoPayload].self, from: data)
        let result = payload
            .first(where: { $0.videoID == videoID })?
            .segments
            .compactMap { item -> SponsorBlockSegment? in
                guard item.segment.count == 2,
                      let category = SponsorBlockCategory(rawValue: item.category),
                      categories.contains(category) else { return nil }
                let start = item.segment[0]
                let end = item.segment[1]
                guard start.isFinite, end.isFinite, start >= 0 else { return nil }
                let title: String?
                let isFullVideoLabel: Bool
                switch item.actionType {
                case "full":
                    guard category.supportsFullVideoLabel, start == 0, end == 0 else { return nil }
                    title = nil
                    isFullVideoLabel = true
                case "poi":
                    guard category == .highlight, end == start else { return nil }
                    title = nil
                    isFullVideoLabel = false
                case "chapter":
                    guard category == .chapter, end > start,
                          let description = item.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !description.isEmpty else { return nil }
                    title = description
                    isFullVideoLabel = false
                case nil, "skip":
                    guard category != .exclusiveAccess, category != .highlight, category != .chapter,
                          end > start else { return nil }
                    title = nil
                    isFullVideoLabel = false
                default:
                    return nil
                }
                return SponsorBlockSegment(
                    id: item.uuid,
                    startTime: start,
                    endTime: end,
                    category: category,
                    title: title,
                    isFullVideoLabel: isFullVideoLabel
                )
            }
            .sorted { $0.startTime < $1.startTime } ?? []
        return result
    }
}
