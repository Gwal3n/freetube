import CryptoKit
import Foundation
import ImageIO

/// Anonymous, read-only DeArrow client. Branding uses a hash-prefix lookup; image generation
/// necessarily sends the video ID to DeArrow's thumbnail server. Neither path submits activity.
actor DeArrowService {
    static let shared = DeArrowService()

    private nonisolated struct CacheEntry {
        let branding: DeArrowBranding
        let expiresAt: Date
        var lastUsed: Date
    }

    nonisolated struct Payload: Decodable, Sendable {
        nonisolated struct Title: Decodable, Sendable {
            let title: String
            let original: Bool
            let votes: Int
            let locked: Bool
        }

        nonisolated struct Thumbnail: Decodable, Sendable {
            let timestamp: Double?
            let original: Bool
            let votes: Int
            let locked: Bool
        }

        let titles: [Title]
        let thumbnails: [Thumbnail]
        let randomTime: Double?
        let videoDuration: Double?

        static let empty = Payload(titles: [], thumbnails: [], randomTime: nil, videoDuration: nil)

        var replacementTitle: String? {
            guard let candidate = titles.first,
                  candidate.locked || candidate.votes >= 0,
                  !candidate.original else { return nil }
            let title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }

        func thumbnailTime(videoID: String, duration: TimeInterval?, randomFallback: Bool, isLive: Bool) -> Double? {
            if let candidate = thumbnails.first, candidate.locked || candidate.votes >= 0 {
                // An approved original thumbnail is an explicit choice, not a missing submission.
                guard !candidate.original, let time = candidate.timestamp,
                      time.isFinite, time >= 0 else { return nil }
                return time
            }
            guard randomFallback, !isLive else { return nil }
            let length = videoDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? duration
            guard let length, length.isFinite, length > 0 else { return nil }
            let fraction: Double
            if let randomTime, randomTime.isFinite, randomTime >= 0, randomTime <= 1 {
                fraction = randomTime > 0.9 ? randomTime - 0.9 : randomTime
            } else {
                // Stable per video: scrolling/reopening must not choose another frame or flood
                // the generation server with timestamps. Stay away from intros and end credits.
                let digest = SHA256.hash(data: Data(videoID.utf8))
                let seed = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                fraction = 0.05 + Double(seed) / Double(UInt32.max) * 0.8
            }
            return fraction * length
        }
    }

    private let session: URLSession
    private var cache: [String: CacheEntry] = [:]
    private var payloadCache: [String: (payload: Payload, expiresAt: Date)] = [:]
    private var inFlight: [String: Task<DeArrowBranding, Error>] = [:]
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var nextRequestAt = Date.distantPast

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.httpMaximumConnectionsPerHost = 3
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Visible rows call this independently of playback. Repeated appearances share a bounded
    /// cache and in-flight request; at most three videos are requested/generated simultaneously.
    func fetchBranding(for video: Video, includeThumbnails: Bool, randomFallback: Bool) async throws -> DeArrowBranding {
        guard video.id.count == 11,
              video.id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return .empty }
        let key = "\(video.id)|\(includeThumbnails)|\(includeThumbnails && randomFallback)|\(video.duration ?? 0)|\(video.isLive)"
        if let value = cached(key) { return value }
        if let task = inFlight[key] { return try await task.value }
        guard Date() >= nextRequestAt else { return .empty }

        await acquireSlot()
        defer { releaseSlot() }
        // A row scrolled out of view while waiting must not start another generation request.
        try Task.checkCancellation()
        if let value = cached(key) { return value }
        if let task = inFlight[key] { return try await task.value }
        guard Date() >= nextRequestAt else { return .empty }

        let task = Task { try await requestBranding(for: video, includeThumbnails: includeThumbnails, randomFallback: randomFallback) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        do {
            let result = try await task.value
            // Missing images may still be in the generation queue. Retry on a later appearance,
            // not in a polling loop. Successful images and titles can stay cached for six hours.
            let ttl: TimeInterval = includeThumbnails && result.thumbnailData == nil ? 300 : 21_600
            store(result, key: key, ttl: ttl)
            return result
        } catch {
            store(.empty, key: key, ttl: 60)
            throw error
        }
    }

    private func requestBranding(for video: Video, includeThumbnails: Bool, randomFallback: Bool) async throws -> DeArrowBranding {
        let payload = try await fetchPayload(videoID: video.id)
        var imageData: Data?
        var imageKey: String?
        if includeThumbnails, let time = payload.thumbnailTime(
            videoID: video.id, duration: video.duration, randomFallback: randomFallback, isLive: video.isLive
        ), let imageURL = Self.thumbnailURL(videoID: video.id, time: time, isLive: video.isLive) {
            // Thumbnail failure must not discard a successfully fetched replacement title.
            if let (data, response) = try? await session.data(from: imageURL),
               let http = response as? HTTPURLResponse {
                respectBackoff(http)
                if http.statusCode == 200,
                   http.mimeType?.hasPrefix("image/") == true, data.count <= 2_097_152,
                   let source = CGImageSourceCreateWithData(data as CFData, nil),
                   CGImageSourceGetCount(source) > 0 {
                    imageData = data
                    imageKey = "dearrow:\(video.id):\(time)"
                }
            }
        }
        return DeArrowBranding(title: payload.replacementTitle, thumbnailData: imageData, thumbnailCacheKey: imageKey)
    }

    private func fetchPayload(videoID: String) async throws -> Payload {
        if let entry = payloadCache[videoID], entry.expiresAt > Date() { return entry.payload }
        let digest = SHA256.hash(data: Data(videoID.utf8))
        let prefix = digest.prefix(2).map { String(format: "%02x", $0) }.joined()
        guard var components = URLComponents(string: "https://sponsor.ajay.app/api/branding/\(prefix)") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "fetchAll", value: "true")]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        respectBackoff(http)
        guard http.statusCode == 200 || http.statusCode == 404 else { throw URLError(.badServerResponse) }
        guard data.count <= 2_097_152 else { throw URLError(.cannotDecodeContentData) }
        let payload: Payload
        if http.statusCode == 404 {
            payload = .empty
        } else {
            payload = try JSONDecoder().decode([String: Payload].self, from: data)[videoID] ?? .empty
        }
        payloadCache[videoID] = (payload, Date().addingTimeInterval(21_600))
        if payloadCache.count > 128,
           let oldest = payloadCache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            payloadCache[oldest] = nil
        }
        return payload
    }

    nonisolated static func thumbnailURL(videoID: String, time: Double, isLive: Bool) -> URL? {
        guard time.isFinite, time >= 0,
              var components = URLComponents(string: "https://dearrow-thumb.ajay.app/api/v1/getThumbnail") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "videoID", value: videoID),
            URLQueryItem(name: "time", value: String(time)),
            URLQueryItem(name: "isLivestream", value: String(isLive)),
            URLQueryItem(name: "generateNow", value: "false")
        ]
        return components.url
    }

    private func cached(_ key: String) -> DeArrowBranding? {
        guard var entry = cache[key], entry.expiresAt > Date() else {
            cache[key] = nil
            return nil
        }
        entry.lastUsed = Date()
        cache[key] = entry
        return entry.branding
    }

    private func store(_ branding: DeArrowBranding, key: String, ttl: TimeInterval) {
        cache[key] = CacheEntry(branding: branding, expiresAt: Date().addingTimeInterval(ttl), lastUsed: Date())
        while cache.count > 128 || cache.values.reduce(0, { $0 + ($1.branding.thumbnailData?.count ?? 0) }) > 16_777_216 {
            guard let oldest = cache.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key else { break }
            cache[oldest] = nil
        }
    }

    private func acquireSlot() async {
        if activeRequests < 3 {
            activeRequests += 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private func releaseSlot() {
        if waiters.isEmpty {
            activeRequests -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    private func respectBackoff(_ response: HTTPURLResponse) {
        guard response.statusCode == 429 || response.statusCode == 503 else { return }
        let delay = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
        nextRequestAt = Date().addingTimeInterval(min(600, max(60, delay.isFinite ? delay : 60)))
    }
}
