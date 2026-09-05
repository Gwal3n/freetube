import Foundation

enum ChannelVideoSort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case popular
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest"
        case .popular: "Popular"
        case .oldest: "Oldest"
        }
    }

    /// Selects the channel's Videos surface. YouTube now exposes sorting through dynamic filter-
    /// chip continuations returned by this request, rather than distinct static params values.
    var requestParameters: String {
        "EgZ2aWRlb3PyBgQKAjoA"
    }

    var chipIndex: Int {
        switch self {
        case .newest: 0
        case .popular: 1
        case .oldest: 2
        }
    }

    func localFallback(_ videos: [Video]) -> [Video] {
        switch self {
        case .newest:
            return videos
        case .popular:
            return videos.sorted { ($0.viewCount ?? 0) > ($1.viewCount ?? 0) }
        case .oldest:
            return Array(videos.reversed())
        }
    }
}
